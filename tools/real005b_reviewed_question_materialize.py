from __future__ import annotations

import argparse
import importlib.util
import json
import os
import subprocess
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import psycopg
from psycopg.rows import dict_row
from pypdf import PdfReader

from guangzhou_physics_v2_materialize import (
    BATCH_KEY,
    C002_IMPORT_KEY,
    EXPECTED_COUNTS,
    OLD_WORKFLOW_KEY,
    WORKFLOW_KEY,
    YEARS,
    YearRegionPlan,
    answer_region_mode,
    build_blocks,
    extract_compact_choice_sequence,
    extract_numbered_answer_sections,
    flatten_question_regions,
    load_c003_candidates,
    load_question_region_plans,
    locate_answer_pages_from_texts,
    stable_id,
    validate_candidate_coverage,
    validate_candidate_content,
)
from repair_c003_question_stems_from_regions import extract_question_stem_from_region_text


def rows(conn: psycopg.Connection[Any], sql: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    with conn.cursor(row_factory=dict_row) as cursor:
        cursor.execute(sql, params)
        return list(cursor.fetchall())


def scalar(conn: psycopg.Connection[Any], sql: str, params: tuple[Any, ...] = ()) -> int:
    with conn.cursor() as cursor:
        cursor.execute(sql, params)
        result = cursor.fetchone()
        return int(result[0]) if result else 0


def build_connection_kwargs(
    host: str,
    port: int,
    database: str,
    user: str,
    password: str,
) -> dict[str, Any]:
    kwargs: dict[str, Any] = {
        "host": host,
        "port": port,
        "dbname": database,
        "user": user,
    }
    if password:
        kwargs["password"] = password
    return kwargs


def text_value(conn: psycopg.Connection[Any], sql: str, params: tuple[Any, ...] = ()) -> str:
    with conn.cursor() as cursor:
        cursor.execute(sql, params)
        result = cursor.fetchone()
        return str(result[0]) if result and result[0] is not None else ""


def workflow_fingerprint(conn: psycopg.Connection[Any]) -> str:
    return text_value(
        conn,
        """
        with target as (
            select id from question_items where custom_fields->>'sourceWorkflowKey'=%s
        ), parts as (
            select 'q' kind, id::text key, row_to_json(q)::text value from question_items q where id in (select id from target)
            union all
            select 'b', id::text, row_to_json(b)::text from question_blocks b where question_item_id in (select id from target)
            union all
            select 'a', id::text, row_to_json(a)::text from question_assets a where question_item_id in (select id from target)
            union all
            select 'c', id::text, row_to_json(c)::text from cut_candidates c where suggested_question_item_id in (select id from target)
            union all
            select 'r', id::text, row_to_json(r)::text from review_queue_items r where payload->>'sourceWorkflowKey'=%s
        )
        select md5(coalesce(string_agg(kind || ':' || key || ':' || value, E'\n' order by kind,key),'')) from parts
        """,
        (WORKFLOW_KEY, WORKFLOW_KEY),
    )


def load_source_documents(conn: psycopg.Connection[Any], file_root: Path) -> dict[tuple[int, str], dict[str, Any]]:
    source_rows = rows(
        conn,
        """
        select sd.id, sd.year, sd.source_type, sd.source_title, sd.file_asset_id,
               fa.relative_path, fa.sha256
        from source_documents sd
        join file_assets fa on fa.id = sd.file_asset_id
        where sd.material_batch_key = %s
          and sd.year between 2015 and 2025
          and sd.source_type in ('local_exam_paper', 'answer_or_solution', 'exam_analysis_report')
        order by sd.year, sd.source_type, sd.created_at desc
        """,
        (BATCH_KEY,),
    )
    result: dict[tuple[int, str], dict[str, Any]] = {}
    for row in source_rows:
        key = (int(row["year"]), str(row["source_type"]))
        if key in result:
            raise ValueError(f"duplicate_v2_source_document:{key}")
        path = file_root / str(row["relative_path"])
        if not path.is_file():
            raise FileNotFoundError(f"file_store_asset_missing:{path}")
        row["path"] = path
        result[key] = row
    expected = {(year, source_type) for year in YEARS for source_type in ("local_exam_paper", "answer_or_solution", "exam_analysis_report")}
    missing = sorted(expected - set(result))
    if missing:
        raise ValueError(f"v2_source_documents_missing:{missing}")
    return result


def select_2015_candidate_rows(candidate_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[int, list[dict[str, Any]]] = {}
    for row in candidate_rows:
        custom = row.get("custom_fields") or {}
        number = int(custom["questionNo"])
        grouped.setdefault(number, []).append(row)

    selected: list[dict[str, Any]] = []
    for number, alternatives in sorted(grouped.items()):
        current = [
            row
            for row in alternatives
            if str((row.get("custom_fields") or {}).get("sourceWorkflowKey") or "") == WORKFLOW_KEY
        ]
        preferred = current if current else alternatives
        if len(preferred) != 1:
            raise ValueError(f"duplicate_2015_candidate:{number}")
        selected.append(preferred[0])
    return selected


def extract_2015_candidate_stem(blocks: list[dict[str, Any]], question_number: int) -> str:
    stem = next(
        (str(block.get("content", {}).get("text") or "") for block in blocks if block.get("type") == "stem"),
        "",
    )
    return extract_question_stem_from_region_text(stem, question_number)


def load_2015_candidates(conn: psycopg.Connection[Any]) -> tuple[dict[tuple[int, int], dict[str, Any]], dict[int, uuid.UUID]]:
    result: dict[tuple[int, int], dict[str, Any]] = {}
    ids: dict[int, uuid.UUID] = {}
    old_rows = rows(
        conn,
        """
        select id, question_type, default_score, blocks, custom_fields, quality_signals
        from question_items
        where custom_fields->>'sourceWorkflowKey' in (
            'guangzhou_2015_real_ingest_v1',
            'guangzhou_2015_visual_region_v1',
            %s
        )
          and coalesce(custom_fields->>'year', custom_fields#>>'{exam,year}') = '2015'
        order by (custom_fields->>'questionNo')::int, updated_at desc
        """,
        (WORKFLOW_KEY,),
    )
    for row in select_2015_candidate_rows(old_rows):
        custom = row["custom_fields"] or {}
        number = int(custom["questionNo"])
        blocks = row["blocks"] or []
        stem = extract_2015_candidate_stem(blocks, number)
        answer = custom.get("answer") or {}
        solution = custom.get("solution") or {}
        result[(2015, number)] = {
            "legacyQuestionId": f"2015-existing-{row['id']}",
            "stem": stem,
            "questionType": str(row["question_type"] or "unknown"),
            "score": float(row["default_score"]) if row["default_score"] is not None else None,
            "answer": str(answer.get("value") or ""),
            "answerTextSource": "existing_2015_candidate",
            "solution": str(solution.get("text") or ""),
            "primaryKnowledgeCandidateId": "",
            "primaryKnowledgeLabel": str(custom.get("primaryKnowledgeLabel") or ""),
            "knowledgeCandidateIds": list(custom.get("knowledgeCandidateIds") or custom.get("knowledgeTags") or []),
            "primaryExamPointCandidateId": "",
            "examPointCandidateIds": [],
            "abilityDimensions": [],
            "confidence": 0.0,
            "difficultyObserved": None,
            "discriminationObserved": None,
            "yearReportEvidenceLocation": str(custom.get("yearReportEvidenceLocation") or "pending_v2_year_report_alignment"),
            "officialExamPointSummary": str(custom.get("officialExamPointSummary") or ""),
            "answerEvidenceLocation": str(custom.get("answerEvidenceLocation") or "2015 answer PDF; per-question page alignment pending review"),
            "subquestions": [],
        }
        ids[number] = uuid.UUID(str(row["id"]))
    return result, ids


def load_existing_question_ids(conn: psycopg.Connection[Any]) -> dict[tuple[int, int], uuid.UUID]:
    existing: dict[tuple[int, int], uuid.UUID] = {}
    for row in rows(
        conn,
        """
        select id, (custom_fields->>'year')::integer as year,
               (custom_fields->>'questionNo')::integer as question_number
        from question_items
        where custom_fields->>'sourceWorkflowKey' = %s
        order by year, question_number, id
        """,
        (WORKFLOW_KEY,),
    ):
        key = (int(row["year"]), int(row["question_number"]))
        if key in existing:
            raise ValueError(f"duplicate_existing_question_identity:{key[0]}:{key[1]}")
        existing[key] = uuid.UUID(str(row["id"]))
    return existing


def question_id(
    year: int,
    number: int,
    source_file: str,
    existing_ids: dict[tuple[int, int], uuid.UUID],
) -> uuid.UUID:
    existing = existing_ids.get((year, number))
    if existing is not None:
        return existing
    return uuid.uuid5(uuid.NAMESPACE_URL, f"real005b:{year}:{number}:{source_file}")


def validate_region_files(file_root: Path, plans: dict[int, YearRegionPlan]) -> None:
    missing = [
        region.relative_path
        for plan in plans.values()
        for regions in plan.questions.values()
        for region in regions
        if not region.relative_path or not (file_root / region.relative_path).is_file()
    ]
    if missing:
        raise FileNotFoundError(f"question_region_files_missing:{missing[:10]}")


def load_answer_page_texts(
    repo_root: Path, file_root: Path, answer_doc: dict[str, Any]
) -> tuple[list[str], str]:
    reader = PdfReader(str(answer_doc["path"]))
    page_texts = [page.extract_text() or "" for page in reader.pages]
    if sum(len(text.strip()) for text in page_texts) >= len(page_texts) * 40:
        return page_texts, "pypdf_text"

    completed = subprocess.run(
        [
            sys.executable,
            str(repo_root / "workers" / "document" / "worker.py"),
            "--job-id",
            f"{WORKFLOW_KEY}-answer-{answer_doc['year']}",
            "--relative-path",
            str(answer_doc["relative_path"]),
            "--file-root",
            str(file_root),
        ],
        cwd=repo_root,
        text=True,
        capture_output=True,
        encoding="utf-8",
        timeout=180,
        check=False,
    )
    if completed.returncode != 0:
        raise ValueError(f"answer_worker_failed:{answer_doc['year']}:{completed.stderr[-500:]}")
    payload = json.loads(completed.stdout)
    pages = payload.get("documentModel", {}).get("pages") or []
    worker_texts = [
        "\n".join(str(block.get("textPreview") or "") for block in page.get("layoutBlocks") or [])
        for page in pages
    ]
    if len(worker_texts) != len(page_texts) or not any(text.strip() for text in worker_texts):
        raise ValueError(f"answer_worker_page_contract_failed:{answer_doc['year']}")
    adapter = str((payload.get("adapterDiagnostics") or [{}])[0].get("adapterName") or "document_worker")
    return worker_texts, adapter


def load_forced_ocr_page_texts(repo_root: Path, path: Path) -> list[str]:
    worker_path = repo_root / "workers" / "document" / "worker.py"
    spec = importlib.util.spec_from_file_location("kqg_document_worker_for_answer_ocr", worker_path)
    if spec is None or spec.loader is None:
        raise ValueError("answer_ocr_worker_import_failed")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    pages, warnings = module.parse_scanned_pdf_with_rapidocr(path)
    texts = [
        "\n".join(str(block.get("textPreview") or "") for block in page.get("layoutBlocks") or [])
        for page in pages
    ]
    if not any(text.strip() for text in texts):
        raise ValueError(f"forced_answer_ocr_empty:{path}:{warnings[-3:]}")
    return texts


def answer_minimum_page(
    year: int,
    plan: YearRegionPlan,
    paper_doc: dict[str, Any],
    answer_doc: dict[str, Any],
) -> int:
    if year != 2020 or answer_doc["file_asset_id"] != paper_doc["file_asset_id"]:
        return 1
    return plan.questions[max(plan.questions)][-1].page_number + 1


def clear_materialized_children(conn: psycopg.Connection[Any], target_ids: list[uuid.UUID]) -> None:
    with conn.cursor() as cursor:
        cursor.execute(
            "delete from review_queue_items where payload->>'sourceWorkflowKey' in (%s, %s)",
            (WORKFLOW_KEY, OLD_WORKFLOW_KEY),
        )
        cursor.execute("delete from cut_candidates where suggested_question_item_id = any(%s)", (target_ids,))
        cursor.execute("delete from question_assets where question_item_id = any(%s)", (target_ids,))


def ensure_answer_regions(
    conn: psycopg.Connection[Any],
    year: int,
    answer_doc: dict[str, Any],
    page_numbers: tuple[int, ...],
) -> list[uuid.UUID]:
    result: list[uuid.UUID] = []
    for page_number in page_numbers:
        region_id = stable_id("answer-document-page", answer_doc["id"], page_number)
        with conn.cursor() as cursor:
            cursor.execute(
                """
                insert into source_regions (
                    id, source_document_id, page_number, x, y, width, height,
                    coordinate_unit, screenshot_relative_path, region_type, created_at
                ) values (%s, %s, %s, 0, 0, 100, 100, 'percent', null, 'guangzhou_v2_answer_document_page', now())
                on conflict (id) do update set
                    source_document_id = excluded.source_document_id,
                    page_number = excluded.page_number,
                    x = excluded.x, y = excluded.y, width = excluded.width, height = excluded.height,
                    coordinate_unit = excluded.coordinate_unit,
                    screenshot_relative_path = excluded.screenshot_relative_path,
                    region_type = excluded.region_type
                """,
                (region_id, answer_doc["id"], page_number),
            )
        result.append(region_id)
    return result


def ensure_question_regions(
    conn: psycopg.Connection[Any], year: int, number: int, plan: YearRegionPlan
) -> list[uuid.UUID]:
    result: list[uuid.UUID] = []
    for index, region in enumerate(plan.questions[number], start=1):
        region_id = stable_id("question-region", year, number, index)
        x, y, width, height = region.bbox_percent
        with conn.cursor() as cursor:
            cursor.execute(
                """
                insert into source_regions (
                    id, source_document_id, page_number, x, y, width, height,
                    coordinate_unit, screenshot_relative_path, region_type, created_at
                ) values (%s, %s, %s, %s, %s, %s, %s, 'percent', %s, 'guangzhou_v2_question_candidate', now())
                on conflict (id) do update set
                    source_document_id = excluded.source_document_id,
                    page_number = excluded.page_number,
                    x = excluded.x, y = excluded.y, width = excluded.width, height = excluded.height,
                    coordinate_unit = excluded.coordinate_unit,
                    screenshot_relative_path = excluded.screenshot_relative_path,
                    region_type = excluded.region_type
                """,
                (region_id, plan.source_document_id, region.page_number, x, y, width, height, region.relative_path),
            )
        result.append(region_id)
    return result


def upsert_question(
    conn: psycopg.Connection[Any],
    qid: uuid.UUID,
    year: int,
    number: int,
    candidate: dict[str, Any],
    plan: YearRegionPlan,
    question_regions: list[uuid.UUID],
    answer_doc: dict[str, Any],
    answer_regions: list[uuid.UUID],
    answer_mode: str,
) -> None:
    materialized_blocks = rows(
        conn,
        """
        select id, block_type, sort_order, content
        from question_blocks
        where question_item_id = %s
          and block_type in ('subquestion','scoring_point')
        order by block_type, sort_order, id
        """,
        (qid,),
    )
    blocks = build_blocks(
        candidate,
        question_regions[0],
        answer_regions[0],
        qid,
        materialized_blocks=materialized_blocks,
    )
    custom_fields = {
        "sourceWorkflowKey": WORKFLOW_KEY,
        "materialBatchKey": BATCH_KEY,
        "year": year,
        "questionNo": number,
        "sourceFile": plan.source_file,
        "sourceDocumentId": str(plan.source_document_id),
        "questionSourceRegionIds": [str(value) for value in question_regions],
        "answerSourceDocumentId": str(answer_doc["id"]),
        "answerSourceRegionIds": [str(value) for value in answer_regions],
        "answerSourceMode": answer_mode,
        "answerStatus": "pending_review",
        "answerTextSource": candidate.get("answerTextSource", "c003_answer_value"),
        "answer": {"value": candidate.get("answer", ""), "status": "pending_review"},
        "solution": {"text": candidate.get("solution", ""), "status": "pending_review"},
        "primaryKnowledgeCandidateId": candidate.get("primaryKnowledgeCandidateId", ""),
        "primaryKnowledgeLabel": candidate.get("primaryKnowledgeLabel", ""),
        "knowledgeCandidateIds": candidate.get("knowledgeCandidateIds", []),
        "primaryExamPointCandidateId": candidate.get("primaryExamPointCandidateId", ""),
        "examPointCandidateIds": candidate.get("examPointCandidateIds", []),
        "abilityDimensions": candidate.get("abilityDimensions", []),
        "taggingStatus": "pending_review",
        "teacherValidationRequired": True,
        "productionEligible": False,
        "manualTakeoverRequired": number in plan.manual_takeovers or answer_mode == "whole_answer_document_pending_review",
        "yearReportEvidenceLocation": candidate.get("yearReportEvidenceLocation", ""),
        "answerEvidenceLocation": candidate.get("answerEvidenceLocation", ""),
        "officialExamPointSummary": candidate.get("officialExamPointSummary", ""),
        "legacyQuestionId": candidate.get("legacyQuestionId", ""),
    }
    quality_signals = {
        "reviewStatus": "pending_review",
        "productionEligible": False,
        "teacherValidationRequired": True,
        "externalAiCalls": 0,
        "realStudentDataUsed": False,
        "candidateConfidence": candidate.get("confidence", 0.0),
        "discriminationObservedCandidate": candidate.get("discriminationObserved"),
    }
    with conn.cursor() as cursor:
        cursor.execute(
            """
            insert into question_items (
                id, subject, stage, grade, question_type, default_score,
                difficulty_estimated, difficulty_observed, status, primary_knowledge_id,
                blocks, custom_fields, quality_signals, created_at, updated_at
            ) values (
                %s, 'physics', 'junior_middle_school', 'grade_9', %s, %s,
                null, %s, 'pending_review', null, %s::jsonb, %s::jsonb, %s::jsonb, now(), now()
            )
            on conflict (id) do update set
                subject = excluded.subject, stage = excluded.stage, grade = excluded.grade,
                question_type = excluded.question_type, default_score = excluded.default_score,
                difficulty_estimated = excluded.difficulty_estimated,
                difficulty_observed = excluded.difficulty_observed,
                status = excluded.status, primary_knowledge_id = null,
                blocks = excluded.blocks, custom_fields = excluded.custom_fields,
                quality_signals = excluded.quality_signals, updated_at = excluded.updated_at
            """,
            (
                qid,
                candidate.get("questionType"),
                candidate.get("score"),
                candidate.get("difficultyObserved"),
                json.dumps(blocks, ensure_ascii=False),
                json.dumps(custom_fields, ensure_ascii=False),
                json.dumps(quality_signals, ensure_ascii=False),
            ),
        )
        prepared_blocks: list[tuple[uuid.UUID, dict[str, Any]]] = []
        for block in blocks:
            question_block_id = block["content"].get("questionBlockId") or stable_id(
                "question-block", qid, block["order"], block["type"]
            )
            prepared_blocks.append((uuid.UUID(str(question_block_id)), block))

        generated_block_ids = [question_block_id for question_block_id, _ in prepared_blocks]
        referenced_stale_blocks = cursor.execute(
            """
            select qb.id
            from question_blocks qb
            where qb.question_item_id = %s
              and not (qb.id = any(%s::uuid[]))
              and exists (select 1 from assessment_targets at where at.question_block_id = qb.id)
            order by qb.id
            """,
            (qid, generated_block_ids),
        ).fetchall()
        if referenced_stale_blocks:
            raise ValueError(
                "referenced_question_blocks_missing_from_refresh:"
                + ",".join(str(row[0]) for row in referenced_stale_blocks)
            )
        cursor.execute(
            """
            delete from question_blocks
            where question_item_id = %s
              and not (id = any(%s::uuid[]))
            """,
            (qid, generated_block_ids),
        )

        for question_block_id, block in prepared_blocks:
            cursor.execute(
                """
                insert into question_blocks (id, question_item_id, block_type, sort_order, content, source_region_id, created_at)
                values (%s, %s, %s, %s, %s::jsonb, %s, now())
                on conflict (id) do update set
                    question_item_id = excluded.question_item_id,
                    block_type = excluded.block_type,
                    sort_order = excluded.sort_order,
                    content = excluded.content,
                    source_region_id = excluded.source_region_id
                """,
                (
                    question_block_id,
                    qid,
                    block["type"],
                    block["order"],
                    json.dumps(block["content"], ensure_ascii=False),
                    uuid.UUID(block["sourceRegionId"]),
                ),
            )
        for index, region_id in enumerate(question_regions, start=1):
            cursor.execute(
                """
                insert into question_assets (
                    id, question_item_id, file_asset_id, source_region_id, asset_type, purpose, metadata, created_at
                ) values (%s, %s, null, %s, 'question_region_image', 'source_review', %s::jsonb, now())
                """,
                (
                    stable_id("question-asset", qid, index),
                    qid,
                    region_id,
                    json.dumps({"sourceWorkflowKey": WORKFLOW_KEY, "segmentIndex": index}, ensure_ascii=False),
                ),
            )
        cursor.execute(
            """
            insert into cut_candidates (
                id, source_document_id, source_region_id, suggested_question_item_id,
                status, confidence, segment_type, sequence_no, candidate_payload,
                failure_reason, takeover_action, metadata, created_at, updated_at
            ) values (%s, %s, %s, %s, 'pending_review', %s, 'question', %s, %s::jsonb, '', 'manual_review', %s::jsonb, now(), now())
            on conflict (id) do update set
                source_document_id=excluded.source_document_id, source_region_id=excluded.source_region_id,
                suggested_question_item_id=excluded.suggested_question_item_id, status=excluded.status,
                confidence=excluded.confidence, segment_type=excluded.segment_type,
                sequence_no=excluded.sequence_no, candidate_payload=excluded.candidate_payload,
                failure_reason=excluded.failure_reason, takeover_action=excluded.takeover_action,
                metadata=excluded.metadata, updated_at=excluded.updated_at
            """,
            (
                stable_id("cut-candidate", year, number),
                plan.source_document_id,
                question_regions[0],
                qid,
                candidate.get("confidence", 0.0),
                number,
                json.dumps({"year": year, "questionNo": number, "status": "pending_review"}, ensure_ascii=False),
                json.dumps({"sourceWorkflowKey": WORKFLOW_KEY, "teacherValidationRequired": True}, ensure_ascii=False),
            ),
        )
        cursor.execute(
            """
            insert into review_queue_items (id, review_type, status, payload, created_at, resolved_at)
            values (%s, 'guangzhou_v2_question_candidate_review', 'open', %s::jsonb, now(), null)
            on conflict (id) do update set status='open', payload=excluded.payload, resolved_at=null
            """,
            (
                stable_id("review", year, number),
                json.dumps(
                    {
                        "sourceWorkflowKey": WORKFLOW_KEY,
                        "materialBatchKey": BATCH_KEY,
                        "questionItemId": str(qid),
                        "year": year,
                        "questionNo": number,
                        "answerSourceMode": answer_mode,
                        "requiredActions": ["review_question_crop", "review_answer_source", "review_tags", "review_difficulty"],
                        "teacherValidationRequired": True,
                        "productionEligible": False,
                    },
                    ensure_ascii=False,
                ),
            ),
        )


def write_reports(report: dict[str, Any], json_path: Path, markdown_path: Path) -> None:
    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    lines = [
        "# REAL005B Guangzhou v2 candidate materialize",
        "",
        f"- status: {report['status']}",
        f"- mode: {report['mode']}",
        f"- workflow_key: {report['workflowKey']}",
        f"- planned_questions: {report['totals']['questions']}",
        f"- question_regions: {report['totals']['questionRegions']}",
        f"- answer_regions: {report['totals']['answerRegions']}",
        f"- open_reviews: {report['database']['openReviewCountInsideTransaction']}",
        f"- persisted_after_run: {report['database']['persistedAfterRun']}",
        f"- active_count_unchanged: {report['invariants']['c002ActiveCountUnchanged']}",
        "",
        "## Years",
    ]
    for item in report["years"]:
        lines.append(
            f"- {item['year']}: questions={item['questions']}; question_regions={item['questionRegions']}; "
            f"answer_modes={json.dumps(item['answerModes'], ensure_ascii=False, sort_keys=True)}"
        )
    lines.extend(["", "## Boundary", report["boundary"]])
    markdown_path.parent.mkdir(parents=True, exist_ok=True)
    markdown_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Materialize Guangzhou physics 2015-2025 v2 candidates")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5432)
    parser.add_argument("--database", default="k12_question_graph")
    parser.add_argument("--user", default="postgres")
    parser.add_argument("--file-root", default=r"D:\KQG_Data\file_store")
    parser.add_argument("--csv-root", default=r"D:\KQG_Data\candidate_packages\c003-merged-quality-review-2016-2025")
    parser.add_argument("--question-region-report-2015", default="docs/evidence/20260726-guangzhou-physics-v2-2015-question-regions.json")
    parser.add_argument("--question-region-report-2016-2025", default="docs/evidence/20260726-guangzhou-physics-v2-question-regions.json")
    parser.add_argument("--backup-manifest", default="")
    parser.add_argument("--output", required=True)
    parser.add_argument("--markdown-output", required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    if args.apply and (not args.backup_manifest or not Path(args.backup_manifest).is_file()):
        raise ValueError("verified_backup_manifest_required_for_apply")
    password = os.environ.get("PGPASSWORD", "")

    repo_root = Path(__file__).resolve().parents[1]
    file_root = Path(args.file_root).resolve()
    csv_root = Path(args.csv_root).resolve()
    plans = load_question_region_plans(
        (repo_root / args.question_region_report_2015).resolve(),
        (repo_root / args.question_region_report_2016_2025).resolve(),
    )
    validate_region_files(file_root, plans)

    conn = psycopg.connect(
        **build_connection_kwargs(args.host, args.port, args.database, args.user, password)
    )
    conn.autocommit = False
    try:
        sources = load_source_documents(conn, file_root)
        candidates = load_c003_candidates(csv_root)
        candidates_2015, existing_2015_ids = load_2015_candidates(conn)
        candidates.update(candidates_2015)
        existing_question_ids = load_existing_question_ids(conn)
        for number, candidate_id in existing_2015_ids.items():
            existing_question_ids.setdefault((2015, number), candidate_id)
        validate_candidate_coverage(candidates)
        validate_candidate_content(candidates)

        target_ids = [
            question_id(year, number, plans[year].source_file, existing_question_ids)
            for year in YEARS
            for number in range(1, EXPECTED_COUNTS[year] + 1)
        ]
        persisted_before = scalar(conn, "select count(*) from question_items where custom_fields->>'sourceWorkflowKey'=%s", (WORKFLOW_KEY,))
        fingerprint_before = workflow_fingerprint(conn)
        active_before = scalar(
            conn,
            "select count(*) from domain_asset_versions where source_evidence->>'importKey'=%s and status='active'",
            (C002_IMPORT_KEY,),
        )
        clear_materialized_children(conn, target_ids)

        answer_page_map: dict[int, dict[int, tuple[int, ...]]] = {}
        answer_page_counts: dict[int, int] = {}
        answer_text_adapters: dict[int, str] = {}
        extracted_answer_counts: dict[int, int] = {}
        for year in YEARS:
            answer_doc = sources[(year, "answer_or_solution")]
            paper_doc = sources[(year, "local_exam_paper")]
            minimum_page = answer_minimum_page(year, plans[year], paper_doc, answer_doc)
            page_texts, adapter = load_answer_page_texts(repo_root, file_root, answer_doc)
            sections = extract_numbered_answer_sections(page_texts, EXPECTED_COUNTS[year], minimum_page)
            extracted_count = 0
            for number in range(1, EXPECTED_COUNTS[year] + 1):
                candidate = candidates[(year, number)]
                if not str(candidate.get("answer") or "").strip() and sections.get(number):
                    candidate["answer"] = sections[number]
                    candidate["answerTextSource"] = f"{adapter}_numbered_section_candidate"
                    extracted_count += 1

            compact_choices = (
                extract_compact_choice_sequence(page_texts[max(0, minimum_page - 1) :], 12)
                if year == 2020
                else {}
            )
            for number, answer in compact_choices.items():
                candidate = candidates[(year, number)]
                if not str(candidate.get("answer") or "").strip():
                    candidate["answer"] = answer
                    candidate["answerTextSource"] = "compact_choice_sequence_candidate"
                    extracted_count += 1

            missing_numbers = [
                number
                for number in range(1, EXPECTED_COUNTS[year] + 1)
                if not str(candidates[(year, number)].get("answer") or "").strip()
            ]
            if missing_numbers:
                forced_ocr_texts = load_forced_ocr_page_texts(repo_root, answer_doc["path"])
                forced_sections = extract_numbered_answer_sections(
                    forced_ocr_texts, EXPECTED_COUNTS[year], minimum_page
                )
                for number in missing_numbers:
                    if forced_sections.get(number):
                        candidates[(year, number)]["answer"] = forced_sections[number]
                        candidates[(year, number)]["answerTextSource"] = (
                            "forced_rapidocr_numbered_section_candidate"
                        )
                        extracted_count += 1
                page_texts = forced_ocr_texts
                adapter = "forced_rapidocr"

            answer_text_adapters[year] = adapter
            answer_page_map[year] = locate_answer_pages_from_texts(
                page_texts, EXPECTED_COUNTS[year], minimum_page
            )
            answer_page_counts[year] = len(
                set(page for pages in answer_page_map[year].values() for page in pages)
            )
            extracted_answer_counts[year] = extracted_count

        year_reports: list[dict[str, Any]] = []
        answer_region_ids: set[uuid.UUID] = set()
        for year in YEARS:
            plan = plans[year]
            answer_doc = sources[(year, "answer_or_solution")]
            modes: dict[str, int] = {}
            for number in range(1, EXPECTED_COUNTS[year] + 1):
                candidate = candidates[(year, number)]
                qid = question_id(year, number, plan.source_file, existing_question_ids)
                question_regions = ensure_question_regions(conn, year, number, plan)
                page_numbers = answer_page_map[year][number]
                answer_regions = ensure_answer_regions(conn, year, answer_doc, page_numbers)
                answer_region_ids.update(answer_regions)
                mode = answer_region_mode(page_numbers, answer_page_counts[year])
                modes[mode] = modes.get(mode, 0) + 1
                upsert_question(conn, qid, year, number, candidate, plan, question_regions, answer_doc, answer_regions, mode)
            year_reports.append(
                {
                    "year": year,
                    "questions": EXPECTED_COUNTS[year],
                    "questionRegions": sum(len(value) for value in plan.questions.values()),
                    "answerDocumentId": str(answer_doc["id"]),
                    "answerModes": modes,
                    "answerTextAdapter": answer_text_adapters[year],
                    "extractedAnswerCandidateCount": extracted_answer_counts[year],
                }
            )

        inside_question_count = scalar(conn, "select count(*) from question_items where custom_fields->>'sourceWorkflowKey'=%s", (WORKFLOW_KEY,))
        inside_review_count = scalar(conn, "select count(*) from review_queue_items where payload->>'sourceWorkflowKey'=%s and status='open'", (WORKFLOW_KEY,))
        inside_pending_count = scalar(conn, "select count(*) from question_items where custom_fields->>'sourceWorkflowKey'=%s and status='pending_review'", (WORKFLOW_KEY,))
        production_eligible_count = scalar(conn, "select count(*) from question_items where custom_fields->>'sourceWorkflowKey'=%s and coalesce((custom_fields->>'productionEligible')::boolean,false)=true", (WORKFLOW_KEY,))
        missing_answer_count = scalar(conn, "select count(*) from question_items where custom_fields->>'sourceWorkflowKey'=%s and coalesce(custom_fields#>>'{answer,value}','')=''", (WORKFLOW_KEY,))
        active_inside = scalar(
            conn,
            "select count(*) from domain_asset_versions where source_evidence->>'importKey'=%s and status='active'",
            (C002_IMPORT_KEY,),
        )
        if inside_question_count != 234 or inside_review_count != 234 or inside_pending_count != 234:
            raise ValueError(f"materialize_invariant_failed:{inside_question_count}:{inside_review_count}:{inside_pending_count}")
        if production_eligible_count or active_inside != active_before:
            raise ValueError("production_or_active_write_detected")
        if missing_answer_count:
            missing_answers = rows(
                conn,
                """
                select custom_fields->>'year' as year, custom_fields->>'questionNo' as question_number
                from question_items
                where custom_fields->>'sourceWorkflowKey'=%s
                  and coalesce(custom_fields#>>'{answer,value}','')=''
                order by (custom_fields->>'year')::int, (custom_fields->>'questionNo')::int
                """,
                (WORKFLOW_KEY,),
            )
            raise ValueError(f"answer_candidate_text_missing:{missing_answers}")

        if args.apply:
            conn.commit()
        else:
            conn.rollback()
        persisted_after = scalar(conn, "select count(*) from question_items where custom_fields->>'sourceWorkflowKey'=%s", (WORKFLOW_KEY,))
        fingerprint_after = workflow_fingerprint(conn)
        active_after = scalar(
            conn,
            "select count(*) from domain_asset_versions where source_evidence->>'importKey'=%s and status='active'",
            (C002_IMPORT_KEY,),
        )
        report = {
            "status": "pass" if args.apply else "dry_run_pass",
            "taskId": "GUANGZHOU_PHYSICS_V2_CANDIDATE_MATERIALIZE",
            "checkedAt": datetime.now(timezone.utc).isoformat(),
            "mode": "apply" if args.apply else "transaction_rollback_dry_run",
            "workflowKey": WORKFLOW_KEY,
            "materialBatchKey": BATCH_KEY,
            "backupManifest": args.backup_manifest if args.apply else None,
            "activeWrite": False,
            "externalAiCalls": 0,
            "realStudentDataUsed": False,
            "totals": {
                "questions": 234,
                "questionRegions": flatten_question_regions(plans.values()),
                "answerRegions": len(answer_region_ids),
            },
            "years": year_reports,
            "database": {
                "questionCountInsideTransaction": inside_question_count,
                "pendingReviewCountInsideTransaction": inside_pending_count,
                "openReviewCountInsideTransaction": inside_review_count,
                "productionEligibleCountInsideTransaction": production_eligible_count,
                "missingAnswerCandidateCountInsideTransaction": missing_answer_count,
                "persistedBeforeRun": persisted_before,
                "persistedAfterRun": persisted_after,
                "stateFingerprintBefore": fingerprint_before,
                "stateFingerprintAfter": fingerprint_after,
            },
            "invariants": {
                "allQuestionsPendingReview": inside_pending_count == 234,
                "allReviewItemsOpen": inside_review_count == 234,
                "productionEligibleFalse": production_eligible_count == 0,
                "allAnswerCandidatesNonEmpty": missing_answer_count == 0,
                "c002ActiveCountBefore": active_before,
                "c002ActiveCountAfter": active_after,
                "c002ActiveCountUnchanged": active_before == active_after,
                "dryRunRolledBack": None if args.apply else (
                    persisted_after == persisted_before and fingerprint_after == fingerprint_before
                ),
            },
            "rollback": {
                "primary": f"restore database from {args.backup_manifest}" if args.apply else "transaction rollback completed",
                "targetedWorkflowKey": WORKFLOW_KEY,
                "restoreCommand": f"pwsh -NoProfile -ExecutionPolicy Bypass -File tools/restore.ps1 -ManifestPath '{args.backup_manifest}' -ApplyDatabase -ApplyFileStore -DryRun:$false" if args.apply else None,
            },
            "boundary": "Candidate materialization only. All 234 questions and reviews remain pending/open; answer full-document fallbacks require teacher validation. No C002 active switch, teacher acceptance, onsite closure, or REAL005 closure is claimed.",
        }
        write_reports(report, (repo_root / args.output).resolve(), (repo_root / args.markdown_output).resolve())
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 0
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())

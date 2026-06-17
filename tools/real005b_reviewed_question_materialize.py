from __future__ import annotations

import argparse
import csv
import json
import re
import uuid
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import psycopg
from psycopg.rows import dict_row


YEARS = list(range(2016, 2026))
QUESTION_TYPE_BY_ROW = {
    "choice": "single_choice",
    "fill_or_drawing": "fill_or_drawing",
    "analysis_calculation": "analysis_calculation",
    "experiment_inquiry": "experiment_inquiry",
    "comprehensive_calculation": "comprehensive_calculation",
}
SOURCE_WORKFLOW_KEY = "guangzhou_2016_2025_reviewed_question_materialize_v1"
TABLE_PATTERN = re.compile(r"(表\s*\d+|数据在表|根据表|表格|如下表|表中)")
FORMULA_PATTERN = re.compile(r"(公式|U-I|F=|Q=|v=|R=|I/A|U/V|ρ=)")
FORMULA_QUESTION_TYPES = {
    "analysis_calculation",
    "experiment_inquiry",
    "comprehensive_calculation",
}


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def rows(conn: psycopg.Connection[Any], sql: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(sql, params)
        return list(cur.fetchall())


def scalar(conn: psycopg.Connection[Any], sql: str, params: tuple[Any, ...] = ()) -> int:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(sql, params)
        row = cur.fetchone()
        if row is None:
            return 0
        value = next(iter(row.values()))
        return int(value or 0)


def group_by_year(rows_in: list[dict[str, str]]) -> dict[int, list[dict[str, str]]]:
    grouped: dict[int, list[dict[str, str]]] = defaultdict(list)
    for row in rows_in:
        year_text = str(row.get("year") or "").strip()
        if year_text.isdigit():
            grouped[int(year_text)].append(row)
    return grouped


def normalize_question_type(value: str) -> str:
    return QUESTION_TYPE_BY_ROW.get(value.strip(), "unknown")


def parse_confidence(value: str | None, default: float = 0.62) -> float:
    try:
        parsed = float(str(value or "").strip())
    except ValueError:
        return default
    return max(0.0, min(parsed, 1.0))


def question_text(question_row: dict[str, str]) -> str:
    stem_text = str(question_row.get("stem_summary") or "").strip()
    notes = str(question_row.get("notes") or "").strip()
    return f"{stem_text} {notes}".strip()


def is_table_candidate(question_row: dict[str, str]) -> bool:
    return bool(TABLE_PATTERN.search(question_text(question_row)))


def is_formula_candidate(question_row: dict[str, str]) -> bool:
    question_type = normalize_question_type(str(question_row.get("question_type") or ""))
    if question_type in FORMULA_QUESTION_TYPES:
        return True
    return bool(FORMULA_PATTERN.search(question_text(question_row)))


def build_table_candidate_content(question_row: dict[str, str], question_region_id: uuid.UUID) -> dict[str, Any]:
    stem_text = str(question_row.get("stem_summary") or "").strip()
    match = TABLE_PATTERN.search(stem_text)
    raw_segment = stem_text[match.start() :] if match else stem_text
    raw_segment = " ".join(raw_segment.split())
    caption_match = re.search(r"表\s*\d+", raw_segment)
    caption = caption_match.group(0) if caption_match else "表格候选"
    raw_lines = [
        " ".join(part.split())
        for part in re.split(r"[；;。]", raw_segment)
        if " ".join(part.split())
    ]
    if not raw_lines:
        raw_lines = [raw_segment or stem_text]
    rows = [[line] for line in raw_lines[:8]]
    return {
        "structureVersion": "table.v1",
        "caption": caption,
        "columns": ["raw_text"],
        "rows": rows,
        "rawText": raw_segment[:600],
        "confidence": min(parse_confidence(question_row.get("confidence"), 0.62), 0.79),
        "reviewStatus": "pending_review",
        "sourceRegionId": str(question_region_id),
    }


def build_formula_candidate_content(question_row: dict[str, str], question_region_id: uuid.UUID) -> dict[str, Any]:
    stem_text = str(question_row.get("stem_summary") or "").strip()
    formula_tokens = FORMULA_PATTERN.findall(stem_text)
    fallback_text = " ".join(formula_tokens).strip()
    if not fallback_text:
        fallback_text = stem_text[:160]
    return {
        "sourceFormat": "scanned_formula_candidate",
        "textCandidate": fallback_text[:160],
        "confidence": min(parse_confidence(question_row.get("confidence"), 0.62), 0.89),
        "reviewStatus": "pending_review",
        "fallbackImageSourceRegionId": str(question_region_id),
        "fallbackImageUrl": f"/source-regions/{question_region_id}/screenshot",
        "recognitionEngine": "real005b_candidate_summary",
    }


def source_region_index_for_block_type(block_type: str) -> int:
    return 1 if block_type == "answer" else 0


def build_question_blocks(
    question_row: dict[str, str],
    answer_row: dict[str, str],
    question_region_id: uuid.UUID,
) -> list[dict[str, Any]]:
    question_no = int(question_row["question_number"])
    stem_text = str(question_row.get("stem_summary") or "").strip()
    answer_text = str(answer_row.get("answer_value") or "").strip()
    question_type = normalize_question_type(str(question_row.get("question_type") or ""))
    blocks = [
        {
            "blockType": "text",
            "sortOrder": 0,
            "content": {
                "text": stem_text,
                "questionNo": question_no,
                "sourceFile": question_row.get("source_file"),
                "evidenceNote": question_row.get("evidence_note") or "",
            },
            "sourceRegionIndex": source_region_index_for_block_type("text"),
        },
        {
            "blockType": "answer",
            "sortOrder": 1,
            "content": {
                "answer": answer_text,
                "sourceFile": answer_row.get("answer_source_file") or question_row.get("source_file"),
                "reviewDecision": answer_row.get("decision") or "resolved_with_unavailable_or_unextracted_fields",
            },
            "sourceRegionIndex": source_region_index_for_block_type("answer"),
        },
    ]
    if is_formula_candidate(question_row):
        blocks.append(
            {
                "blockType": "formula",
                "sortOrder": len(blocks),
                "content": build_formula_candidate_content(question_row, question_region_id),
                "sourceRegionIndex": source_region_index_for_block_type("formula"),
            }
        )
    if is_table_candidate(question_row):
        blocks.append(
            {
                "blockType": "table",
                "sortOrder": len(blocks),
                "content": build_table_candidate_content(question_row, question_region_id),
                "sourceRegionIndex": source_region_index_for_block_type("table"),
            }
        )
    return blocks


def ensure_source_regions(
    conn: psycopg.Connection[Any],
    source_document_id: uuid.UUID,
    year: int,
    question_row: dict[str, str],
    answer_row: dict[str, str],
) -> tuple[uuid.UUID, uuid.UUID]:
    question_no = int(question_row["question_number"])
    page_text = str(question_row.get("page_or_location") or "")
    question_page = int("".join(ch for ch in page_text if ch.isdigit()) or "1")
    answer_page = question_page
    now = datetime.now(timezone.utc)
    question_page_screenshot = f"generated/guangzhou-physics-2016-2025/source-pages/{year}/{source_document_id}/page-{question_page:03d}.png"
    answer_page_screenshot = f"generated/guangzhou-physics-2016-2025/source-pages/{year}/{source_document_id}/page-{answer_page:03d}.png"

    existing = rows(
        conn,
        """
        select id, region_type
        from source_regions
        where source_document_id = %s
          and region_type in ('real005b_review_question', 'real005b_review_answer')
          and page_number = %s
        order by created_at
        """,
        (source_document_id, question_page),
    )
    question_region_id = next(
        (row["id"] for row in existing if row["region_type"] == "real005b_review_question"),
        None,
    )
    answer_region_id = next(
        (row["id"] for row in existing if row["region_type"] == "real005b_review_answer"),
        None,
    )
    if question_region_id is not None and answer_region_id is not None:
        return question_region_id, answer_region_id

    question_region_id = question_region_id or uuid.uuid4()
    answer_region_id = answer_region_id or uuid.uuid4()
    with conn.cursor() as cur:
        if question_region_id not in {row["id"] for row in existing}:
            cur.execute(
                """
                insert into source_regions (
                    id, source_document_id, page_number, x, y, width, height,
                    coordinate_unit, screenshot_relative_path, region_type, created_at
                )
                values (%s, %s, %s, 5, 8, 90, 18, 'percent', %s, 'real005b_review_question', %s)
                """,
                (
                    question_region_id,
                    source_document_id,
                    question_page,
                    question_page_screenshot,
                    now,
                ),
            )
        if answer_region_id not in {row["id"] for row in existing}:
            cur.execute(
                """
                insert into source_regions (
                    id, source_document_id, page_number, x, y, width, height,
                    coordinate_unit, screenshot_relative_path, region_type, created_at
                )
                values (%s, %s, %s, 5, 78, 90, 12, 'percent', %s, 'real005b_review_answer', %s)
                """,
                (
                    answer_region_id,
                    source_document_id,
                    answer_page,
                    answer_page_screenshot,
                    now,
                ),
            )
    return question_region_id, answer_region_id


def main() -> int:
    parser = argparse.ArgumentParser(description="Materialize reviewed 2016-2025 Guangzhou physics questions into API-visible rows")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5432)
    parser.add_argument("--database", default="k12_question_graph")
    parser.add_argument("--user", default="postgres")
    parser.add_argument("--password", default="")
    parser.add_argument("--file-root", default=r"D:\KQG_Data\file_store")
    parser.add_argument("--csv-root", default="guangzhou-physics-full-research-package-2016-2025/csv")
    parser.add_argument("--quality-review-csv-root", default="guangzhou-physics-full-research-package-2016-2025/quality-review-complete-csv-package")
    parser.add_argument("--output", default="docs/evidence/20260617-real005b-reviewed-question-materialize.json")
    parser.add_argument("--markdown-output", default="docs/evidence/20260617-real005b-reviewed-question-materialize.md")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    csv_root = Path(args.csv_root)
    quality_root = Path(args.quality_review_csv_root)

    question_rows = read_csv(quality_root / "c003-question-item-full.csv")
    answer_rows = read_csv(quality_root / "c003-answer-scoring-point.csv")
    review_rows = read_csv(quality_root / "c003-quality-issue-review-evidence.csv")
    source_rows = read_csv(csv_root / "c003-source-material.csv")

    question_by_year = group_by_year(question_rows)
    answer_by_year = group_by_year(answer_rows)
    review_by_question = {str(row.get("question_id") or ""): row for row in review_rows if str(row.get("question_id") or "").strip()}
    now = datetime.now(timezone.utc)

    with psycopg.connect(
        host=args.host,
        port=args.port,
        dbname=args.database,
        user=args.user,
        password=args.password,
        row_factory=dict_row,
    ) as conn:
        created_question_ids: list[str] = []
        created_region_ids: list[str] = []
        year_reports: list[dict[str, Any]] = []

        conn.execute("begin")
        try:
            for year in YEARS:
                qrows = sorted(question_by_year.get(year, []), key=lambda row: int(row["question_number"]))
                arows = {int(row["question_number"]): row for row in answer_by_year.get(year, [])}
                if not qrows:
                    year_reports.append({"year": year, "status": "blocked", "blockers": ["question_rows_missing"]})
                    continue

                year_question_ids: list[str] = []
                year_blockers: list[str] = []
                for qrow in qrows:
                    question_no = int(qrow["question_number"])
                    arow = arows.get(question_no)
                    if arow is None:
                        year_blockers.append(f"answer_missing:{question_no}")
                        continue

                    source_file = str(qrow.get("source_file") or "").strip()
                    source_doc_rows = rows(
                        conn,
                        """
                        select sd.id, sd.source_type, sd.source_title, sd.year, sd.material_batch_key, fa.relative_path
                        from source_documents sd
                        join file_assets fa on fa.id = sd.file_asset_id
                        where sd.year = %s and fa.original_file_name = %s
                        order by sd.created_at desc
                        """,
                        (year, source_file),
                    )
                    if not source_doc_rows:
                        year_blockers.append(f"source_document_missing:{question_no}")
                        continue
                    source_document_id = source_doc_rows[0]["id"]
                    question_region_id, answer_region_id = ensure_source_regions(conn, source_document_id, year, qrow, arow)
                    created_region_ids.extend([str(question_region_id), str(answer_region_id)])

                    question_id = uuid.uuid5(uuid.NAMESPACE_URL, f"real005b:{year}:{question_no}:{source_file}")
                    review = review_by_question.get(str(qrow["question_id"]))
                    question_type = normalize_question_type(str(qrow.get("question_type") or ""))
                    answer_text = str(arow.get("answer_value") or "").strip()
                    blocks = build_question_blocks(qrow, arow, question_region_id)
                    blocks_json = [
                        {
                            "blockType": block["blockType"],
                            "sortOrder": block["sortOrder"],
                            "content": block["content"],
                            "sourceRegionIndex": block["sourceRegionIndex"],
                        }
                        for block in blocks
                    ]
                    custom_fields = {
                        "sourceWorkflowKey": SOURCE_WORKFLOW_KEY,
                        "questionNo": question_no,
                        "sourceFile": source_file,
                        "sourceDocumentId": str(source_document_id),
                        "reviewDecision": review.get("decision") if review else "resolved_with_unavailable_or_unextracted_fields",
                        "reviewer": review.get("reviewer") if review else "chatgpt_web_document_review",
                        "reviewedAt": review.get("reviewed_at") if review else now.isoformat(),
                        "answer": {"value": answer_text, "sourceFile": review.get("answer_source_file") if review else source_file},
                        "yearReportEvidenceLocation": review.get("year_report_evidence_location") if review else "",
                        "officialExamPointSummary": review.get("official_exam_point_summary") if review else "",
                    }
                    quality_signals = {
                        "reviewStatus": "resolved",
                        "productionEligible": False,
                        "externalAiCalls": 0,
                        "realStudentDataUsed": False,
                        "reviewEvidencePath": f"{quality_root}/c003-quality-issue-review-evidence.csv",
                    }

                    with conn.cursor() as cur:
                        cur.execute(
                            """
                            insert into question_items (
                                id, subject, stage, grade, question_type, default_score,
                                difficulty_estimated, status, primary_knowledge_id, blocks,
                                custom_fields, quality_signals, created_at, updated_at
                            )
                            values (
                                %s, 'physics', 'junior_middle_school', %s, %s, %s,
                                null, 'usable', null, %s::jsonb, %s::jsonb, %s::jsonb, %s, %s
                            )
                            on conflict (id) do update set
                                subject = excluded.subject,
                                stage = excluded.stage,
                                grade = excluded.grade,
                                question_type = excluded.question_type,
                                default_score = excluded.default_score,
                                status = excluded.status,
                                primary_knowledge_id = excluded.primary_knowledge_id,
                                blocks = excluded.blocks,
                                custom_fields = excluded.custom_fields,
                                quality_signals = excluded.quality_signals,
                                updated_at = excluded.updated_at
                            """,
                            (
                                question_id,
                                "grade_9",
                                question_type,
                                qrow.get("score") or None,
                                json.dumps(blocks_json, ensure_ascii=False),
                                json.dumps(custom_fields, ensure_ascii=False),
                                json.dumps(quality_signals, ensure_ascii=False),
                                now,
                                now,
                            ),
                        )

                    with conn.cursor() as cur:
                        cur.execute("delete from question_blocks where question_item_id = %s", (question_id,))
                        cur.execute("delete from question_assets where question_item_id = %s", (question_id,))
                        for block in blocks:
                            block_id = uuid.uuid5(uuid.NAMESPACE_URL, f"real005b-block:{question_id}:{block['sortOrder']}")
                            cur.execute(
                                """
                                insert into question_blocks (id, question_item_id, block_type, sort_order, content, source_region_id, created_at)
                                values (%s, %s, %s, %s, %s::jsonb, %s, %s)
                                """,
                                (
                                    block_id,
                                    question_id,
                                    block["blockType"],
                                    block["sortOrder"],
                                    json.dumps(block["content"], ensure_ascii=False),
                                    question_region_id if block["sourceRegionIndex"] == 0 else answer_region_id,
                                    now,
                                ),
                            )
                        cur.execute(
                            """
                            insert into question_assets (id, question_item_id, file_asset_id, source_region_id, asset_type, purpose, metadata, created_at)
                            values (%s, %s, null, %s, 'image', 'question_content', %s::jsonb, %s)
                            on conflict do nothing
                            """,
                            (
                                uuid.uuid5(uuid.NAMESPACE_URL, f"real005b-asset:{question_id}"),
                                question_id,
                                question_region_id,
                                json.dumps({"sourceWorkflowKey": SOURCE_WORKFLOW_KEY}, ensure_ascii=False),
                                now,
                            ),
                        )
                        cur.execute(
                            """
                            insert into review_queue_items (id, review_type, status, payload, created_at)
                            values (%s, 'real005b_question_materialize', 'resolved', %s::jsonb, %s)
                            on conflict (id) do update set
                                status = excluded.status,
                                payload = excluded.payload
                            """,
                            (
                                uuid.uuid5(uuid.NAMESPACE_URL, f"real005b-review:{question_id}"),
                                json.dumps(
                                    {
                                        "questionId": str(question_id),
                                        "questionNo": question_no,
                                        "reviewDecision": custom_fields["reviewDecision"],
                                        "reviewer": custom_fields["reviewer"],
                                        "sourceDocumentId": str(source_document_id),
                                        "sourceWorkflowKey": SOURCE_WORKFLOW_KEY,
                                    },
                                    ensure_ascii=False,
                                ),
                                now,
                            ),
                        )

                        for block in blocks:
                            block_id = uuid.uuid5(uuid.NAMESPACE_URL, f"real005b-block:{question_id}:{block['sortOrder']}")
                            source_region_id = question_region_id if block["sourceRegionIndex"] == 0 else answer_region_id
                            if block["blockType"] == "table":
                                cur.execute(
                                    """
                                    insert into review_queue_items (id, review_type, status, payload, created_at)
                                    values (%s, 'question_table_block_review', 'open', %s::jsonb, %s)
                                    on conflict (id) do update set
                                        status = excluded.status,
                                        payload = excluded.payload
                                    """,
                                    (
                                        uuid.uuid5(uuid.NAMESPACE_URL, f"real005b-table-review:{question_id}:{block['sortOrder']}"),
                                        json.dumps(
                                            {
                                                "questionItemId": str(question_id),
                                                "questionBlockId": str(block_id),
                                                "sourceRegionId": str(source_region_id),
                                                "blockType": "table",
                                                "caption": block["content"].get("caption"),
                                                "confidence": block["content"].get("confidence"),
                                                "reviewStatus": block["content"].get("reviewStatus", "pending_review"),
                                                "riskLevel": "medium",
                                                "requiredAction": "review_table_structure",
                                                "reason": "table_block_low_confidence_or_pending_review",
                                                "sourceWorkflowKey": SOURCE_WORKFLOW_KEY,
                                            },
                                            ensure_ascii=False,
                                        ),
                                        now,
                                    ),
                                )
                            if block["blockType"] == "formula":
                                cur.execute(
                                    """
                                    insert into review_queue_items (id, review_type, status, payload, created_at)
                                    values (%s, 'question_formula_block_review', 'open', %s::jsonb, %s)
                                    on conflict (id) do update set
                                        status = excluded.status,
                                        payload = excluded.payload
                                    """,
                                    (
                                        uuid.uuid5(uuid.NAMESPACE_URL, f"real005b-formula-review:{question_id}:{block['sortOrder']}"),
                                        json.dumps(
                                            {
                                                "questionItemId": str(question_id),
                                                "questionBlockId": str(block_id),
                                                "sourceRegionId": str(source_region_id),
                                                "blockType": "formula",
                                                "sourceFormat": block["content"].get("sourceFormat", "unknown"),
                                                "confidence": block["content"].get("confidence"),
                                                "fallbackImageUrl": block["content"].get("fallbackImageUrl"),
                                                "reviewStatus": block["content"].get("reviewStatus", "pending_review"),
                                                "riskLevel": "medium",
                                                "requiredAction": "review_formula_structure",
                                                "reason": "formula_block_low_confidence_or_non_omml_candidate",
                                                "sourceWorkflowKey": SOURCE_WORKFLOW_KEY,
                                            },
                                            ensure_ascii=False,
                                        ),
                                        now,
                                    ),
                                )

                    created_question_ids.append(str(question_id))
                    year_question_ids.append(str(question_id))

                year_reports.append(
                    {
                        "year": year,
                        "status": "pass" if not year_blockers else "blocked",
                        "questionCount": len(year_question_ids),
                        "questionIds": year_question_ids[:3],
                        "blockers": year_blockers,
                    }
                )

            report = {
                "status": "pass" if args.apply else "dry_run_pass",
                "taskId": "REAL005B_REVIEWED_QUESTION_MATERIALIZE",
                "checkedAt": now.isoformat(),
                "apply": bool(args.apply),
                "activeWrite": bool(args.apply),
                "externalAiCalls": 0,
                "realStudentDataUsed": False,
                "createdQuestionCount": len(created_question_ids),
                "createdRegionCount": len(created_region_ids),
                "yearReports": year_reports,
                "questionCountAfter": scalar(conn, f"select count(*) from question_items where coalesce(custom_fields->>'sourceWorkflowKey','') = '{SOURCE_WORKFLOW_KEY}';"),
                "reviewQueueCountAfter": scalar(conn, "select count(*) from review_queue_items where review_type = 'real005b_question_materialize';"),
                "tableReviewQueueCountAfter": scalar(
                    conn,
                    f"select count(*) from review_queue_items where review_type = 'question_table_block_review' and coalesce(payload->>'sourceWorkflowKey','') = '{SOURCE_WORKFLOW_KEY}';",
                ),
                "formulaReviewQueueCountAfter": scalar(
                    conn,
                    f"select count(*) from review_queue_items where review_type = 'question_formula_block_review' and coalesce(payload->>'sourceWorkflowKey','') = '{SOURCE_WORKFLOW_KEY}';",
                ),
                "tableBlockCountAfter": scalar(
                    conn,
                    f"""
                    select count(*)
                    from question_blocks qb
                    join question_items qi on qi.id = qb.question_item_id
                    where qb.block_type = 'table'
                      and coalesce(qi.custom_fields->>'sourceWorkflowKey','') = '{SOURCE_WORKFLOW_KEY}';
                    """,
                ),
                "formulaBlockCountAfter": scalar(
                    conn,
                    f"""
                    select count(*)
                    from question_blocks qb
                    join question_items qi on qi.id = qb.question_item_id
                    where qb.block_type = 'formula'
                      and coalesce(qi.custom_fields->>'sourceWorkflowKey','') = '{SOURCE_WORKFLOW_KEY}';
                    """,
                ),
                "rollback": [
                    f"delete from review_queue_items where review_type in ('question_table_block_review', 'question_formula_block_review') and coalesce(payload->>'sourceWorkflowKey','') = '{SOURCE_WORKFLOW_KEY}';",
                    "delete from review_queue_items where review_type = 'real005b_question_materialize';",
                    f"delete from question_assets where question_item_id in (select id from question_items where custom_fields->>'sourceWorkflowKey' = '{SOURCE_WORKFLOW_KEY}');",
                    f"delete from question_blocks where question_item_id in (select id from question_items where custom_fields->>'sourceWorkflowKey' = '{SOURCE_WORKFLOW_KEY}');",
                    "delete from source_regions where region_type in ('real005b_review_question','real005b_review_answer');",
                    f"delete from question_items where custom_fields->>'sourceWorkflowKey' = '{SOURCE_WORKFLOW_KEY}';",
                ],
            }

            if args.apply:
                conn.commit()
            else:
                conn.rollback()

        except Exception:
            conn.rollback()
            raise

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    Path(args.markdown_output).write_text(
        "\n".join(
            [
                "# REAL005B Reviewed Question Materialize",
                "",
                f"- status: {report['status']}",
                f"- created_question_count: {report['createdQuestionCount']}",
                f"- created_region_count: {report['createdRegionCount']}",
                f"- question_count_after: {report['questionCountAfter']}",
                f"- review_queue_count_after: {report['reviewQueueCountAfter']}",
                f"- table_block_count_after: {report['tableBlockCountAfter']}",
                f"- formula_block_count_after: {report['formulaBlockCountAfter']}",
                f"- table_review_queue_count_after: {report['tableReviewQueueCountAfter']}",
                f"- formula_review_queue_count_after: {report['formulaReviewQueueCountAfter']}",
                "",
                "## Boundary",
                "This command is repo-side only. Use -Apply only after validating the dry run and keep rollback SQL with the report.",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import uuid
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path
from typing import Any

import psycopg
from psycopg.rows import dict_row


WORKFLOW_KEY = "guangzhou_2015_visual_region_v1"
REAL001_WORKFLOW_KEY = "guangzhou_2015_real_ingest_v1"
PAPER_SHA256 = "534d8eee3b99446d514af736aaf4cd8e36f2803154f7778c0f656f1832b7510c"
ANSWER_SHA256 = "065a6293b5c1019ed2da199736df44c6d0304797d0a986a750449197ca9ba88d"
QUESTION_RANGE = range(19, 25)

QUESTION_TAGS: dict[int, dict[str, Any]] = {
    19: {"primary": "滑轮组机械效率", "tags": ["机械效率", "功", "滑轮组"]},
    20: {"primary": "功率与受力分析", "tags": ["功", "功率", "摩擦力", "受力示意图"]},
    21: {"primary": "电热水壶与热量计算", "tags": ["欧姆定律", "电功率", "比热容", "温控开关"]},
    22: {"primary": "实验仪器读数", "tags": ["弹簧测力计", "体温计", "停表"]},
    23: {"primary": "小灯泡电功率实验", "tags": ["电功率", "电路连接", "实验数据", "故障分析"]},
    24: {"primary": "浮力测量设计", "tags": ["浮力", "排水法", "二力平衡", "实验设计"]},
}

QUESTION_VISUAL_PROFILE: dict[int, dict[str, Any]] = {
    19: {"page": 5, "bbox": [4, 8, 92, 18], "asset": False, "risk": "medium"},
    20: {"page": 5, "bbox": [4, 26, 92, 30], "asset": True, "risk": "high"},
    21: {"page": 6, "bbox": [4, 4, 92, 34], "asset": True, "risk": "high"},
    22: {"page": 7, "bbox": [4, 4, 92, 28], "asset": True, "risk": "high"},
    23: {"page": 7, "bbox": [4, 34, 92, 46], "asset": True, "risk": "high"},
    24: {"page": 8, "bbox": [4, 70, 92, 20], "asset": True, "risk": "high"},
}


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def json_dump(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), default=str)


def pretty_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2, default=str)


def normalize_text(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def rows(conn: psycopg.Connection[Any], sql: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(sql, params)
        return list(cur.fetchall())


def scalar(conn: psycopg.Connection[Any], sql: str, params: tuple[Any, ...] = ()) -> int:
    with conn.cursor() as cur:
        cur.execute(sql, params)
        value = cur.fetchone()[0]
        return int(value or 0)


def fetch_document(conn: psycopg.Connection[Any], sha256: str) -> dict[str, Any]:
    matches = rows(
        conn,
        """
        select
            sd.id as source_document_id,
            sd.source_title,
            sd.source_type,
            sd.region,
            sd.year,
            sd.material_batch_key,
            fa.id as file_asset_id,
            fa.original_file_name,
            fa.relative_path,
            fa.sha256,
            fa.size_bytes
        from source_documents sd
        join file_assets fa on fa.id = sd.file_asset_id
        where lower(fa.sha256) = %s
        order by sd.created_at desc
        """,
        (sha256,),
    )
    if not matches:
        raise RuntimeError(f"source document missing for sha256={sha256}")
    return matches[0]


def run_worker(repo_root: Path, python: str, file_root: Path, job_id: str, relative_path: str) -> dict[str, Any]:
    completed = subprocess.run(
        [
            python,
            str(repo_root / "workers" / "document" / "worker.py"),
            "--job-id",
            job_id,
            "--relative-path",
            relative_path,
            "--file-root",
            str(file_root),
        ],
        cwd=repo_root,
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        timeout=120,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"document worker failed for {relative_path}: exit={completed.returncode} stderr={completed.stderr.strip()}"
        )
    return json.loads(completed.stdout)


def document_text(worker_result: dict[str, Any]) -> str:
    parts: list[str] = []
    for page in worker_result.get("documentModel", {}).get("pages", []):
        page_no = int(page.get("pageNumber") or 1)
        for block in page.get("layoutBlocks", []):
            text = normalize_text(str(block.get("textPreview") or ""))
            if text:
                parts.append(f" [PAGE {page_no}] {text}")
    return normalize_text(" ".join(parts))


def split_by_question_numbers(text: str, question_numbers: range) -> dict[int, str]:
    numbers = "|".join(str(number) for number in question_numbers)
    pattern = re.compile(rf"(?<!\d)({numbers})\s*[.．、]\s*", re.S)
    matches = list(pattern.finditer(text))
    found: dict[int, tuple[int, int]] = {}
    for index, match in enumerate(matches):
        number = int(match.group(1))
        if number in found:
            continue
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        found[number] = (match.start(), end)

    missing = [number for number in question_numbers if number not in found]
    if missing:
        raise RuntimeError(f"missing visual question text boundaries: {missing}")

    return {
        number: normalize_text(text[start:end])
        for number, (start, end) in found.items()
        if number in question_numbers
    }


def split_answers(text: str) -> dict[int, str]:
    # The answer PDF includes Q18 before Q19. Including 18 gives Q19 a stable left boundary.
    boundaries = split_by_question_numbers(text, range(18, 25))
    return {number: boundaries[number] for number in QUESTION_RANGE}


def before_counts(conn: psycopg.Connection[Any], paper_id: str, answer_id: str) -> dict[str, int]:
    return {
        "visualWorkflowQuestions": scalar(
            conn,
            "select count(*) from question_items where custom_fields->>'sourceWorkflowKey' = %s",
            (WORKFLOW_KEY,),
        ),
        "visualSourceRegions": scalar(
            conn,
            """
            select count(*)
            from source_regions
            where source_document_id in (%s, %s)
              and region_type in ('guangzhou_2015_visual_question','guangzhou_2015_visual_answer','guangzhou_2015_visual_asset')
            """,
            (paper_id, answer_id),
        ),
        "visualQuestionAssets": scalar(
            conn,
            """
            select count(*)
            from question_assets qa
            join question_items qi on qi.id = qa.question_item_id
            where qi.custom_fields->>'sourceWorkflowKey' = %s
            """,
            (WORKFLOW_KEY,),
        ),
        "visualReviewItems": scalar(
            conn,
            "select count(*) from review_queue_items where payload::text like %s",
            (f"%{WORKFLOW_KEY}%",),
        ),
        "real001Questions": scalar(
            conn,
            "select count(*) from question_items where custom_fields->>'sourceWorkflowKey' = %s",
            (REAL001_WORKFLOW_KEY,),
        ),
    }


def cleanup_previous(conn: psycopg.Connection[Any], paper_id: str, answer_id: str) -> dict[str, int]:
    question_rows = rows(
        conn,
        "select id from question_items where custom_fields->>'sourceWorkflowKey' = %s",
        (WORKFLOW_KEY,),
    )
    question_ids = [str(row["id"]) for row in question_rows]
    deleted_blocks = 0
    deleted_assets = 0
    if question_ids:
        with conn.cursor() as cur:
            cur.execute("delete from question_blocks where question_item_id = any(%s::uuid[])", (question_ids,))
            deleted_blocks = int(cur.rowcount or 0)
            cur.execute("delete from question_assets where question_item_id = any(%s::uuid[])", (question_ids,))
            deleted_assets = int(cur.rowcount or 0)

    with conn.cursor() as cur:
        cur.execute("delete from review_queue_items where payload::text like %s", (f"%{WORKFLOW_KEY}%",))
        deleted_review_items = int(cur.rowcount or 0)
        cur.execute(
            "delete from cut_candidates where metadata::text like %s or candidate_payload::text like %s",
            (f"%{WORKFLOW_KEY}%", f"%{WORKFLOW_KEY}%"),
        )
        deleted_candidates = int(cur.rowcount or 0)
        cur.execute(
            """
            delete from source_regions
            where source_document_id in (%s, %s)
              and region_type in ('guangzhou_2015_visual_question','guangzhou_2015_visual_answer','guangzhou_2015_visual_asset')
            """,
            (paper_id, answer_id),
        )
        deleted_regions = int(cur.rowcount or 0)
        cur.execute("delete from question_items where custom_fields->>'sourceWorkflowKey' = %s", (WORKFLOW_KEY,))
        deleted_questions = int(cur.rowcount or 0)

    return {
        "deletedQuestionItems": deleted_questions,
        "deletedQuestionBlocks": deleted_blocks,
        "deletedQuestionAssets": deleted_assets,
        "deletedReviewItems": deleted_review_items,
        "deletedCutCandidates": deleted_candidates,
        "deletedSourceRegions": deleted_regions,
    }


def ensure_screenshot_manifest(file_root: Path, relative_path: str, payload: dict[str, Any]) -> None:
    target = file_root / relative_path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(pretty_json(payload), encoding="utf-8")


def insert_visual_question(
    conn: psycopg.Connection[Any],
    file_root: Path,
    paper_doc: dict[str, Any],
    answer_doc: dict[str, Any],
    question_no: int,
    question_text: str,
    answer_text: str,
    apply: bool,
    now: datetime,
) -> dict[str, Any]:
    profile = QUESTION_VISUAL_PROFILE[question_no]
    tag = QUESTION_TAGS[question_no]
    question_id = str(uuid.uuid4())
    question_region_id = str(uuid.uuid4())
    answer_region_id = str(uuid.uuid4())
    asset_region_id = str(uuid.uuid4()) if profile["asset"] else None
    candidate_id = str(uuid.uuid4())
    review_id = str(uuid.uuid4())
    bbox = profile["bbox"]
    screenshot_relative_path = f"generated/guangzhou-2015/visual-region/q{question_no:02d}-question.json"
    answer_screenshot_relative_path = f"generated/guangzhou-2015/visual-region/q{question_no:02d}-answer.json"
    asset_screenshot_relative_path = f"generated/guangzhou-2015/visual-region/q{question_no:02d}-asset.json"

    if apply:
        ensure_screenshot_manifest(
            file_root,
            screenshot_relative_path,
            {
                "sourceWorkflowKey": WORKFLOW_KEY,
                "questionNo": question_no,
                "source": paper_doc["original_file_name"],
                "page": profile["page"],
                "bboxPercent": bbox,
                "textPreview": question_text[:500],
                "note": "Text manifest for screenshot-level region review; original PDF remains the visual source.",
            },
        )
        ensure_screenshot_manifest(
            file_root,
            answer_screenshot_relative_path,
            {
                "sourceWorkflowKey": WORKFLOW_KEY,
                "questionNo": question_no,
                "source": answer_doc["original_file_name"],
                "bboxPercent": [4, 8, 92, 16],
                "textPreview": answer_text[:500],
                "note": "Answer region manifest for teacher review.",
            },
        )
        if asset_region_id:
            ensure_screenshot_manifest(
                file_root,
                asset_screenshot_relative_path,
                {
                    "sourceWorkflowKey": WORKFLOW_KEY,
                    "questionNo": question_no,
                    "source": paper_doc["original_file_name"],
                    "page": profile["page"],
                    "bboxPercent": bbox,
                    "assetType": "figure_or_diagram",
                    "note": "Question visual asset manifest; teacher must review against original PDF.",
                },
            )

    with conn.cursor() as cur:
        cur.execute(
            """
            insert into source_regions (
                id, source_document_id, page_number, x, y, width, height,
                coordinate_unit, screenshot_relative_path, region_type, created_at
            )
            values (%s, %s, %s, %s, %s, %s, %s, 'percent', %s, 'guangzhou_2015_visual_question', %s),
                   (%s, %s, 1, 4, 8, 92, 16, 'percent', %s, 'guangzhou_2015_visual_answer', %s)
            """,
            (
                question_region_id,
                str(paper_doc["source_document_id"]),
                int(profile["page"]),
                Decimal(str(bbox[0])),
                Decimal(str(bbox[1])),
                Decimal(str(bbox[2])),
                Decimal(str(bbox[3])),
                screenshot_relative_path,
                now,
                answer_region_id,
                str(answer_doc["source_document_id"]),
                answer_screenshot_relative_path,
                now,
            ),
        )
        if asset_region_id:
            cur.execute(
                """
                insert into source_regions (
                    id, source_document_id, page_number, x, y, width, height,
                    coordinate_unit, screenshot_relative_path, region_type, created_at
                )
                values (%s, %s, %s, %s, %s, %s, %s, 'percent', %s, 'guangzhou_2015_visual_asset', %s)
                """,
                (
                    asset_region_id,
                    str(paper_doc["source_document_id"]),
                    int(profile["page"]),
                    Decimal(str(bbox[0])),
                    Decimal(str(bbox[1])),
                    Decimal(str(bbox[2])),
                    Decimal(str(bbox[3])),
                    asset_screenshot_relative_path,
                    now,
                ),
            )

        custom_fields = {
            "sourceWorkflowKey": WORKFLOW_KEY,
            "parentWorkflowKey": REAL001_WORKFLOW_KEY,
            "exam": {"region": "guangzhou", "year": 2015, "subject": "physics", "paper": "2015广州中考"},
            "questionNo": question_no,
            "sourceDocumentId": str(paper_doc["source_document_id"]),
            "answerSourceDocumentId": str(answer_doc["source_document_id"]),
            "answer": {"value": answer_text, "status": "extracted_pending_review"},
            "primaryKnowledgeLabel": tag["primary"],
            "knowledgeTags": tag["tags"],
            "visualRegionStatus": "screenshot_manifest_pending_teacher_review",
            "teacherValidationRequired": True,
        }
        quality_signals = {
            "sourceWorkflowKey": WORKFLOW_KEY,
            "adapter": "pdf_text_adapter",
            "cutMode": "visual_region_manual_bbox_seed",
            "visualCoordinateStatus": "screenshot_level_manifest",
            "externalAiCalls": 0,
            "realStudentDataUsed": False,
            "teacherValidationRequired": True,
        }
        blocks = [
            {
                "type": "stem",
                "order": 0,
                "content": {"text": question_text, "questionNo": question_no, "status": "visual_cut_pending_review"},
                "source_region_id": question_region_id,
            },
            {
                "type": "answer",
                "order": 1,
                "content": {"answer": answer_text, "status": "answer_pending_review"},
                "source_region_id": answer_region_id,
            },
        ]
        cur.execute(
            """
            insert into question_items (
                id, subject, stage, grade, question_type, default_score,
                difficulty_estimated, status, primary_knowledge_id, blocks,
                custom_fields, quality_signals, created_at, updated_at
            )
            values (
                %s, 'physics', 'junior_middle_school', 'grade_9', %s, null,
                null, 'pending_review', null, %s::jsonb,
                %s::jsonb, %s::jsonb, %s, %s
            )
            """,
            (
                question_id,
                "experiment_or_calculation",
                json_dump(blocks),
                json_dump(custom_fields),
                json_dump(quality_signals),
                now,
                now,
            ),
        )
        cur.execute(
            """
            insert into question_blocks (id, question_item_id, block_type, sort_order, content, source_region_id, created_at)
            values (%s, %s, 'stem', 0, %s::jsonb, %s, %s),
                   (%s, %s, 'answer', 1, %s::jsonb, %s, %s)
            """,
            (
                str(uuid.uuid4()),
                question_id,
                json_dump({"text": question_text, "questionNo": question_no, "status": "visual_cut_pending_review"}),
                question_region_id,
                now,
                str(uuid.uuid4()),
                question_id,
                json_dump({"answer": answer_text, "status": "answer_pending_review"}),
                answer_region_id,
                now,
            ),
        )
        if asset_region_id:
            cur.execute(
                """
                insert into question_assets (id, question_item_id, file_asset_id, source_region_id, asset_type, purpose, metadata, created_at)
                values (%s, %s, %s, %s, 'image', 'question_visual_region', %s::jsonb, %s)
                """,
                (
                    str(uuid.uuid4()),
                    question_id,
                    str(paper_doc["file_asset_id"]),
                    asset_region_id,
                    json_dump(
                        {
                            "sourceWorkflowKey": WORKFLOW_KEY,
                            "questionNo": question_no,
                            "screenshotRelativePath": asset_screenshot_relative_path,
                            "teacherValidationRequired": True,
                        }
                    ),
                    now,
                ),
            )
        candidate_payload = {
            "sourceWorkflowKey": WORKFLOW_KEY,
            "questionNo": question_no,
            "pageNumber": int(profile["page"]),
            "textPreview": question_text,
            "answerPreview": answer_text[:300],
            "primaryKnowledgeLabel": tag["primary"],
            "knowledgeTags": tag["tags"],
            "visualRegionStatus": "screenshot_manifest_pending_teacher_review",
            "teacherValidationRequired": True,
        }
        cur.execute(
            """
            insert into cut_candidates (
                id, source_document_id, source_region_id, suggested_question_item_id,
                status, confidence, segment_type, sequence_no, candidate_payload,
                failure_reason, takeover_action, metadata, created_at, updated_at
            )
            values (%s, %s, %s, %s, 'pending_review', 0.82, 'visual_long_question', %s, %s::jsonb,
                    'teacher_validation_required_for_visual_long_question',
                    'manual_review',
                    %s::jsonb, %s, %s)
            """,
            (
                candidate_id,
                str(paper_doc["source_document_id"]),
                question_region_id,
                question_id,
                question_no,
                json_dump(candidate_payload),
                json_dump({"sourceWorkflowKey": WORKFLOW_KEY, "externalAiCalls": 0, "bboxPercent": bbox}),
                now,
                now,
            ),
        )
        cur.execute(
            """
            insert into review_queue_items (id, review_type, status, payload, created_at)
            values (%s, 'guangzhou_2015_question_review', 'open', %s::jsonb, %s)
            """,
            (
                review_id,
                json_dump(
                    {
                        "sourceWorkflowKey": WORKFLOW_KEY,
                        "questionNo": question_no,
                        "sourceDocumentId": str(paper_doc["source_document_id"]),
                        "answerSourceDocumentId": str(answer_doc["source_document_id"]),
                        "sourceRegionId": question_region_id,
                        "answerRegionId": answer_region_id,
                        "assetRegionId": asset_region_id,
                        "candidateId": candidate_id,
                        "questionItemId": question_id,
                        "confidence": 0.82,
                        "requiredAction": "teacher_review",
                        "reason": "visual_long_question_requires_teacher_validation",
                        "riskLevel": profile["risk"],
                        "textPreview": question_text[:240],
                        "answer": answer_text[:500],
                        "primaryKnowledgeLabel": tag["primary"],
                        "knowledgeTags": tag["tags"],
                    }
                ),
                now,
            ),
        )

    return {
        "questionNo": question_no,
        "questionItemId": question_id,
        "questionRegionId": question_region_id,
        "answerRegionId": answer_region_id,
        "assetRegionId": asset_region_id,
        "hasQuestionAsset": bool(asset_region_id),
        "pageNumber": int(profile["page"]),
        "bboxPercent": bbox,
        "textPreview": question_text[:180],
        "answerPreview": answer_text[:180],
        "primaryKnowledgeLabel": tag["primary"],
    }


def after_counts(conn: psycopg.Connection[Any]) -> dict[str, Any]:
    question_rows = rows(
        conn,
        """
        select
            (custom_fields->>'questionNo')::int as question_no,
            id,
            status,
            custom_fields->>'visualRegionStatus' as visual_region_status,
            custom_fields->>'primaryKnowledgeLabel' as primary_knowledge_label,
            custom_fields->'answer'->>'value' as answer
        from question_items
        where custom_fields->>'sourceWorkflowKey' = %s
        order by (custom_fields->>'questionNo')::int
        """,
        (WORKFLOW_KEY,),
    )
    question_ids = [str(row["id"]) for row in question_rows]
    return {
        "questionCount": len(question_rows),
        "questionNumbers": [int(row["question_no"]) for row in question_rows],
        "allHaveAnswers": all(bool(row["answer"]) for row in question_rows),
        "allHaveKnowledgeTags": all(bool(row["primary_knowledge_label"]) for row in question_rows),
        "allHaveVisualRegionStatus": all(row["visual_region_status"] == "screenshot_manifest_pending_teacher_review" for row in question_rows),
        "sourceRegionCount": scalar(
            conn,
            """
            select count(*)
            from source_regions
            where region_type in ('guangzhou_2015_visual_question','guangzhou_2015_visual_answer','guangzhou_2015_visual_asset')
            """,
        ),
        "questionAssetCount": scalar(
            conn,
            "select count(*) from question_assets where question_item_id = any(%s::uuid[])",
            (question_ids,),
        ) if question_ids else 0,
        "cutCandidateCount": scalar(
            conn,
            "select count(*) from cut_candidates where metadata::text like %s or candidate_payload::text like %s",
            (f"%{WORKFLOW_KEY}%", f"%{WORKFLOW_KEY}%"),
        ),
        "openReviewQueueCount": scalar(
            conn,
            "select count(*) from review_queue_items where status = 'open' and payload::text like %s",
            (f"%{WORKFLOW_KEY}%",),
        ),
        "questions": [dict(row) for row in question_rows],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the 2015 Guangzhou physics visual long-question slice.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5432)
    parser.add_argument("--database", default="k12_question_graph")
    parser.add_argument("--user", default="postgres")
    parser.add_argument("--password", default="")
    parser.add_argument("--file-root", default=r"D:\KQG_Data\file_store")
    parser.add_argument("--python", default=sys.executable)
    parser.add_argument("--output", default="docs/evidence/20260512-guangzhou-2015-visual-region-slice-report.json")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    output_path = repo_root / args.output
    report: dict[str, Any] = {
        "schemaVersion": "guangzhou-2015-visual-region-slice.v1",
        "workflowKey": WORKFLOW_KEY,
        "generatedAt": utc_now().isoformat(),
        "mode": "apply" if args.apply else "dry_run",
        "status": "started",
        "scope": {
            "paperSha256": PAPER_SHA256,
            "answerSha256": ANSWER_SHA256,
            "questionRange": "19-24",
            "expectedQuestionCount": 6,
            "externalAiCalls": 0,
            "realStudentDataUsed": False,
        },
    }
    conninfo = {
        "host": args.host,
        "port": args.port,
        "dbname": args.database,
        "user": args.user,
        "password": args.password,
    }
    with psycopg.connect(**conninfo) as conn:
        try:
            paper_doc = fetch_document(conn, PAPER_SHA256)
            answer_doc = fetch_document(conn, ANSWER_SHA256)
            report["sourceDocuments"] = {"paper": dict(paper_doc), "answer": dict(answer_doc)}
            report["before"] = before_counts(conn, str(paper_doc["source_document_id"]), str(answer_doc["source_document_id"]))
            if report["before"]["real001Questions"] < 18:
                raise RuntimeError("REAL001 question evidence must exist before REAL002 visual region slice")

            paper_worker = run_worker(repo_root, args.python, Path(args.file_root), "guangzhou-2015-visual-paper", str(paper_doc["relative_path"]))
            answer_worker = run_worker(repo_root, args.python, Path(args.file_root), "guangzhou-2015-visual-answer", str(answer_doc["relative_path"]))
            paper_text = document_text(paper_worker)
            answer_text = document_text(answer_worker)
            questions = split_by_question_numbers(paper_text, QUESTION_RANGE)
            answers = split_answers(answer_text)
            report["worker"] = {
                "paperAdapter": paper_worker["adapterDiagnostics"][0]["adapterName"],
                "paperPages": len(paper_worker["documentModel"]["pages"]),
                "answerAdapter": answer_worker["adapterDiagnostics"][0]["adapterName"],
                "answerPages": len(answer_worker["documentModel"]["pages"]),
                "recognizedQuestionCount": len(questions),
                "recognizedAnswerCount": len(answers),
            }
            report["questionPreview"] = [
                {
                    "questionNo": number,
                    "pageNumber": QUESTION_VISUAL_PROFILE[number]["page"],
                    "hasQuestionAsset": QUESTION_VISUAL_PROFILE[number]["asset"],
                    "bboxPercent": QUESTION_VISUAL_PROFILE[number]["bbox"],
                    "answerPreview": answers[number][:180],
                    "textPreview": questions[number][:220],
                }
                for number in QUESTION_RANGE
            ]

            conn.execute("begin")
            report["cleanup"] = cleanup_previous(conn, str(paper_doc["source_document_id"]), str(answer_doc["source_document_id"]))
            now = utc_now()
            created = [
                insert_visual_question(
                    conn,
                    Path(args.file_root),
                    paper_doc,
                    answer_doc,
                    number,
                    questions[number],
                    answers[number],
                    args.apply,
                    now,
                )
                for number in QUESTION_RANGE
            ]
            report["created"] = created
            report["after"] = after_counts(conn)
            report["verification"] = {
                "questionRangeComplete": report["after"]["questionNumbers"] == list(QUESTION_RANGE),
                "allHaveAnswers": report["after"]["allHaveAnswers"],
                "allHaveKnowledgeTags": report["after"]["allHaveKnowledgeTags"],
                "allHaveVisualRegionStatus": report["after"]["allHaveVisualRegionStatus"],
                "hasQuestionAssetsForVisualQuestions": report["after"]["questionAssetCount"] >= 5,
                "openReviewQueueCount": report["after"]["openReviewQueueCount"],
                "noExternalAiCalls": True,
                "realStudentDataUsed": False,
            }
            if not all(
                [
                    report["verification"]["questionRangeComplete"],
                    report["verification"]["allHaveAnswers"],
                    report["verification"]["allHaveKnowledgeTags"],
                    report["verification"]["allHaveVisualRegionStatus"],
                    report["verification"]["hasQuestionAssetsForVisualQuestions"],
                    report["verification"]["openReviewQueueCount"] == 6,
                ]
            ):
                raise RuntimeError("REAL002 visual verification failed")
            if args.apply:
                conn.commit()
                report["status"] = "pass"
            else:
                conn.rollback()
                report["status"] = "dry_run_pass"
            report["remainingGaps"] = [
                "Teacher must review each visual region, answer, tag, and diagram against the original PDF.",
                "REAL003 still needs 2016-2025 batch dry-run before 2015-2025 closure can advance.",
            ]
            report["rollback"] = {
                "restoreCommand": "pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-guangzhou-2015-visual-region-slice.ps1 -Apply",
                "targetedSql": [
                    f"delete from review_queue_items where payload::text like '%{WORKFLOW_KEY}%';",
                    f"delete from question_blocks where question_item_id in (select id from question_items where custom_fields->>'sourceWorkflowKey' = '{WORKFLOW_KEY}');",
                    f"delete from question_assets where question_item_id in (select id from question_items where custom_fields->>'sourceWorkflowKey' = '{WORKFLOW_KEY}');",
                    f"delete from cut_candidates where metadata::text like '%{WORKFLOW_KEY}%' or candidate_payload::text like '%{WORKFLOW_KEY}%';",
                    f"delete from question_items where custom_fields->>'sourceWorkflowKey' = '{WORKFLOW_KEY}';",
                    "delete from source_regions where region_type in ('guangzhou_2015_visual_question','guangzhou_2015_visual_answer','guangzhou_2015_visual_asset');",
                ],
            }
        except Exception as exc:
            conn.rollback()
            report["status"] = "fail"
            report["error"] = str(exc)
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_text(pretty_json(report), encoding="utf-8")
            raise

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(pretty_json(report), encoding="utf-8")
    print(pretty_json(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

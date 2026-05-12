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


WORKFLOW_KEY = "guangzhou_2015_real_ingest_v1"
PAPER_SHA256 = "534d8eee3b99446d514af736aaf4cd8e36f2803154f7778c0f656f1832b7510c"
ANSWER_SHA256 = "065a6293b5c1019ed2da199736df44c6d0304797d0a986a750449197ca9ba88d"
EXPECTED_QUESTION_COUNT = 18

QUESTION_START_RE = re.compile(r"^\s*(\d{1,2})\s*[.．、]\s*(.*)", re.DOTALL)

QUESTION_TAGS: dict[int, dict[str, Any]] = {
    1: {"primary": "分子热运动", "tags": ["分子运动", "扩散现象"]},
    2: {"primary": "串并联电路电压电流", "tags": ["电路识图", "电压表", "电流表"]},
    3: {"primary": "摩擦起电与电荷相互作用", "tags": ["静电", "电子转移"]},
    4: {"primary": "电磁波谱", "tags": ["电磁波", "频率", "波长"]},
    5: {"primary": "声音传播与频率", "tags": ["音调", "频率", "海洋声传播"]},
    6: {"primary": "做功改变内能", "tags": ["内能", "压缩空气", "温度升高"]},
    7: {"primary": "磁场对通电导体的作用", "tags": ["电动机原理", "电流方向", "受力方向"]},
    8: {"primary": "晶体熔化图像", "tags": ["熔化", "吸热", "温度时间图像"]},
    9: {"primary": "液体压强", "tags": ["深度", "橡皮膜", "压强方向"]},
    10: {"primary": "质量与密度", "tags": ["天平", "体积", "密度比较"]},
    11: {"primary": "杠杆平衡与力臂", "tags": ["杠杆", "力臂", "静止平衡"]},
    12: {"primary": "电磁铁与巨磁电阻", "tags": ["GMR", "磁场强弱", "电路动态分析"]},
    13: {"primary": "平面镜成像", "tags": ["作图", "像的运动", "速度"]},
    14: {"primary": "凸透镜成像作图", "tags": ["物距", "光路作图", "实像"]},
    15: {"primary": "凸透镜成像性质", "tags": ["实像", "倒立"]},
    16: {"primary": "机械能守恒与速度图像", "tags": ["机械能", "无摩擦轨道", "v-t图像"]},
    17: {"primary": "气体压强变化", "tags": ["二氧化碳溶解", "瓶内压强", "大气压"]},
    18: {"primary": "重力与固体压强", "tags": ["重力计算", "压强公式"]},
}


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def json_dump(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


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
    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"document worker returned invalid JSON for {relative_path}: {exc}") from exc


def flatten_blocks(worker_result: dict[str, Any]) -> list[dict[str, Any]]:
    blocks: list[dict[str, Any]] = []
    document_model = worker_result.get("documentModel", {})
    for page in document_model.get("pages", []):
        page_number = int(page.get("pageNumber") or 1)
        for index, block in enumerate(page.get("layoutBlocks", [])):
            text = normalize_text(str(block.get("textPreview") or ""))
            if not text:
                continue
            blocks.append(
                {
                    "pageNumber": page_number,
                    "textGroupIndex": index,
                    "blockType": str(block.get("blockType") or "unknown"),
                    "text": text,
                    "confidence": Decimal(str(block.get("confidence") or "0.88")),
                    "takeoverRequired": bool(block.get("takeoverRequired", False)),
                }
            )
    return blocks


def extract_questions(worker_result: dict[str, Any]) -> dict[int, dict[str, Any]]:
    questions: dict[int, dict[str, Any]] = {}
    for block in flatten_blocks(worker_result):
        match = QUESTION_START_RE.match(block["text"])
        if not match:
            continue
        question_no = int(match.group(1))
        if 1 <= question_no <= EXPECTED_QUESTION_COUNT:
            if question_no in questions:
                raise RuntimeError(f"duplicate question block detected for question {question_no}")
            questions[question_no] = block | {"questionNo": question_no}

    missing = [number for number in range(1, EXPECTED_QUESTION_COUNT + 1) if number not in questions]
    if missing:
        raise RuntimeError(f"missing question blocks: {missing}")
    if len(questions) != EXPECTED_QUESTION_COUNT:
        raise RuntimeError(f"expected {EXPECTED_QUESTION_COUNT} questions, got {len(questions)}")
    return questions


def strip_answer_prefix(text: str) -> str:
    text = normalize_text(QUESTION_START_RE.sub(r"\2", text, count=1))
    text = re.sub(r"\s+[1-4]\s*$", "", text).strip()
    return text


def extract_answers(worker_result: dict[str, Any]) -> dict[int, dict[str, Any]]:
    blocks = flatten_blocks(worker_result)
    full_text = " ".join(block["text"] for block in blocks)
    answers: dict[int, dict[str, Any]] = {}

    answer_match = re.search(r"答案\s+((?:[ABCD]\s+){11}[ABCD])", full_text)
    if answer_match:
        letters = re.findall(r"[ABCD]", answer_match.group(1))
        for index, value in enumerate(letters[:12], start=1):
            answers[index] = {
                "value": value,
                "pageNumber": 1,
                "textGroupIndex": 0,
                "rawText": value,
                "status": "extracted_pending_review",
            }

    for block in blocks:
        match = QUESTION_START_RE.match(block["text"])
        if not match:
            continue
        question_no = int(match.group(1))
        if 13 <= question_no <= EXPECTED_QUESTION_COUNT:
            answers[question_no] = {
                "value": strip_answer_prefix(block["text"]),
                "pageNumber": block["pageNumber"],
                "textGroupIndex": block["textGroupIndex"],
                "rawText": block["text"],
                "status": "extracted_pending_review",
            }

    missing = [number for number in range(1, EXPECTED_QUESTION_COUNT + 1) if number not in answers]
    if missing:
        raise RuntimeError(f"missing answer blocks: {missing}")
    return answers


def parse_options(text: str) -> list[dict[str, str]]:
    markers = list(re.finditer(r"([ABCD])\s*[.．]\s*", text))
    if len(markers) < 4:
        return []

    options: list[dict[str, str]] = []
    for index, marker in enumerate(markers[:4]):
        start = marker.end()
        end = markers[index + 1].start() if index + 1 < min(len(markers), 4) else len(text)
        options.append({"label": marker.group(1), "text": normalize_text(text[start:end])})
    return options


def question_type_for(question_no: int) -> str:
    return "single_choice" if question_no <= 12 else "fill_blank_or_drawing"


def default_score_for(question_no: int) -> Decimal | None:
    return Decimal("3") if question_no <= 12 else None


def before_counts(conn: psycopg.Connection[Any], paper_id: str, answer_id: str) -> dict[str, int]:
    return {
        "sourceRegions2015": scalar(
            conn,
            "select count(*) from source_regions where source_document_id in (%s, %s)",
            (paper_id, answer_id),
        ),
        "cutCandidates2015": scalar(
            conn,
            "select count(*) from cut_candidates where source_document_id in (%s, %s)",
            (paper_id, answer_id),
        ),
        "workflowQuestions": scalar(
            conn,
            "select count(*) from question_items where custom_fields->>'sourceWorkflowKey' = %s",
            (WORKFLOW_KEY,),
        ),
        "workflowReviewItems": scalar(
            conn,
            "select count(*) from review_queue_items where payload::text like %s",
            (f"%{WORKFLOW_KEY}%",),
        ),
    }


def cleanup_previous_workflow(conn: psycopg.Connection[Any], paper_id: str, answer_id: str) -> dict[str, int]:
    existing_question_rows = rows(
        conn,
        "select id from question_items where custom_fields->>'sourceWorkflowKey' = %s",
        (WORKFLOW_KEY,),
    )
    existing_question_ids = [str(row["id"]) for row in existing_question_rows]
    deleted_blocks = 0
    if existing_question_ids:
        with conn.cursor() as cur:
            cur.execute("delete from question_blocks where question_item_id = any(%s::uuid[])", (existing_question_ids,))
            deleted_blocks = int(cur.rowcount or 0)

    with conn.cursor() as cur:
        cur.execute("delete from question_assets where question_item_id = any(%s::uuid[])", (existing_question_ids,))
        deleted_assets = int(cur.rowcount or 0)

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
              and region_type in ('guangzhou_2015_question', 'guangzhou_2015_answer')
            """,
            (paper_id, answer_id),
        )
        deleted_regions = int(cur.rowcount or 0)

    return {
        "deletedQuestionBlocks": deleted_blocks,
        "deletedQuestionAssets": deleted_assets,
        "deletedReviewItems": deleted_review_items,
        "deletedCutCandidates": deleted_candidates,
        "deletedSourceRegions": deleted_regions,
        "existingQuestionItemsRetainedForUpdate": len(existing_question_ids),
    }


def upsert_question(
    conn: psycopg.Connection[Any],
    question_no: int,
    question: dict[str, Any],
    answer: dict[str, Any],
    paper_source_document_id: str,
    answer_source_document_id: str,
    paper_region_id: str,
    answer_region_id: str,
    now: datetime,
) -> str:
    existing = rows(
        conn,
        """
        select id
        from question_items
        where custom_fields->>'sourceWorkflowKey' = %s
          and (custom_fields->>'questionNo')::int = %s
        order by created_at
        limit 1
        """,
        (WORKFLOW_KEY, question_no),
    )
    question_id = str(existing[0]["id"]) if existing else str(uuid.uuid4())
    tag = QUESTION_TAGS[question_no]
    options = parse_options(question["text"])
    question_type = question_type_for(question_no)
    default_score = default_score_for(question_no)
    stem_content = {
        "text": question["text"],
        "questionNo": question_no,
        "options": options,
        "extractionStatus": "rule_cut_pending_teacher_review",
    }
    answer_content = {
        "answer": answer["value"],
        "rawText": answer["rawText"],
        "source": "2015广州中考答案.pdf",
        "status": answer["status"],
    }
    item_blocks = [
        {
            "type": "stem",
            "order": 0,
            "content": stem_content,
            "source_region_id": paper_region_id,
        },
        {
            "type": "answer",
            "order": 1,
            "content": answer_content,
            "source_region_id": answer_region_id,
        },
    ]
    custom_fields = {
        "sourceWorkflowKey": WORKFLOW_KEY,
        "exam": {
            "region": "guangzhou",
            "year": 2015,
            "subject": "physics",
            "paper": "2015广州中考",
        },
        "questionNo": question_no,
        "sourceDocumentId": paper_source_document_id,
        "answerSourceDocumentId": answer_source_document_id,
        "answer": {"value": answer["value"], "status": answer["status"]},
        "solution": {"text": None, "status": "not_extracted_for_first_18_slice"},
        "primaryKnowledgeLabel": tag["primary"],
        "knowledgeTags": tag["tags"],
        "taggingStatus": "rule_seed_pending_teacher_review",
        "teacherValidationRequired": True,
    }
    quality_signals = {
        "sourceWorkflowKey": WORKFLOW_KEY,
        "adapter": "pdf_text_adapter",
        "cutMode": "pdftotext_layout_question_number_rule",
        "answerMode": "answer_pdf_rule_alignment",
        "externalAiCalls": 0,
        "realStudentDataUsed": False,
        "visualCoordinateStatus": "text_group_placeholder_pending_precise_region_review",
        "teacherValidationRequired": True,
    }
    with conn.cursor() as cur:
        if existing:
            cur.execute(
                """
                update question_items
                set subject = 'physics',
                    stage = 'junior_middle_school',
                    grade = 'grade_9',
                    question_type = %s,
                    default_score = %s,
                    difficulty_estimated = null,
                    status = 'pending_review',
                    primary_knowledge_id = null,
                    blocks = %s::jsonb,
                    custom_fields = %s::jsonb,
                    quality_signals = %s::jsonb,
                    updated_at = %s
                where id = %s
                """,
                (
                    question_type,
                    default_score,
                    json_dump(item_blocks),
                    json_dump(custom_fields),
                    json_dump(quality_signals),
                    now,
                    question_id,
                ),
            )
        else:
            cur.execute(
                """
                insert into question_items (
                    id, subject, stage, grade, question_type, default_score,
                    difficulty_estimated, status, primary_knowledge_id, blocks,
                    custom_fields, quality_signals, created_at, updated_at
                )
                values (
                    %s, 'physics', 'junior_middle_school', 'grade_9', %s, %s,
                    null, 'pending_review', null, %s::jsonb,
                    %s::jsonb, %s::jsonb, %s, %s
                )
                """,
                (
                    question_id,
                    question_type,
                    default_score,
                    json_dump(item_blocks),
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
                json_dump(stem_content),
                paper_region_id,
                now,
                str(uuid.uuid4()),
                question_id,
                json_dump(answer_content),
                answer_region_id,
                now,
            ),
        )
    return question_id


def apply_workflow(
    conn: psycopg.Connection[Any],
    questions: dict[int, dict[str, Any]],
    answers: dict[int, dict[str, Any]],
    paper_doc: dict[str, Any],
    answer_doc: dict[str, Any],
) -> list[dict[str, Any]]:
    now = utc_now()
    created: list[dict[str, Any]] = []
    paper_source_document_id = str(paper_doc["source_document_id"])
    answer_source_document_id = str(answer_doc["source_document_id"])

    for question_no in range(1, EXPECTED_QUESTION_COUNT + 1):
        question = questions[question_no]
        answer = answers[question_no]
        question_region_id = str(uuid.uuid4())
        answer_region_id = str(uuid.uuid4())
        candidate_id = str(uuid.uuid4())
        review_id = str(uuid.uuid4())
        tag = QUESTION_TAGS[question_no]
        y = Decimal(str(min(94, 4 + ((question_no - 1) % 6) * 14)))

        with conn.cursor() as cur:
            cur.execute(
                """
                insert into source_regions (
                    id, source_document_id, page_number, x, y, width, height,
                    coordinate_unit, screenshot_relative_path, region_type, created_at
                )
                values (%s, %s, %s, 0, %s, 100, 10, 'percent', null, 'guangzhou_2015_question', %s),
                       (%s, %s, %s, 0, %s, 100, 8, 'percent', null, 'guangzhou_2015_answer', %s)
                """,
                (
                    question_region_id,
                    paper_source_document_id,
                    question["pageNumber"],
                    y,
                    now,
                    answer_region_id,
                    answer_source_document_id,
                    answer["pageNumber"],
                    y,
                    now,
                ),
            )

            candidate_payload = {
                "sourceWorkflowKey": WORKFLOW_KEY,
                "questionNo": question_no,
                "pageNumber": question["pageNumber"],
                "textPreview": question["text"],
                "answerPreview": answer["value"],
                "primaryKnowledgeLabel": tag["primary"],
                "knowledgeTags": tag["tags"],
                "extractionMode": "pdftotext_layout_question_number_rule",
                "teacherValidationRequired": True,
            }
            cur.execute(
                """
                insert into cut_candidates (
                    id, source_document_id, source_region_id, suggested_question_item_id,
                    status, confidence, segment_type, sequence_no, candidate_payload,
                    failure_reason, takeover_action, metadata, created_at, updated_at
                )
                values (%s, %s, %s, null, 'pending_review', 0.86, %s, %s, %s::jsonb,
                        'teacher_validation_required_for_real_material',
                        'manual_review',
                        %s::jsonb, %s, %s)
                """,
                (
                    candidate_id,
                    paper_source_document_id,
                    question_region_id,
                    question_type_for(question_no),
                    question_no,
                    json_dump(candidate_payload),
                    json_dump(
                        {
                            "sourceWorkflowKey": WORKFLOW_KEY,
                            "generatedBy": "tools/guangzhou_2015_real_ingest.py",
                            "generatedAt": now.isoformat(),
                            "externalAiCalls": 0,
                        }
                    ),
                    now,
                    now,
                ),
            )

        question_id = upsert_question(
            conn,
            question_no,
            question,
            answer,
            paper_source_document_id,
            answer_source_document_id,
            question_region_id,
            answer_region_id,
            now,
        )

        with conn.cursor() as cur:
            cur.execute(
                "update cut_candidates set suggested_question_item_id = %s where id = %s",
                (question_id, candidate_id),
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
                            "sourceDocumentId": paper_source_document_id,
                            "answerSourceDocumentId": answer_source_document_id,
                            "sourceRegionId": question_region_id,
                            "answerRegionId": answer_region_id,
                            "candidateId": candidate_id,
                            "questionItemId": question_id,
                            "confidence": 0.86,
                            "requiredAction": "teacher_review",
                            "reason": "real_exam_question_cut_answer_and_tags_require_teacher_validation",
                            "riskLevel": "medium",
                            "textPreview": question["text"][:240],
                            "answer": answer["value"],
                            "primaryKnowledgeLabel": tag["primary"],
                            "knowledgeTags": tag["tags"],
                        }
                    ),
                    now,
                ),
            )

        created.append(
            {
                "questionNo": question_no,
                "questionItemId": question_id,
                "cutCandidateId": candidate_id,
                "questionRegionId": question_region_id,
                "answerRegionId": answer_region_id,
                "answer": answer["value"],
                "primaryKnowledgeLabel": tag["primary"],
                "knowledgeTags": tag["tags"],
                "textPreview": question["text"][:160],
            }
        )
    return created


def workflow_after(conn: psycopg.Connection[Any]) -> dict[str, Any]:
    question_rows = rows(
        conn,
        """
        select
            (custom_fields->>'questionNo')::int as question_no,
            id,
            question_type,
            status,
            custom_fields->>'primaryKnowledgeLabel' as primary_knowledge_label,
            custom_fields->'knowledgeTags' as knowledge_tags,
            custom_fields->'answer'->>'value' as answer,
            left(blocks::text, 220) as blocks_preview
        from question_items
        where custom_fields->>'sourceWorkflowKey' = %s
        order by (custom_fields->>'questionNo')::int
        """,
        (WORKFLOW_KEY,),
    )
    return {
        "questionCount": len(question_rows),
        "questionNumbers": [int(row["question_no"]) for row in question_rows],
        "allHaveAnswers": all(bool(row["answer"]) for row in question_rows),
        "allHaveKnowledgeTags": all(bool(row["primary_knowledge_label"]) and bool(row["knowledge_tags"]) for row in question_rows),
        "cutCandidateCount": scalar(
            conn,
            "select count(*) from cut_candidates where metadata::text like %s or candidate_payload::text like %s",
            (f"%{WORKFLOW_KEY}%", f"%{WORKFLOW_KEY}%"),
        ),
        "sourceRegionCount": scalar(
            conn,
            """
            select count(*)
            from source_regions
            where region_type in ('guangzhou_2015_question', 'guangzhou_2015_answer')
            """,
        ),
        "openReviewQueueCount": scalar(
            conn,
            "select count(*) from review_queue_items where status = 'open' and payload::text like %s",
            (f"%{WORKFLOW_KEY}%",),
        ),
        "questions": [dict(row) for row in question_rows],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the real 2015 Guangzhou physics exam first-18 ingest slice.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5432)
    parser.add_argument("--database", default="k12_question_graph")
    parser.add_argument("--user", default="postgres")
    parser.add_argument("--password", default="")
    parser.add_argument("--file-root", default=r"D:\KQG_Data\file_store")
    parser.add_argument("--python", default=sys.executable)
    parser.add_argument("--output", default="docs/evidence/20260512-guangzhou-2015-real-ingest-slice-report.json")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    output_path = repo_root / args.output
    report: dict[str, Any] = {
        "schemaVersion": "guangzhou-2015-real-ingest-slice.v1",
        "workflowKey": WORKFLOW_KEY,
        "generatedAt": utc_now().isoformat(),
        "mode": "apply" if args.apply else "dry_run",
        "status": "started",
        "scope": {
            "paperSha256": PAPER_SHA256,
            "answerSha256": ANSWER_SHA256,
            "expectedQuestionCount": EXPECTED_QUESTION_COUNT,
            "questionRange": "1-18",
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
            report["sourceDocuments"] = {
                "paper": dict(paper_doc),
                "answer": dict(answer_doc),
            }
            report["before"] = before_counts(
                conn,
                str(paper_doc["source_document_id"]),
                str(answer_doc["source_document_id"]),
            )

            paper_worker = run_worker(
                repo_root,
                args.python,
                Path(args.file_root),
                "guangzhou-2015-real-paper",
                str(paper_doc["relative_path"]),
            )
            answer_worker = run_worker(
                repo_root,
                args.python,
                Path(args.file_root),
                "guangzhou-2015-real-answer",
                str(answer_doc["relative_path"]),
            )
            questions = extract_questions(paper_worker)
            answers = extract_answers(answer_worker)
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
                    "pageNumber": questions[number]["pageNumber"],
                    "answer": answers[number]["value"],
                    "primaryKnowledgeLabel": QUESTION_TAGS[number]["primary"],
                    "textPreview": questions[number]["text"][:180],
                }
                for number in range(1, EXPECTED_QUESTION_COUNT + 1)
            ]

            conn.execute("begin")
            cleanup = cleanup_previous_workflow(
                conn,
                str(paper_doc["source_document_id"]),
                str(answer_doc["source_document_id"]),
            )
            created = apply_workflow(conn, questions, answers, paper_doc, answer_doc)
            after = workflow_after(conn)
            report["cleanup"] = cleanup
            report["appliedRows"] = created
            report["after"] = after
            report["verification"] = {
                "exactly18Questions": after["questionCount"] == EXPECTED_QUESTION_COUNT,
                "exactly18CutCandidates": after["cutCandidateCount"] == EXPECTED_QUESTION_COUNT,
                "hasQuestionAndAnswerRegions": after["sourceRegionCount"] == EXPECTED_QUESTION_COUNT * 2,
                "allHaveAnswers": after["allHaveAnswers"],
                "allHaveKnowledgeTags": after["allHaveKnowledgeTags"],
                "allRequireTeacherReview": after["openReviewQueueCount"] == EXPECTED_QUESTION_COUNT,
                "noExternalAiCalls": True,
                "noRealStudentDataUsed": True,
            }

            if not all(report["verification"].values()):
                raise RuntimeError(f"workflow verification failed: {report['verification']}")

            report["remainingGaps"] = [
                "本 slice 只覆盖 2015 广州中考第 1-18 题；第 19-24 题由 REAL002 visual-region slice 补齐。",
                "第 1-18 题 SourceRegion 仍使用 text group placeholder 坐标；第 19-24 题已有 REAL002 screenshot manifest，但全卷仍需教师逐题复核。",
                "知识点标签为 deterministic rule seed，状态保持 pending_review，仍需教师或教研审核确认。",
                "没有调用外部 AI，没有处理真实学生成绩，因此不能宣称成绩分析或现场教师验收已完成。",
            ]
            report["rollback"] = {
                "preferred": "restore the pre-run database backup if this was part of a release rehearsal",
                "targetedSql": [
                    f"delete from review_queue_items where payload::text like '%{WORKFLOW_KEY}%';",
                    f"delete from question_blocks where question_item_id in (select id from question_items where custom_fields->>'sourceWorkflowKey' = '{WORKFLOW_KEY}');",
                    f"delete from cut_candidates where metadata::text like '%{WORKFLOW_KEY}%' or candidate_payload::text like '%{WORKFLOW_KEY}%';",
                    f"delete from question_items where custom_fields->>'sourceWorkflowKey' = '{WORKFLOW_KEY}';",
                    "delete from source_regions where region_type in ('guangzhou_2015_question','guangzhou_2015_answer');",
                ],
            }

            if args.apply:
                conn.commit()
                report["status"] = "pass"
            else:
                conn.rollback()
                report["status"] = "dry_run_pass"
        except Exception as exc:
            conn.rollback()
            report["status"] = "failed"
            report["error"] = str(exc)
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_text(pretty_json(report) + "\n", encoding="utf-8")
            print(pretty_json(report))
            return 1

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(pretty_json(report) + "\n", encoding="utf-8")
    print(pretty_json(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import psycopg
from psycopg.rows import dict_row

from guangzhou_physics_v2_materialize import C002_IMPORT_KEY, WORKFLOW_KEY


def scalar(conn: psycopg.Connection[Any], sql: str, params: tuple[Any, ...] = ()) -> int:
    with conn.cursor() as cursor:
        cursor.execute(sql, params)
        row = cursor.fetchone()
        return int(row[0]) if row else 0


def rows(conn: psycopg.Connection[Any], sql: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    with conn.cursor(row_factory=dict_row) as cursor:
        cursor.execute(sql, params)
        return list(cursor.fetchall())


def write_markdown(report: dict[str, Any], path: Path) -> None:
    counts = report["counts"]
    lines = [
        "# Guangzhou Physics v2 Asset Diagnostics",
        "",
        f"- status: {report['status']}",
        f"- checked_at: {report['checkedAt']}",
        f"- questions: {counts['questions']}",
        f"- answer_blocks: {counts['answerBlocks']}",
        f"- subquestion_blocks: {counts['subquestionBlocks']}",
        f"- formula_blocks: {counts['formulaBlocks']}",
        f"- table_blocks: {counts['tableBlocks']}",
        f"- question_assets: {counts['questionAssets']}",
        f"- open_reviews: {counts['openReviews']}",
        f"- usable_questions: {counts['usableQuestions']}",
        f"- c002_active_count: {counts['c002ActiveCount']}",
        "",
        "## Answer Text Sources",
    ]
    for item in report["answerTextSources"]:
        lines.append(f"- {item['source']}: {item['count']}")
    lines.extend(["", "## Blockers"])
    lines.extend(["- none"] if not report["blockers"] else [f"- {item}" for item in report["blockers"]])
    lines.extend(["", "## Boundary", report["boundary"]])
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Read-only Guangzhou physics v2 asset diagnostics")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5432)
    parser.add_argument("--database", default="k12_question_graph")
    parser.add_argument("--user", default="postgres")
    parser.add_argument("--file-root", default=r"D:\KQG_Data\file_store")
    parser.add_argument("--output", required=True)
    parser.add_argument("--markdown-output", required=True)
    args = parser.parse_args()

    password = os.environ.get("PGPASSWORD", "")
    if not password:
        raise ValueError("PGPASSWORD_required")

    conn = psycopg.connect(
        host=args.host,
        port=args.port,
        dbname=args.database,
        user=args.user,
        password=password,
    )
    try:
        conn.execute("set transaction read only")
        question_filter = "custom_fields->>'sourceWorkflowKey'=%s"
        counts = {
            "questions": scalar(conn, f"select count(*) from question_items where {question_filter}", (WORKFLOW_KEY,)),
            "pendingReviewQuestions": scalar(conn, f"select count(*) from question_items where {question_filter} and status='pending_review'", (WORKFLOW_KEY,)),
            "usableQuestions": scalar(conn, f"select count(*) from question_items where {question_filter} and status='usable'", (WORKFLOW_KEY,)),
            "productionEligibleQuestions": scalar(conn, f"select count(*) from question_items where {question_filter} and coalesce((custom_fields->>'productionEligible')::boolean,false)", (WORKFLOW_KEY,)),
            "missingAnswerTexts": scalar(conn, f"select count(*) from question_items where {question_filter} and coalesce(custom_fields#>>'{{answer,value}}','')=''", (WORKFLOW_KEY,)),
            "openReviews": scalar(conn, "select count(*) from review_queue_items where payload->>'sourceWorkflowKey'=%s and status='open'", (WORKFLOW_KEY,)),
            "answerBlocks": scalar(conn, "select count(*) from question_blocks b join question_items q on q.id=b.question_item_id where q.custom_fields->>'sourceWorkflowKey'=%s and b.block_type='answer'", (WORKFLOW_KEY,)),
            "subquestionBlocks": scalar(conn, "select count(*) from question_blocks b join question_items q on q.id=b.question_item_id where q.custom_fields->>'sourceWorkflowKey'=%s and b.block_type='subquestion'", (WORKFLOW_KEY,)),
            "formulaBlocks": scalar(conn, "select count(*) from question_blocks b join question_items q on q.id=b.question_item_id where q.custom_fields->>'sourceWorkflowKey'=%s and b.block_type='formula'", (WORKFLOW_KEY,)),
            "tableBlocks": scalar(conn, "select count(*) from question_blocks b join question_items q on q.id=b.question_item_id where q.custom_fields->>'sourceWorkflowKey'=%s and b.block_type='table'", (WORKFLOW_KEY,)),
            "questionAssets": scalar(conn, "select count(*) from question_assets a join question_items q on q.id=a.question_item_id where q.custom_fields->>'sourceWorkflowKey'=%s", (WORKFLOW_KEY,)),
            "uniqueAssetSourceRegions": scalar(conn, "select count(distinct a.source_region_id) from question_assets a join question_items q on q.id=a.question_item_id where q.custom_fields->>'sourceWorkflowKey'=%s", (WORKFLOW_KEY,)),
            "c002ActiveCount": scalar(conn, "select count(*) from domain_asset_versions where source_evidence->>'importKey'=%s and status='active'", (C002_IMPORT_KEY,)),
        }

        integrity = {
            "questionsWithoutAnswerSourceRegion": scalar(conn, "select count(*) from question_items q where q.custom_fields->>'sourceWorkflowKey'=%s and jsonb_array_length(coalesce(q.custom_fields->'answerSourceRegionIds','[]'::jsonb))=0", (WORKFLOW_KEY,)),
            "wrongAnswerSourceDocumentType": scalar(conn, """
                select count(*) from question_items q
                cross join lateral jsonb_array_elements_text(q.custom_fields->'answerSourceRegionIds') answer_region_id
                left join source_regions sr on sr.id=answer_region_id::uuid
                left join source_documents sd on sd.id=sr.source_document_id
                where q.custom_fields->>'sourceWorkflowKey'=%s
                  and coalesce(sd.source_type,'missing') <> 'answer_or_solution'
                """, (WORKFLOW_KEY,)),
            "answerBlockSourceTypeMismatch": scalar(conn, """
                select count(*) from question_blocks b
                join question_items q on q.id=b.question_item_id
                left join source_regions sr on sr.id=b.source_region_id
                left join source_documents sd on sd.id=sr.source_document_id
                where q.custom_fields->>'sourceWorkflowKey'=%s and b.block_type='answer'
                  and (sr.region_type <> 'guangzhou_v2_answer_document_page' or sd.source_type <> 'answer_or_solution')
                """, (WORKFLOW_KEY,)),
            "questionBlockSourceTypeMismatch": scalar(conn, """
                select count(*) from question_blocks b
                join question_items q on q.id=b.question_item_id
                left join source_regions sr on sr.id=b.source_region_id
                where q.custom_fields->>'sourceWorkflowKey'=%s and b.block_type <> 'answer'
                  and sr.region_type <> 'guangzhou_v2_question_candidate'
                """, (WORKFLOW_KEY,)),
            "orphanBlocks": scalar(conn, "select count(*) from question_blocks b join question_items q on q.id=b.question_item_id left join source_regions sr on sr.id=b.source_region_id where q.custom_fields->>'sourceWorkflowKey'=%s and sr.id is null", (WORKFLOW_KEY,)),
            "orphanAssets": scalar(conn, "select count(*) from question_assets a join question_items q on q.id=a.question_item_id left join source_regions sr on sr.id=a.source_region_id where q.custom_fields->>'sourceWorkflowKey'=%s and sr.id is null", (WORKFLOW_KEY,)),
            "assetSourceTypeMismatch": scalar(conn, "select count(*) from question_assets a join question_items q on q.id=a.question_item_id left join source_regions sr on sr.id=a.source_region_id where q.custom_fields->>'sourceWorkflowKey'=%s and sr.region_type <> 'guangzhou_v2_question_candidate'", (WORKFLOW_KEY,)),
            "fallbackWithoutOpenReview": scalar(conn, """
                select count(*) from question_items q
                where q.custom_fields->>'sourceWorkflowKey'=%s
                  and q.custom_fields->>'answerSourceMode'='whole_answer_document_pending_review'
                  and not exists (
                    select 1 from review_queue_items r
                    where r.payload->>'sourceWorkflowKey'=%s and r.status='open'
                      and r.payload->>'questionItemId'=q.id::text
                  )
                """, (WORKFLOW_KEY, WORKFLOW_KEY)),
            "answerPageBefore2020Page9": scalar(conn, """
                select count(*) from question_items q
                cross join lateral jsonb_array_elements_text(q.custom_fields->'answerSourceRegionIds') answer_region_id
                join source_regions sr on sr.id=answer_region_id::uuid
                where q.custom_fields->>'sourceWorkflowKey'=%s
                  and q.custom_fields->>'year'='2020' and sr.page_number < 9
                """, (WORKFLOW_KEY,)),
        }

        screenshot_rows = rows(conn, """
            select distinct sr.screenshot_relative_path
            from question_assets a
            join question_items q on q.id=a.question_item_id
            join source_regions sr on sr.id=a.source_region_id
            where q.custom_fields->>'sourceWorkflowKey'=%s
            order by sr.screenshot_relative_path
            """, (WORKFLOW_KEY,))
        missing_screenshots = [
            str(item["screenshot_relative_path"] or "")
            for item in screenshot_rows
            if not item["screenshot_relative_path"]
            or not (Path(args.file_root) / str(item["screenshot_relative_path"])).is_file()
        ]

        answer_text_sources = rows(conn, """
            select custom_fields->>'answerTextSource' source, count(*)::int count
            from question_items where custom_fields->>'sourceWorkflowKey'=%s
            group by 1 order by 1
            """, (WORKFLOW_KEY,))

        blockers: list[str] = []
        expected_counts = {
            "questions": 234,
            "pendingReviewQuestions": 234,
            "usableQuestions": 0,
            "productionEligibleQuestions": 0,
            "missingAnswerTexts": 0,
            "openReviews": 234,
            "answerBlocks": 234,
            "subquestionBlocks": 349,
            "formulaBlocks": 62,
            "tableBlocks": 21,
            "questionAssets": 270,
            "uniqueAssetSourceRegions": 270,
            "c002ActiveCount": 452,
        }
        for name, expected in expected_counts.items():
            if counts[name] != expected:
                blockers.append(f"{name}:{counts[name]}!=expected:{expected}")
        blockers.extend(f"{name}:{value}" for name, value in integrity.items() if value != 0)
        if missing_screenshots:
            blockers.append(f"missingQuestionRegionScreenshots:{len(missing_screenshots)}")

        report = {
            "status": "pass" if not blockers else "blocked",
            "taskId": "GUANGZHOU_PHYSICS_V2_ASSET_DIAGNOSTICS",
            "checkedAt": datetime.now(timezone.utc).isoformat(),
            "workflowKey": WORKFLOW_KEY,
            "readOnly": True,
            "counts": counts,
            "integrity": integrity,
            "answerTextSources": answer_text_sources,
            "missingQuestionRegionScreenshots": missing_screenshots[:20],
            "blockers": blockers,
            "boundary": "Read-only local PostgreSQL/FileStore diagnostics. All answers, blocks, tags, and reviews remain candidates pending teacher validation; no C002 active switch, teacher acceptance, onsite closure, or REAL005 closure is claimed.",
            "rollback": "No rollback required; the diagnostic opens a read-only transaction and writes evidence files only.",
        }
        output = Path(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        write_markdown(report, Path(args.markdown_output))
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 0 if not blockers else 2
    finally:
        conn.rollback()
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())

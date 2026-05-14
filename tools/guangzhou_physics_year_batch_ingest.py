from __future__ import annotations

import argparse
import csv
import json
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import psycopg
from psycopg.rows import dict_row


YEARS = list(range(2016, 2026))
EXPECTED_QUESTION_COUNTS = {
    2016: 24,
    2017: 24,
    2018: 24,
    2019: 24,
    2020: 24,
    2021: 18,
    2022: 18,
    2023: 18,
    2024: 18,
    2025: 18,
}
MATERIAL_BATCH_KEY = "guangzhou_physics_2016_2025"


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def rows(conn: psycopg.Connection[Any], sql: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(sql, params)
        return list(cur.fetchall())


def fetch_source_documents(conn: psycopg.Connection[Any]) -> list[dict[str, Any]]:
    return rows(
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
        where sd.material_batch_key = %s
          and sd.year between 2016 and 2025
        order by sd.year, sd.source_type, fa.original_file_name
        """,
        (MATERIAL_BATCH_KEY,),
    )


def group_by_year(items: list[dict[str, Any]]) -> dict[int, list[dict[str, Any]]]:
    grouped: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for item in items:
        try:
            year = int(item.get("year") or 0)
        except ValueError:
            continue
        if year in YEARS:
            grouped[year].append(item)
    return grouped


def material_year(row: dict[str, str]) -> int | None:
    value = row.get("year", "")
    if not value.isdigit():
        return None
    year = int(value)
    return year if year in YEARS else None


def has_source_type(materials: list[dict[str, str]], source_type: str) -> bool:
    return any(row.get("source_type") == source_type for row in materials)


def build_year_report(
    year: int,
    source_materials: list[dict[str, str]],
    questions: list[dict[str, str]],
    answers: list[dict[str, str]],
    db_documents: list[dict[str, Any]],
    file_store_root: Path,
) -> dict[str, Any]:
    expected_count = EXPECTED_QUESTION_COUNTS[year]
    question_numbers = sorted({int(row["question_number"]) for row in questions if row.get("question_number", "").isdigit()})
    answer_question_numbers = sorted(
        {int(row["question_number"]) for row in answers if row.get("question_number", "").isdigit()}
    )
    db_hash_documents = [doc for doc in db_documents if doc.get("sha256")]
    missing_files = [
        str(file_store_root / str(doc["relative_path"]).replace("/", "\\"))
        for doc in db_hash_documents
        if not (file_store_root / str(doc["relative_path"]).replace("/", "\\")).exists()
    ]
    local_exam_docs = [
        doc
        for doc in db_documents
        if doc.get("source_type") == "local_exam_paper" or "中考" in str(doc.get("source_title") or "")
    ]
    answer_docs = [
        doc
        for doc in db_documents
        if "答案" in str(doc.get("source_title") or "")
        or "答案" in str(doc.get("original_file_name") or "")
        or "解析版" in str(doc.get("source_title") or "")
        or "解析版" in str(doc.get("original_file_name") or "")
        or doc.get("source_type") == "answer_or_solution"
    ]
    year_report_docs = [
        doc
        for doc in db_documents
        if doc.get("source_type") in {"exam_analysis_report", "exam_year_report"} or "年报" in str(doc.get("source_title") or "")
    ]

    warnings: list[str] = []
    if not has_source_type(source_materials, "local_exam_paper"):
        warnings.append("source_material_csv_missing_local_exam_paper; check combined paper+answer source mapping")
    if any(row.get("production_eligible") != "false" for row in source_materials + questions + answers):
        warnings.append("unexpected_production_eligible_value; dry-run requires non-production candidate rows")

    blockers: list[str] = []
    if len(db_hash_documents) < 2:
        blockers.append("db_source_hash_coverage_missing")
    if missing_files:
        blockers.append("file_store_blob_missing")
    if len(local_exam_docs) < 1:
        blockers.append("paper_source_document_missing")
    if len(answer_docs) < 1:
        blockers.append("answer_source_document_missing")
    if len(year_report_docs) < 1:
        blockers.append("year_report_source_document_missing")
    if len(question_numbers) != expected_count:
        blockers.append("question_count_mismatch")
    if len(answer_question_numbers) != expected_count:
        blockers.append("answer_count_mismatch")
    if question_numbers != answer_question_numbers:
        blockers.append("question_answer_number_mismatch")
    if any(row.get("review_status") != "pending_review" for row in questions + answers):
        blockers.append("candidate_rows_not_pending_review")
    if any(row.get("production_eligible") != "false" for row in questions + answers):
        blockers.append("candidate_rows_marked_production_eligible")

    source_hashes = [
        {
            "sourceDocumentId": str(doc["source_document_id"]),
            "sourceType": doc["source_type"],
            "title": doc["source_title"],
            "fileName": doc["original_file_name"],
            "relativePath": doc["relative_path"],
            "sha256": doc["sha256"],
            "sizeBytes": int(doc["size_bytes"] or 0),
        }
        for doc in db_hash_documents
    ]

    return {
        "year": year,
        "expectedQuestionCount": expected_count,
        "sourceMaterialRows": len(source_materials),
        "dbSourceDocuments": len(db_documents),
        "dbSourceDocumentsWithHash": len(db_hash_documents),
        "sourceHashes": source_hashes,
        "questionCount": len(question_numbers),
        "answerCount": len(answer_question_numbers),
        "answerCoverage": round(len(answer_question_numbers) / expected_count, 4),
        "questionNumbers": question_numbers,
        "answerQuestionNumbers": answer_question_numbers,
        "adapterQuality": {
            "csvParseQuality": sorted({row.get("parse_quality", "") for row in source_materials if row.get("parse_quality")}),
            "dbFileHashCoveragePass": len(db_hash_documents) == len(db_documents) and len(db_documents) > 0,
            "fileStoreExistencePass": len(missing_files) == 0,
            "workerProbe": "not_run_in_batch_dry_run; source hashes and structured candidate rows verified",
        },
        "manualTakeoverPoints": warnings
        + [
            "teacher_review_required_for_all_candidate_questions",
            "screenshot_level_source_regions_not_created_by_REAL003_dry_run",
            "no_active_write; keep all candidate rows pending_review",
        ],
        "rollbackSql": [
            f"delete from review_queue_items where import_key = 'guangzhou_{year}_question_review';",
            f"delete from cut_candidates where source_document_id in (select id from source_documents where material_batch_key = '{MATERIAL_BATCH_KEY}' and year = {year});",
            f"delete from question_items where import_key = 'guangzhou_{year}_real_batch_v1';",
        ],
        "blockers": blockers,
    }


def write_markdown(report: dict[str, Any], path: Path) -> None:
    lines = [
        "# REAL003 广州 2016-2025 真卷批量 dry-run",
        "",
        f"- status: {report['status']}",
        f"- task: {report['taskId']}",
        f"- dry_run_only: {str(report['dryRunOnly']).lower()}",
        f"- years_checked: {report['yearsChecked']}",
        f"- total_questions: {report['totals']['questions']}",
        f"- total_answers: {report['totals']['answers']}",
        f"- external_ai_calls: {report['externalAiCalls']}",
        f"- active_write: {str(report['activeWrite']).lower()}",
        "",
        "## 年度结果",
    ]
    for item in report["years"]:
        blockers = ", ".join(item["blockers"]) if item["blockers"] else "none"
        lines.append(
            f"- {item['year']}: questions={item['questionCount']}/{item['expectedQuestionCount']}; "
            f"answers={item['answerCount']}/{item['expectedQuestionCount']}; "
            f"source_hashes={item['dbSourceDocumentsWithHash']}; blockers={blockers}"
        )
    lines.extend(
        [
            "",
            "## 接管与回滚",
            "- 所有候选题保持 pending_review，不写 active。",
            "- 逐年 rollbackSql 已写入 JSON report。",
            "- REAL003 只证明批量 dry-run 计划和来源/答案覆盖，不证明教师验收。",
        ]
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="REAL003 Guangzhou physics 2016-2025 batch ingest dry-run")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5432)
    parser.add_argument("--database", default="k12_question_graph")
    parser.add_argument("--user", default="postgres")
    parser.add_argument("--password", default="")
    parser.add_argument("--csv-root", default="guangzhou-physics-full-research-package-2016-2025/csv")
    parser.add_argument("--file-root", default=r"D:\KQG_Data\file_store")
    parser.add_argument("--output", default="docs/evidence/20260514-real003-guangzhou-physics-year-batch-ingest-report.json")
    parser.add_argument("--markdown-output", default="docs/evidence/20260514-real003-guangzhou-physics-year-batch-ingest-report.md")
    args = parser.parse_args()

    csv_root = Path(args.csv_root)
    source_material_rows = read_csv(csv_root / "c003-source-material.csv")
    question_rows = read_csv(csv_root / "c003-question-item-full.csv")
    answer_rows = read_csv(csv_root / "c003-answer-scoring-point.csv")

    sources_by_year: dict[int, list[dict[str, str]]] = defaultdict(list)
    questions_by_year: dict[int, list[dict[str, str]]] = defaultdict(list)
    answers_by_year: dict[int, list[dict[str, str]]] = defaultdict(list)
    for row in source_material_rows:
        year = material_year(row)
        if year is not None and row.get("region") == "Guangzhou":
            sources_by_year[year].append(row)
    for row in question_rows:
        year = material_year(row)
        if year is not None:
            questions_by_year[year].append(row)
    for row in answer_rows:
        year = material_year(row)
        if year is not None:
            answers_by_year[year].append(row)

    with psycopg.connect(
        host=args.host,
        port=args.port,
        dbname=args.database,
        user=args.user,
        password=args.password,
        row_factory=dict_row,
    ) as conn:
        db_by_year = group_by_year(fetch_source_documents(conn))

    year_reports = [
        build_year_report(
            year,
            sources_by_year[year],
            questions_by_year[year],
            answers_by_year[year],
            db_by_year[year],
            Path(args.file_root),
        )
        for year in YEARS
    ]
    all_blockers = [
        {"year": item["year"], "blocker": blocker}
        for item in year_reports
        for blocker in item["blockers"]
    ]
    status = "dry_run_pass" if not all_blockers else "dry_run_blocked"
    report: dict[str, Any] = {
        "status": status,
        "taskId": "REAL003",
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "materialBatchKey": MATERIAL_BATCH_KEY,
        "dryRunOnly": True,
        "activeWrite": False,
        "externalAiCalls": 0,
        "realStudentDataUsed": False,
        "yearsChecked": YEARS,
        "totals": {
            "questions": sum(item["questionCount"] for item in year_reports),
            "answers": sum(item["answerCount"] for item in year_reports),
            "dbSourceDocuments": sum(item["dbSourceDocuments"] for item in year_reports),
            "dbSourceDocumentsWithHash": sum(item["dbSourceDocumentsWithHash"] for item in year_reports),
        },
        "blockers": all_blockers,
        "years": year_reports,
        "completionBoundary": (
            "REAL003 proves 2016-2025 batch ingest planning and dry-run evidence only; "
            "it does not write active data or prove teacher validation."
        ),
        "rollback": "git restore tracked files; for any later apply run, execute per-year rollbackSql from this report inside a reviewed transaction.",
        "summaryChinese": (
            "REAL003 dry-run 已核对 2016-2025 来源 hash、题数、答案覆盖、adapter 质量、异常接管点和回滚 SQL；"
            "所有候选仍为 pending_review，未写 active。"
            if status == "dry_run_pass"
            else "REAL003 dry-run 发现阻断项；不得进入批量写入或 active。"
        ),
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
    write_markdown(report, Path(args.markdown_output))
    print(json.dumps(report, ensure_ascii=False, indent=2, default=str))
    return 0 if status == "dry_run_pass" else 2


if __name__ == "__main__":
    raise SystemExit(main())

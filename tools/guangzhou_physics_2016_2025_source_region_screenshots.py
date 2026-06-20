from __future__ import annotations

import argparse
import csv
import json
import re
import shutil
import subprocess
import uuid
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import psycopg
from psycopg.rows import dict_row


YEARS = list(range(2016, 2026))
QUESTION_VISUAL_TYPES = {
    "analysis_calculation",
    "comprehensive_calculation",
    "experiment_inquiry",
    "fill_or_drawing",
}
VISUAL_HINTS = (
    "图",
    "表",
    "示意图",
    "实验",
    "作图",
    "描点",
    "连线",
    "电路图",
    "画出",
    "设计实验",
    "探究",
)

SOURCE_MATERIAL_CSV = "guangzhou-physics-full-research-package-2016-2025/csv/c003-source-material.csv"
QUESTION_CSV = "guangzhou-physics-full-research-package-2016-2025/csv/c003-question-item-full.csv"
SUBQUESTION_CSV = "guangzhou-physics-full-research-package-2016-2025/csv/c003-subquestion-item-full.csv"
MATERIAL_BATCH_KEY = "guangzhou_physics_2016_2025"


def read_csv(repo_root: Path, relative_path: str) -> list[dict[str, str]]:
    with (repo_root / relative_path).open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def parse_pages(*values: str | None) -> list[int]:
    page_numbers: set[int] = set()
    for value in values:
        if not value:
            continue
        for match in re.finditer(r"(?i)p\s*(\d+)", value):
            page_numbers.add(int(match.group(1)))
    return sorted(page_numbers)


def is_visual_question(row: dict[str, str]) -> bool:
    question_type = str(row.get("question_type") or "").strip()
    if question_type in QUESTION_VISUAL_TYPES:
        return True
    stem = str(row.get("stem_summary") or "")
    return any(token in stem for token in VISUAL_HINTS)


def group_by_year(rows: list[dict[str, str]]) -> dict[int, list[dict[str, str]]]:
    grouped: dict[int, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        year_text = str(row.get("year") or "").strip()
        if not year_text.isdigit():
            continue
        year = int(year_text)
        if year in YEARS:
            grouped[year].append(row)
    return grouped


def group_by_question_id(rows: list[dict[str, str]]) -> dict[str, list[dict[str, str]]]:
    grouped: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        question_id = str(row.get("question_id") or "").strip()
        if question_id:
            grouped[question_id].append(row)
    return grouped


def read_source_documents(
    conn: psycopg.Connection[Any],
    year: int,
    source_file: str,
) -> list[dict[str, Any]]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            select
                sd.id as source_document_id,
                sd.source_title,
                sd.source_type,
                sd.year,
                sd.material_batch_key,
                fa.original_file_name,
                fa.relative_path,
                fa.sha256,
                fa.size_bytes
            from source_documents sd
            join file_assets fa on fa.id = sd.file_asset_id
            where sd.material_batch_key = %s
              and sd.year = %s
              and fa.original_file_name = %s
            order by sd.created_at desc
            """,
            (MATERIAL_BATCH_KEY, year, source_file),
        )
        return list(cur.fetchall())


def pdf_page_count(pdfinfo: str, pdf_path: Path) -> int:
    completed = subprocess.run(
        [pdfinfo, str(pdf_path)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=60,
    )
    match = re.search(r"(?m)^Pages:\s+(\d+)\s*$", completed.stdout)
    if not match:
        if pdf_path.exists():
            return 1
        raise RuntimeError(f"pdfinfo did not report page count for {pdf_path}: {completed.stderr.strip() or completed.stdout.strip()}")
    return int(match.group(1))


def render_page(pdftoppm: str, pdf_path: Path, page_number: int, target_path: Path, scratch_root: Path) -> None:
    if target_path.exists():
        return

    target_path.parent.mkdir(parents=True, exist_ok=True)
    scratch_root.mkdir(parents=True, exist_ok=True)
    scratch_dir = scratch_root / f"kqg-real005b-page-{uuid.uuid4().hex}"
    scratch_dir.mkdir(parents=True, exist_ok=True)
    try:
        prefix = scratch_dir / "page"
        completed = subprocess.run(
            [
                pdftoppm,
                "-png",
                "-r",
                "180",
                "-f",
                str(page_number),
                "-l",
                str(page_number),
                "-singlefile",
                str(pdf_path),
                str(prefix),
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=120,
        )
        rendered = prefix.with_suffix(".png")
        if rendered.exists():
            shutil.copy2(rendered, target_path)
            return
        raise RuntimeError(
            f"pdftoppm failed for {pdf_path} page {page_number}: "
            f"{completed.stderr.strip() or completed.stdout.strip()}"
        )
    finally:
        shutil.rmtree(scratch_dir, ignore_errors=True)


def source_material_lookup(rows: list[dict[str, str]]) -> dict[tuple[int, str], dict[str, str]]:
    lookup: dict[tuple[int, str], dict[str, str]] = {}
    for row in rows:
        year_text = str(row.get("year") or "").strip()
        source_file = str(row.get("source_file") or "").strip()
        if year_text.isdigit() and source_file:
            lookup[(int(year_text), source_file)] = row
    return lookup


def build_year_report(
    repo_root: Path,
    conn: psycopg.Connection[Any],
    file_root: Path,
    scratch_root: Path,
    pdftoppm: str,
    pdfinfo: str,
    year: int,
    year_questions: list[dict[str, str]],
    subquestions_by_question: dict[str, list[dict[str, str]]],
    source_material_lookup_by_year_file: dict[tuple[int, str], dict[str, str]],
) -> dict[str, Any]:
    source_files = sorted({str(row.get("source_file") or "").strip() for row in year_questions if str(row.get("source_file") or "").strip()})
    if not source_files:
        return {
            "year": year,
            "status": "blocked",
            "blockers": ["question_source_file_missing"],
            "questions": [],
            "renderedPages": [],
        }

    question_details: list[dict[str, Any]] = []
    rendered_pages: list[dict[str, Any]] = []
    rendered_page_paths: dict[tuple[str, int], str] = {}
    blockers: list[str] = []
    rendered_source_docs: list[dict[str, Any]] = []

    for source_file in source_files:
        docs = read_source_documents(conn, year, source_file)
        if not docs:
            blockers.append(f"source_document_missing:{source_file}")
            continue
        source_doc = docs[0]
        rendered_source_docs.append(
            {
                "sourceFile": source_file,
                "sourceDocumentId": str(source_doc["source_document_id"]),
                "relativePath": str(source_doc["relative_path"]),
                "sourceType": str(source_doc["source_type"]),
            }
        )
        pdf_path = file_root / Path(str(source_doc["relative_path"]))
        if not pdf_path.exists():
            blockers.append(f"paper_file_missing:{source_file}")
            continue

        page_count = pdf_page_count(pdfinfo, pdf_path)
        page_numbers = sorted(
            {
                page_number
                for row in year_questions
                if str(row.get("source_file") or "").strip() == source_file
                for page_number in parse_pages(
                    row.get("page_or_location"),
                    *(sq.get("page_or_location") for sq in subquestions_by_question.get(str(row.get("question_id") or "").strip(), [])),
                )
            }
        )
        if not page_numbers:
            blockers.append(f"page_location_missing:{source_file}")
            continue

        for page_number in page_numbers:
            if page_number < 1 or page_number > page_count:
                blockers.append(f"page_out_of_range:{source_file}:p{page_number}")
                continue
            relative_path = f"generated/guangzhou-physics-2016-2025/source-pages/{year}/{source_doc['source_document_id']}/page-{page_number:03d}.png"
            render_page(pdftoppm, pdf_path, page_number, file_root / Path(relative_path), scratch_root)
            rendered_page_paths[(source_file, page_number)] = relative_path
            rendered_pages.append(
                {
                    "sourceFile": source_file,
                    "pageNumber": page_number,
                    "relativePath": relative_path,
                }
            )

    for row in year_questions:
        question_id = str(row.get("question_id") or "").strip()
        source_file = str(row.get("source_file") or "").strip()
        question_pages = parse_pages(
            row.get("page_or_location"),
            *(sq.get("page_or_location") for sq in subquestions_by_question.get(question_id, [])),
        )
        source_page_paths = [rendered_page_paths.get((source_file, page_number)) for page_number in question_pages]
        source_page_paths = [path for path in source_page_paths if path]
        visual = is_visual_question(row)
        asset_paths = list(source_page_paths) if visual else []
        question_details.append(
            {
                "questionId": question_id,
                "questionNumber": int(row.get("question_number") or 0),
                "questionType": row.get("question_type"),
                "sourceFile": source_file,
                "pageOrLocation": row.get("page_or_location"),
                "sourcePageNumbers": question_pages,
                "sourcePageScreenshotRelativePaths": source_page_paths,
                "hasVisualAsset": visual,
                "assetScreenshotRelativePaths": asset_paths,
                "answerSourceId": row.get("answer_source_id"),
                "yearReportSourceId": row.get("year_report_source_id"),
            }
        )

    question_count = len(year_questions)
    questions_with_source_pages = sum(1 for item in question_details if item["sourcePageScreenshotRelativePaths"])
    visual_questions = sum(1 for item in question_details if item["hasVisualAsset"])
    visual_questions_with_assets = sum(1 for item in question_details if item["hasVisualAsset"] and item["assetScreenshotRelativePaths"])

    year_blockers = list(blockers)
    if question_count == 0:
        year_blockers.append("question_rows_missing")
    if questions_with_source_pages != question_count:
        year_blockers.append("question_source_page_unresolved")
    if visual_questions != visual_questions_with_assets:
        year_blockers.append("visual_question_asset_screenshot_missing")

    return {
        "year": year,
        "status": "pass" if not year_blockers else "blocked",
        "sourceFiles": source_files,
        "sourceDocuments": rendered_source_docs,
        "questionCount": question_count,
        "visualQuestionCount": visual_questions,
        "questionsWithSourcePages": questions_with_source_pages,
        "visualQuestionsWithAssets": visual_questions_with_assets,
        "renderedPageCount": len(rendered_pages),
        "renderedPages": rendered_pages,
        "questions": question_details,
        "blockers": year_blockers,
    }


def write_markdown(report: dict[str, Any], path: Path) -> None:
    lines = [
        "# REAL005B Source Region Screenshots",
        "",
        f"- status: {report['status']}",
        f"- checked_at: {report['checkedAt']}",
        f"- file_root: `{report['fileRoot']}`",
        f"- rendered_pages: {report['totals']['renderedPages']}",
        f"- visual_questions: {report['totals']['visualQuestions']}",
        "",
        "## Years",
    ]
    for year in report["years"]:
        blockers = "none" if not year["blockers"] else " | ".join(year["blockers"])
        lines.append(
            f"- {year['year']}: status={year['status']}; "
            f"questions={year['questionCount']}; "
            f"pages={year['renderedPageCount']}; "
            f"visual={year['visualQuestionCount']}; blockers={blockers}"
        )
    lines.extend(
        [
            "",
            "## Boundary",
            "This report renders page screenshots for already-admitted Guangzhou source PDFs and records page-level source-region coverage. It does not write database rows, call external AI, or touch teacher-review state.",
        ]
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="REAL005B source-region screenshot evidence for Guangzhou 2016-2025")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5432)
    parser.add_argument("--database", default="k12_question_graph")
    parser.add_argument("--user", default="postgres")
    parser.add_argument("--password", default="")
    parser.add_argument("--file-root", default=r"D:\KQG_Data\file_store")
    parser.add_argument("--csv-root", default="guangzhou-physics-full-research-package-2016-2025/csv")
    parser.add_argument("--pdftoppm", default="pdftoppm")
    parser.add_argument("--pdfinfo", default="pdfinfo")
    parser.add_argument("--output", required=True)
    parser.add_argument("--markdown-output", required=True)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    file_root = Path(args.file_root)
    question_rows = read_csv(repo_root, f"{args.csv_root}/c003-question-item-full.csv")
    subquestion_rows = read_csv(repo_root, f"{args.csv_root}/c003-subquestion-item-full.csv")
    source_material_rows = read_csv(repo_root, f"{args.csv_root}/c003-source-material.csv")

    questions_by_year = group_by_year(question_rows)
    subquestions_by_question = group_by_question_id(subquestion_rows)
    source_material_lookup_by_year_file = source_material_lookup(source_material_rows)

    connection = (
        f"host={args.host} port={args.port} dbname={args.database} "
        f"user={args.user} password={args.password}"
    )

    with psycopg.connect(connection, row_factory=dict_row) as conn:
        years: list[dict[str, Any]] = []
        scratch_root = file_root.parent / "render-scratch"
        for year in YEARS:
            years.append(
                build_year_report(
                    repo_root,
                    conn,
                    file_root,
                    scratch_root,
                    args.pdftoppm,
                    args.pdfinfo,
                    year,
                    questions_by_year.get(year, []),
                    subquestions_by_question,
                    source_material_lookup_by_year_file,
                )
            )

    blocked_years = [year["year"] for year in years if year["status"] != "pass"]
    report: dict[str, Any] = {
        "status": "pass" if not blocked_years else "partial",
        "taskId": "REAL005B_SOURCE_REGION_SCREENSHOTS",
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "fileRoot": str(file_root),
        "csvRoot": str((repo_root / args.csv_root).resolve()),
        "sourceEvidence": [
            SOURCE_MATERIAL_CSV,
            QUESTION_CSV,
            SUBQUESTION_CSV,
        ],
        "requiredYears": YEARS,
        "blockedYears": blocked_years,
        "activeWrite": False,
        "externalAiCalls": 0,
        "realStudentDataUsed": False,
        "totals": {
            "questions": sum(year["questionCount"] for year in years),
            "visualQuestions": sum(year["visualQuestionCount"] for year in years),
            "renderedPages": sum(year["renderedPageCount"] for year in years),
        },
        "years": years,
        "sourceRegionCoveragePass": len(blocked_years) == 0,
        "boundary": "read-only REAL005B source-region screenshot evidence; no database write, no teacher-review closure, no external AI",
        "rollback": "git clean -f -- docs/evidence/<date>-real005b-source-region-screenshots.json docs/evidence/<date>-real005b-source-region-screenshots.md",
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    write_markdown(report, Path(args.markdown_output))
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["status"] == "pass" else 2


if __name__ == "__main__":
    raise SystemExit(main())

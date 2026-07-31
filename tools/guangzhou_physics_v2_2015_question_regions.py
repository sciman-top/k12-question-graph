from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import psycopg
from psycopg.rows import dict_row

from guangzhou_physics_v2_question_regions import (
    DEFAULT_MATERIAL_BATCH_KEY,
    build_question_regions,
)
from guangzhou_physics_2016_2025_source_region_screenshots import (
    generated_page_relative_path,
    image_quality,
)


YEAR = 2015
EXPECTED_QUESTION_COUNT = 24


def read_paper_source(connection: str, material_batch_key: str) -> dict[str, Any]:
    with psycopg.connect(connection, row_factory=dict_row) as conn:
        rows = list(
            conn.execute(
                """
                select
                    sd.id as source_document_id,
                    sd.year,
                    sd.source_title,
                    fa.original_file_name,
                    fa.relative_path,
                    fa.sha256
                from source_documents sd
                join file_assets fa on fa.id = sd.file_asset_id
                where sd.material_batch_key = %s
                  and sd.year = %s
                  and sd.source_type = 'local_exam_paper'
                order by sd.id
                """,
                (material_batch_key, YEAR),
            ).fetchall()
        )
    if len(rows) != 1:
        raise RuntimeError(f"expected one 2015 local_exam_paper in {material_batch_key}, got {len(rows)}")
    return dict(rows[0])


def render_page(pdftoppm: str, source_pdf: Path, page_number: int, target: Path) -> None:
    if target.exists():
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    prefix = target.with_suffix("")
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
            str(source_pdf),
            str(prefix),
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=120,
    )
    if completed.returncode != 0 or not target.exists():
        raise RuntimeError(
            f"pdftoppm failed for 2015 page {page_number}: "
            f"{completed.stderr.strip() or completed.stdout.strip()}"
        )


def build_source_page_report(
    file_root: Path,
    material_batch_key: str,
    source: dict[str, Any],
    pdftoppm: str,
) -> dict[str, Any]:
    from pypdf import PdfReader

    source_pdf = file_root / Path(str(source["relative_path"]))
    page_count = len(PdfReader(source_pdf).pages)
    if page_count < 1:
        raise RuntimeError("2015 paper has no pages")
    rendered_pages: list[dict[str, Any]] = []
    for page_number in range(1, page_count + 1):
        relative_path = generated_page_relative_path(
            material_batch_key,
            YEAR,
            source["source_document_id"],
            page_number,
        )
        target = file_root / Path(relative_path)
        render_page(pdftoppm, source_pdf, page_number, target)
        quality = image_quality(target)
        if not quality["nonBlank"]:
            raise RuntimeError(f"2015 source page is blank: {page_number}")
        rendered_pages.append({"pageNumber": page_number, "relativePath": relative_path, "imageQuality": quality})
    return {
        "status": "pass",
        "materialBatchKey": material_batch_key,
        "years": [{"year": YEAR, "renderedPages": rendered_pages}],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Build v2 Guangzhou 2015 question-region candidates")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5432)
    parser.add_argument("--database", default="k12_question_graph")
    parser.add_argument("--user", default="postgres")
    parser.add_argument("--password", default=os.environ.get("PGPASSWORD", ""))
    parser.add_argument("--material-batch-key", default=DEFAULT_MATERIAL_BATCH_KEY)
    parser.add_argument("--file-root", default=r"D:\KQG_Data\file_store")
    parser.add_argument("--pdftoppm", default=shutil.which("pdftoppm.exe") or "")
    parser.add_argument("--output", required=True)
    parser.add_argument("--markdown-output", required=True)
    args = parser.parse_args()

    if not args.pdftoppm:
        raise RuntimeError("pdftoppm is required for 2015 v2 source-page rendering")
    connection = f"host={args.host} port={args.port} dbname={args.database} user={args.user} password={args.password}"
    file_root = Path(args.file_root)
    source = read_paper_source(connection, args.material_batch_key)
    source_page_report = build_source_page_report(file_root, args.material_batch_key, source, args.pdftoppm)
    year_report = build_question_regions(
        file_root,
        args.material_batch_key,
        source,
        source_page_report,
        EXPECTED_QUESTION_COUNT,
    )
    report = {
        "status": year_report["status"],
        "taskId": "GUANGZHOU_PHYSICS_V2_2015_QUESTION_REGIONS",
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "materialBatchKey": args.material_batch_key,
        "fileRoot": str(file_root),
        "activeWrite": False,
        "externalAiCalls": 0,
        "realStudentDataUsed": False,
        "totals": {
            "questionCandidates": EXPECTED_QUESTION_COUNT,
            "regionCandidates": year_report["regionCount"],
            "manualTakeovers": len(year_report["manualTakeoverCandidates"]),
            "manualVisualOverrides": len(year_report["manualVisualOverrides"]),
            "blockedItems": len(year_report["blockers"]),
            "sourcePages": len(source_page_report["years"][0]["renderedPages"]),
        },
        "sourcePageEvidence": source_page_report,
        "year": year_report,
        "boundary": "candidate-only v2 2015 question crops; no database write, no approval, no active switch",
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    Path(args.markdown_output).write_text(
        "# Guangzhou Physics v2 2015 Question Region Candidates\n\n"
        f"- status: {report['status']}\n"
        f"- material_batch_key: `{report['materialBatchKey']}`\n"
        f"- source_pages: {report['totals']['sourcePages']}\n"
        f"- question_candidates: {report['totals']['questionCandidates']}\n"
        f"- region_candidates: {report['totals']['regionCandidates']}\n"
        f"- manual_takeovers: {report['totals']['manualTakeovers']}\n"
        f"- manual_visual_overrides: {report['totals']['manualVisualOverrides']}\n\n"
        "## Boundary\n\n"
        "These are machine-generated v2 2015 question-region candidates. They do not replace teacher review, write database rows, or change C002 active assets.\n",
        encoding="utf-8",
    )
    print(json.dumps({"status": report["status"], "totals": report["totals"], "blockers": year_report["blockers"]}, ensure_ascii=False, indent=2))
    return 2 if year_report["blockers"] else 0


if __name__ == "__main__":
    raise SystemExit(main())

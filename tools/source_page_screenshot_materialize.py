from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import tempfile
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import psycopg
from psycopg.rows import dict_row


SAFE_BATCH_KEY = re.compile(r"^[A-Za-z0-9_-]+$")
PDF_PAGES = re.compile(r"^Pages:\s+(\d+)\s*$", re.MULTILINE)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def relative_page_path(material_batch_key: str, year: int, document_id: str, page_number: int) -> str:
    if not SAFE_BATCH_KEY.fullmatch(material_batch_key):
        raise ValueError(f"unsafe material batch key: {material_batch_key}")
    if year < 1900 or year > 2200:
        raise ValueError(f"invalid source year: {year}")
    if page_number < 1:
        raise ValueError(f"invalid page number: {page_number}")
    batch = material_batch_key.replace("_", "-")
    return f"generated/{batch}/source-pages/{year}/{document_id}/page-{page_number:03d}.png"


def validate_png(path: Path) -> dict[str, Any]:
    payload = path.read_bytes()
    if len(payload) < 1024 or payload[:8] != b"\x89PNG\r\n\x1a\n" or payload[12:16] != b"IHDR":
        raise ValueError(f"invalid PNG payload: {path}")
    width, height = struct.unpack(">II", payload[16:24])
    if width < 100 or height < 100:
        raise ValueError(f"invalid PNG dimensions: {path} ({width}x{height})")
    return {
        "bytes": len(payload),
        "width": width,
        "height": height,
        "sha256": hashlib.sha256(payload).hexdigest(),
    }


def curriculum_anchor_pages(path: Path) -> dict[str, set[int]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    result: dict[str, set[int]] = defaultdict(set)
    for requirement in payload.get("requirements", []):
        for wrapper in requirement.get("facets", []):
            for anchor in wrapper.get("facet", {}).get("evidence_anchors", []):
                document_id = anchor.get("source_document_id")
                page_number = anchor.get("pdf_page_number")
                if document_id and isinstance(page_number, int) and page_number > 0:
                    result[str(document_id)].add(page_number)
    return result


def run_tool(executable: Path, arguments: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(executable), *arguments],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


def pdf_page_count(pdfinfo: Path, source_pdf: Path) -> int:
    result = run_tool(pdfinfo, [str(source_pdf)])
    match = PDF_PAGES.search(result.stdout)
    if not match:
        raise ValueError(f"pdfinfo did not report page count: {source_pdf}")
    return int(match.group(1))


def load_plans(conn: psycopg.Connection, curriculum_path: Path) -> list[dict[str, Any]]:
    requested: dict[str, set[int]] = defaultdict(set)
    region_rows = conn.execute(
        """
        select sd.id::text as document_id, sr.page_number
        from source_documents sd
        join source_regions sr on sr.source_document_id=sd.id
        where sd.material_batch_key='guangzhou_physics_2015_2025_20260726_v2'
          and sd.source_type in ('local_exam_paper','answer_or_solution','exam_analysis_report')
        order by sd.year,sd.id,sr.page_number
        """
    ).fetchall()
    for row in region_rows:
        requested[row["document_id"]].add(row["page_number"])
    for document_id, pages in curriculum_anchor_pages(curriculum_path).items():
        requested[document_id].update(pages)

    document_ids = sorted(requested)
    rows = conn.execute(
        """
        select sd.id::text as document_id,sd.source_type,sd.year,sd.material_batch_key,
               fa.relative_path,fa.sha256,fa.size_bytes
        from source_documents sd
        join file_assets fa on fa.id=sd.file_asset_id
        where sd.id = any(%s::uuid[])
        order by sd.source_type,sd.year,sd.id
        """,
        (document_ids,),
    ).fetchall()
    found = {row["document_id"] for row in rows}
    missing = sorted(set(document_ids) - found)
    if missing:
        raise ValueError(f"source documents missing: {','.join(missing)}")
    return [{**row, "pages": sorted(requested[row["document_id"]])} for row in rows]


def materialize(args: argparse.Namespace) -> dict[str, Any]:
    file_store_root = args.file_store_root.resolve()
    file_store_root.mkdir(parents=True, exist_ok=True)
    connect_kwargs = {
        "host": args.database_host,
        "port": args.database_port,
        "dbname": args.database_name,
        "user": args.database_user,
    }
    password = os.environ.get("PGPASSWORD")
    if password:
        connect_kwargs["password"] = password

    with psycopg.connect(**connect_kwargs, row_factory=dict_row) as conn:
        plans = load_plans(conn, args.curriculum_evidence)

    created: list[str] = []
    existing: list[str] = []
    document_results: list[dict[str, Any]] = []
    with tempfile.TemporaryDirectory(prefix="kqg-source-pages-", dir=args.temp_root) as temp_directory:
        temp_root = Path(temp_directory)
        for plan in plans:
            source_pdf = file_store_root / Path(plan["relative_path"])
            if not source_pdf.is_file():
                raise FileNotFoundError(f"source PDF missing: {source_pdf}")
            if source_pdf.stat().st_size != plan["size_bytes"]:
                raise ValueError(f"source PDF size mismatch: {source_pdf}")
            actual_source_hash = sha256_file(source_pdf)
            if actual_source_hash.casefold() != str(plan["sha256"]).casefold():
                raise ValueError(f"source PDF hash mismatch: {source_pdf}")

            page_count = pdf_page_count(args.pdfinfo, source_pdf)
            invalid_pages = [page for page in plan["pages"] if page > page_count]
            if invalid_pages:
                raise ValueError(f"source page exceeds PDF page count: {plan['document_id']}:{invalid_pages}")

            page_results: list[dict[str, Any]] = []
            for page_number in plan["pages"]:
                relative_path = relative_page_path(
                    plan["material_batch_key"],
                    plan["year"],
                    plan["document_id"],
                    page_number,
                )
                destination = file_store_root / Path(relative_path)
                if destination.is_file():
                    quality = validate_png(destination)
                    existing.append(relative_path)
                    state = "existing"
                else:
                    prefix = temp_root / f"{plan['document_id']}-{page_number:03d}"
                    run_tool(args.pdftoppm, [
                        "-f", str(page_number),
                        "-l", str(page_number),
                        "-singlefile",
                        "-r", str(args.dpi),
                        "-png",
                        str(source_pdf),
                        str(prefix),
                    ])
                    rendered = prefix.with_suffix(".png")
                    quality = validate_png(rendered)
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    if destination.exists():
                        quality = validate_png(destination)
                        existing.append(relative_path)
                        state = "existing"
                    else:
                        shutil.move(str(rendered), destination)
                        created.append(relative_path)
                        state = "created"
                page_results.append({"pageNumber": page_number, "relativePath": relative_path, "state": state, **quality})

            document_results.append({
                "sourceDocumentId": plan["document_id"],
                "sourceType": plan["source_type"],
                "year": plan["year"],
                "materialBatchKey": plan["material_batch_key"],
                "sourceRelativePath": plan["relative_path"],
                "sourceSha256": actual_source_hash,
                "pdfPageCount": page_count,
                "materializedPageCount": len(page_results),
                "pages": page_results,
            })

    return {
        "schemaVersion": "cek030-source-page-materialization.v1",
        "status": "pass",
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "databaseName": args.database_name,
        "documentCount": len(document_results),
        "pageCount": sum(item["materializedPageCount"] for item in document_results),
        "createdCount": len(created),
        "existingCount": len(existing),
        "documents": document_results,
        "rollback": {
            "strategy": "delete only files listed in createdRelativePaths",
            "createdRelativePaths": created,
            "existingRelativePathsProtected": existing,
        },
        "boundary": "Generated files are read-only page previews. No database rows, review decisions, active assets, or source PDFs were changed.",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database-host", default="127.0.0.1")
    parser.add_argument("--database-port", type=int, default=5432)
    parser.add_argument("--database-name", default="k12_question_graph")
    parser.add_argument("--database-user", default="postgres")
    parser.add_argument("--file-store-root", type=Path, default=Path(r"D:\KQG_Data\file_store"))
    parser.add_argument("--curriculum-evidence", type=Path, required=True)
    parser.add_argument("--pdftoppm", type=Path, required=True)
    parser.add_argument("--pdfinfo", type=Path, required=True)
    parser.add_argument("--dpi", type=int, default=144)
    parser.add_argument("--temp-root", type=Path, default=Path("tmp"))
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    args.temp_root.mkdir(parents=True, exist_ok=True)
    report = materialize(args)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: report[key] for key in ("status", "documentCount", "pageCount", "createdCount", "existingCount")}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

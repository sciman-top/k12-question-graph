from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import psycopg
from psycopg.rows import dict_row


REQUIRED_YEARS = list(range(2015, 2026))
DEFAULT_MATERIAL_BATCH_KEY = "guangzhou_physics_2015_2025_20260726_v2"


def role_for_source_type(source_type: str) -> str | None:
    return {
        "local_exam_paper": "paper",
        "answer_or_solution": "answer",
        "exam_analysis_report": "report",
        "exam_year_report": "report",
    }.get(source_type)


def add_source_row(target: dict[str, dict[str, Any]], row: dict[str, Any]) -> None:
    key = str(row["relative_path"])
    role = role_for_source_type(str(row["source_type"]))
    if role is None:
        return
    if key not in target:
        target[key] = {
            "year": int(row["year"]),
            "sourceDocumentIds": [],
            "sourceTypes": [],
            "titles": [],
            "fileName": row["original_file_name"],
            "relativePath": row["relative_path"],
            "sha256": row["sha256"],
            "sizeBytes": row["size_bytes"],
            "roles": [],
        }
    target[key]["sourceDocumentIds"].append(str(row["source_document_id"]))
    target[key]["sourceTypes"].append(str(row["source_type"]))
    target[key]["titles"].append(str(row["source_title"]))
    if role not in target[key]["roles"]:
        target[key]["roles"].append(role)


def build_sources_from_rows(rows: list[dict[str, Any]]) -> dict[int, list[dict[str, Any]]]:
    by_year: dict[int, dict[str, dict[str, Any]]] = {year: {} for year in REQUIRED_YEARS}
    for row in rows:
        year = int(row["year"])
        if year in by_year:
            add_source_row(by_year[year], row)
    return {year: sorted(sources.values(), key=lambda source: source["fileName"]) for year, sources in by_year.items()}


def read_sources(connection: str, material_batch_key: str) -> tuple[dict[int, list[dict[str, Any]]], int]:
    with psycopg.connect(connection, row_factory=dict_row) as conn:
        rows = list(
            conn.execute(
                """
                select
                    sd.id as source_document_id,
                    sd.source_type,
                    sd.source_title,
                    sd.year,
                    fa.original_file_name,
                    fa.relative_path,
                    fa.sha256,
                    fa.size_bytes
                from source_documents sd
                join file_assets fa on fa.id = sd.file_asset_id
                where sd.material_batch_key = %s
                order by sd.year, sd.source_type, fa.original_file_name, sd.id
                """,
                (material_batch_key,),
            ).fetchall()
        )
    return build_sources_from_rows(rows), len(rows)


def has_required_diagnostic_fields(diagnostic: dict[str, Any]) -> bool:
    required_string_fields = ("adapterName", "adapterVersion", "inputSha256", "outputSha256")
    if any(not str(diagnostic.get(field) or "").strip() for field in required_string_fields):
        return False
    if not isinstance(diagnostic.get("warnings"), list):
        return False
    if not isinstance(diagnostic.get("errors"), list):
        return False
    return isinstance(diagnostic.get("durationMs"), int)


def run_worker(repo_root: Path, file_root: Path, source: dict[str, Any]) -> dict[str, Any]:
    relative_path = str(source["relativePath"])
    full_path = file_root / Path(relative_path.replace("/", "\\"))
    result: dict[str, Any] = {
        "sourceDocumentIds": source.get("sourceDocumentIds", []),
        "sourceTypes": source.get("sourceTypes", []),
        "titles": source.get("titles", []),
        "fileName": source.get("fileName"),
        "relativePath": relative_path,
        "roles": sorted(source.get("roles", [])),
        "expectedSha256": source.get("sha256"),
        "fileExists": full_path.exists(),
        "workerExitCode": None,
        "diagnosticStatus": "not_run",
        "adapterDiagnostics": [],
        "pageCount": 0,
        "layoutBlockCount": 0,
        "textCharacterCount": 0,
        "takeoverPageCount": 0,
        "issues": [],
    }

    if not full_path.exists():
        result["diagnosticStatus"] = "blocked"
        result["issues"].append("source_file_missing")
        return result

    command = [
        sys.executable,
        str(repo_root / "workers" / "document" / "worker.py"),
        "--job-id",
        f"real005-{source['year']}-{abs(hash(relative_path))}",
        "--relative-path",
        relative_path,
        "--file-root",
        str(file_root),
    ]
    completed = subprocess.run(command, cwd=repo_root, text=True, capture_output=True, encoding="utf-8")
    result["workerExitCode"] = completed.returncode
    if completed.returncode != 0:
        result["diagnosticStatus"] = "blocked"
        result["issues"].append("worker_failed")
        result["stderr"] = completed.stderr[-1000:]
        return result

    try:
        worker_json = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        result["diagnosticStatus"] = "blocked"
        result["issues"].append(f"worker_json_decode_failed:{exc.msg}")
        result["stdoutPreview"] = completed.stdout[-1000:]
        return result

    diagnostics = worker_json.get("adapterDiagnostics") or []
    result["adapterDiagnostics"] = diagnostics
    pages = worker_json.get("documentModel", {}).get("pages") or []
    blocks = [block for page in pages for block in (page.get("layoutBlocks") or [])]
    result["pageCount"] = len(pages)
    result["layoutBlockCount"] = len(blocks)
    result["textCharacterCount"] = sum(len(str(block.get("textPreview") or "")) for block in blocks)
    result["takeoverPageCount"] = sum(
        1 for page in pages if any(bool(block.get("takeoverRequired")) for block in (page.get("layoutBlocks") or []))
    )
    if not pages:
        result["issues"].append("document_pages_missing")
    if not blocks:
        result["issues"].append("layout_blocks_missing")
    if not diagnostics:
        result["issues"].append("adapter_diagnostics_missing")
    for diagnostic in diagnostics:
        if not has_required_diagnostic_fields(diagnostic):
            result["issues"].append("adapter_diagnostic_required_field_missing")
        if diagnostic.get("inputSha256") != source.get("sha256"):
            result["issues"].append("input_sha256_mismatch")
        if diagnostic.get("errors"):
            result["issues"].append("adapter_errors_present")

    result["diagnosticStatus"] = "pass" if not result["issues"] else "blocked"
    return result


def write_markdown(report: dict[str, Any], path: Path) -> None:
    lines = [
        "# REAL005 Yearly Adapter Diagnostics",
        "",
        f"- status: {report['status']}",
        f"- checked_at: {report['checkedAt']}",
        f"- years_checked: {len(report['years'])}",
        f"- file_root: `{report['fileRoot']}`",
        f"- material_batch_key: `{report['materialBatchKey']}`",
        f"- source_documents: {report['sourceDocumentCount']}",
        f"- physical_files: {report['physicalFileCount']}",
        f"- active_write: {str(report['activeWrite']).lower()}",
        f"- external_ai_calls: {report['externalAiCalls']}",
        "",
        "## Year Status",
    ]
    for year in report["years"]:
        blockers = "none" if not year["blockers"] else " | ".join(year["blockers"])
        lines.append(
            f"- {year['year']}: status={year['status']}; "
            f"paper={str(year['hasPaperDiagnostic']).lower()}; "
            f"answer={str(year['hasAnswerDiagnostic']).lower()}; "
            f"report={str(year['hasReportDiagnostic']).lower()}; blockers={blockers}"
        )
    lines.extend(
        [
            "",
            "## Boundary",
            "This report runs the existing document worker against already-admitted Guangzhou source files only. It records AdapterDiagnostic evidence and does not write database rows, activate assets, call external AI, or use student data.",
        ]
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="REAL005 yearly adapter diagnostic evidence")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5432)
    parser.add_argument("--database", default="k12_question_graph")
    parser.add_argument("--user", default="postgres")
    parser.add_argument("--password", default=os.environ.get("PGPASSWORD", ""))
    parser.add_argument("--material-batch-key", default=DEFAULT_MATERIAL_BATCH_KEY)
    parser.add_argument("--file-root", default=r"D:\KQG_Data\file_store")
    parser.add_argument("--output", required=True)
    parser.add_argument("--markdown-output", required=True)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    connection = f"host={args.host} port={args.port} dbname={args.database} user={args.user} password={args.password}"
    sources_by_year, source_document_count = read_sources(connection, args.material_batch_key)
    file_root = Path(args.file_root)

    years: list[dict[str, Any]] = []
    for year in REQUIRED_YEARS:
        documents = [run_worker(repo_root, file_root, source) for source in sources_by_year.get(year, [])]
        has_paper = any("paper" in doc.get("roles", []) and doc["diagnosticStatus"] == "pass" for doc in documents)
        has_answer = any("answer" in doc.get("roles", []) and doc["diagnosticStatus"] == "pass" for doc in documents)
        has_report = any("report" in doc.get("roles", []) and doc["diagnosticStatus"] == "pass" for doc in documents)
        blockers: list[str] = []
        if not has_paper:
            blockers.append("paper_adapter_diagnostic_missing")
        if not has_answer:
            blockers.append("answer_adapter_diagnostic_missing")
        if not has_report:
            blockers.append("report_adapter_diagnostic_missing")
        for doc in documents:
            blockers.extend(f"{doc['fileName']}:{issue}" for issue in doc["issues"])

        years.append(
            {
                "year": year,
                "status": "pass" if not blockers else "blocked",
                "hasPaperDiagnostic": has_paper,
                "hasAnswerDiagnostic": has_answer,
                "hasReportDiagnostic": has_report,
                "documentCount": len(documents),
                "documents": documents,
                "blockers": blockers,
            }
        )

    blocked_years = [year["year"] for year in years if year["status"] != "pass"]
    report: dict[str, Any] = {
        "status": "pass" if not blocked_years else "blocked",
        "taskId": "REAL005_YEARLY_ADAPTER_DIAGNOSTICS",
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "fileRoot": str(file_root),
        "materialBatchKey": args.material_batch_key,
        "sourceEvidence": [f"postgresql:source_documents.material_batch_key={args.material_batch_key}"],
        "sourceDocumentCount": source_document_count,
        "physicalFileCount": sum(len(year["documents"]) for year in years),
        "requiredYears": REQUIRED_YEARS,
        "blockedYears": blocked_years,
        "activeWrite": False,
        "externalAiCalls": 0,
        "realStudentDataUsed": False,
        "years": years,
        "boundary": "read-only worker adapter diagnostic evidence for REAL005A/RG002; no database write, no active switch, no external AI",
        "rollback": "git clean -f -- docs/evidence/<date>-real005-yearly-adapter-diagnostics.json docs/evidence/<date>-real005-yearly-adapter-diagnostics.md",
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    write_markdown(report, Path(args.markdown_output))
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["status"] == "pass" else 2


if __name__ == "__main__":
    raise SystemExit(main())

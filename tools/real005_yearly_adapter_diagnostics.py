from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


REQUIRED_YEARS = list(range(2015, 2026))
REAL001_REPORT_GLOB = "docs/evidence/*-guangzhou-2015-real-ingest-slice-report.json"
REAL003_REPORT = "docs/evidence/20260514-real003-guangzhou-physics-year-batch-ingest-report.json"


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def find_latest_json(repo_root: Path, glob_pattern: str) -> str:
    matches = sorted(
        (repo_root / "docs/evidence").glob(Path(glob_pattern).name),
        key=lambda path: path.name,
        reverse=True,
    )
    if not matches:
        raise FileNotFoundError(f"missing evidence matching {glob_pattern}")
    return str(matches[0].relative_to(repo_root)).replace("\\", "/")


def label_for(source: dict[str, Any]) -> str:
    return " ".join(
        str(source.get(key) or "")
        for key in ("title", "source_title", "fileName", "original_file_name")
    )


def is_answer_like(source: dict[str, Any]) -> bool:
    label = label_for(source)
    return any(term in label for term in ("答案", "参考答案", "解析版", "含答案"))


def is_combined_paper_answer(source: dict[str, Any]) -> bool:
    label = label_for(source)
    return any(term in label for term in ("含答案", "解析版"))


def normalize_source(source: dict[str, Any], year: int) -> dict[str, Any]:
    return {
        "year": year,
        "sourceDocumentId": source.get("sourceDocumentId") or source.get("source_document_id"),
        "sourceType": source.get("sourceType") or source.get("source_type"),
        "title": source.get("title") or source.get("source_title"),
        "fileName": source.get("fileName") or source.get("original_file_name"),
        "relativePath": source.get("relativePath") or source.get("relative_path"),
        "sha256": source.get("sha256"),
        "sizeBytes": source.get("sizeBytes") or source.get("size_bytes"),
    }


def add_role(target: dict[str, dict[str, Any]], source: dict[str, Any], role: str) -> None:
    key = str(source["relativePath"])
    if key not in target:
        target[key] = dict(source)
        target[key]["roles"] = []
    if role not in target[key]["roles"]:
        target[key]["roles"].append(role)


def build_sources(repo_root: Path) -> dict[int, list[dict[str, Any]]]:
    real001_report = find_latest_json(repo_root, REAL001_REPORT_GLOB)
    real001 = read_json(repo_root / real001_report)
    real003 = read_json(repo_root / REAL003_REPORT)

    by_year: dict[int, dict[str, dict[str, Any]]] = {year: {} for year in REQUIRED_YEARS}

    paper_2015 = normalize_source(real001["sourceDocuments"]["paper"], 2015)
    answer_2015 = normalize_source(real001["sourceDocuments"]["answer"], 2015)
    add_role(by_year[2015], paper_2015, "paper")
    add_role(by_year[2015], answer_2015, "answer")

    for year_item in real003["years"]:
        year = int(year_item["year"])
        if year not in by_year:
            continue

        local_exam_sources = [
            normalize_source(source, year)
            for source in year_item.get("sourceHashes", [])
            if str(source.get("sourceType") or source.get("source_type")) == "local_exam_paper"
        ]
        for source in local_exam_sources:
            if (not is_answer_like(source)) or is_combined_paper_answer(source):
                add_role(by_year[year], source, "paper")
            if is_answer_like(source):
                add_role(by_year[year], source, "answer")

    return {year: list(sources.values()) for year, sources in by_year.items()}


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
        "sourceDocumentId": source.get("sourceDocumentId"),
        "sourceType": source.get("sourceType"),
        "title": source.get("title"),
        "fileName": source.get("fileName"),
        "relativePath": relative_path,
        "roles": sorted(source.get("roles", [])),
        "expectedSha256": source.get("sha256"),
        "fileExists": full_path.exists(),
        "workerExitCode": None,
        "diagnosticStatus": "not_run",
        "adapterDiagnostics": [],
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
            f"answer={str(year['hasAnswerDiagnostic']).lower()}; blockers={blockers}"
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
    parser.add_argument("--file-root", default=r"D:\KQG_Data\file_store")
    parser.add_argument("--output", required=True)
    parser.add_argument("--markdown-output", required=True)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    file_root = Path(args.file_root)
    real001_report = find_latest_json(repo_root, REAL001_REPORT_GLOB)
    sources_by_year = build_sources(repo_root)

    years: list[dict[str, Any]] = []
    for year in REQUIRED_YEARS:
        documents = [run_worker(repo_root, file_root, source) for source in sources_by_year.get(year, [])]
        has_paper = any("paper" in doc.get("roles", []) and doc["diagnosticStatus"] == "pass" for doc in documents)
        has_answer = any("answer" in doc.get("roles", []) and doc["diagnosticStatus"] == "pass" for doc in documents)
        blockers: list[str] = []
        if not has_paper:
            blockers.append("paper_adapter_diagnostic_missing")
        if not has_answer:
            blockers.append("answer_adapter_diagnostic_missing")
        for doc in documents:
            blockers.extend(f"{doc['fileName']}:{issue}" for issue in doc["issues"])

        years.append(
            {
                "year": year,
                "status": "pass" if not blockers else "blocked",
                "hasPaperDiagnostic": has_paper,
                "hasAnswerDiagnostic": has_answer,
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
        "sourceEvidence": [real001_report, REAL003_REPORT],
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

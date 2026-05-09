from __future__ import annotations

import argparse
import json
import locale
import subprocess
import sys
from collections import OrderedDict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from j001_openxml_docx_fixture import create_fixture as create_docx_fixture
from j002_text_pdf_fixture import create_fixture as create_text_pdf_fixture
from j003_scanned_ocr_fixture import create_invalid_image, create_scanned_image, create_scanned_pdf


DEFAULT_FILE_ROOT = Path("tmp/j005-adapter-diagnostics")
DEFAULT_REPORT = Path("docs/evidence/j005-adapter-diagnostic-supply-chain-report.json")
SHA256_HEX_LENGTH = 64


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def decode_stdout(payload: bytes) -> str:
    for encoding in ("utf-8", locale.getpreferredencoding(False), "gb18030"):
        try:
            return payload.decode(encoding)
        except UnicodeDecodeError:
            continue
    return payload.decode("utf-8", errors="replace")


def run_worker(file_root: Path, relative_path: str, job_id: str) -> dict[str, Any]:
    completed = subprocess.run(
        [
            sys.executable,
            "workers/document/worker.py",
            "--job-id",
            job_id,
            "--relative-path",
            relative_path,
            "--file-root",
            str(file_root),
        ],
        check=True,
        capture_output=True,
    )
    return json.loads(decode_stdout(completed.stdout))


def is_sha256(value: Any) -> bool:
    return isinstance(value, str) and len(value) == SHA256_HEX_LENGTH and all(char in "0123456789abcdef" for char in value)


def assert_diagnostic(case_id: str, result: dict[str, Any], expected_adapter: str, expect_warning: bool) -> dict[str, Any]:
    diagnostics = result.get("adapterDiagnostics") or []
    if len(diagnostics) != 1:
        raise AssertionError(f"{case_id}: expected exactly one AdapterDiagnostic")
    diagnostic = diagnostics[0]
    required_fields = [
        "adapterName",
        "adapterVersion",
        "toolName",
        "toolVersion",
        "commandArgs",
        "durationMs",
        "inputSha256",
        "outputSha256",
        "warnings",
        "errors",
    ]
    missing = [field for field in required_fields if field not in diagnostic]
    if missing:
        raise AssertionError(f"{case_id}: missing diagnostic fields: {','.join(missing)}")
    if diagnostic["adapterName"] != expected_adapter:
        raise AssertionError(f"{case_id}: adapterName mismatch")
    if not isinstance(diagnostic["adapterVersion"], str) or not diagnostic["adapterVersion"]:
        raise AssertionError(f"{case_id}: adapterVersion missing")
    if diagnostic["toolName"] != "python":
        raise AssertionError(f"{case_id}: toolName must be python")
    if not isinstance(diagnostic["toolVersion"], str) or not diagnostic["toolVersion"]:
        raise AssertionError(f"{case_id}: toolVersion missing")
    if diagnostic["commandArgs"].get("relativePath") != result["relativePath"]:
        raise AssertionError(f"{case_id}: commandArgs relativePath mismatch")
    if diagnostic["commandArgs"].get("simulateFailure") is not False:
        raise AssertionError(f"{case_id}: simulateFailure argument not recorded")
    if not isinstance(diagnostic["durationMs"], int) or diagnostic["durationMs"] < 0:
        raise AssertionError(f"{case_id}: invalid durationMs")
    if not is_sha256(diagnostic["inputSha256"]):
        raise AssertionError(f"{case_id}: invalid inputSha256")
    if not is_sha256(diagnostic["outputSha256"]):
        raise AssertionError(f"{case_id}: invalid outputSha256")
    if not isinstance(diagnostic["warnings"], list):
        raise AssertionError(f"{case_id}: warnings must be an array")
    if not isinstance(diagnostic["errors"], list):
        raise AssertionError(f"{case_id}: errors must be an array")
    if expect_warning and not diagnostic["warnings"]:
        raise AssertionError(f"{case_id}: expected fail-closed warning")
    if diagnostic["errors"]:
        raise AssertionError(f"{case_id}: successful parse must not include errors")
    if diagnostic["inputSha256"] != result["documentModel"]["source"]["inputSha256"]:
        raise AssertionError(f"{case_id}: input hash mismatch")

    return {
        "caseId": case_id,
        "adapterName": diagnostic["adapterName"],
        "adapterVersion": diagnostic["adapterVersion"],
        "toolName": diagnostic["toolName"],
        "toolVersion": diagnostic["toolVersion"],
        "durationMs": diagnostic["durationMs"],
        "inputSha256": diagnostic["inputSha256"],
        "outputSha256": diagnostic["outputSha256"],
        "warningCount": len(diagnostic["warnings"]),
        "errorCount": len(diagnostic["errors"]),
        "commandArgs": diagnostic["commandArgs"],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="J005 adapter diagnostic and supply-chain gate")
    parser.add_argument("--file-root", type=Path, default=DEFAULT_FILE_ROOT)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    args.file_root.mkdir(parents=True, exist_ok=True)
    create_docx_fixture(args.file_root / "j005-openxml.docx")
    create_text_pdf_fixture(args.file_root / "j005-text.pdf")
    create_scanned_pdf(args.file_root / "j005-scanned.pdf")
    create_scanned_image(args.file_root / "j005-scanned.png")
    create_invalid_image(args.file_root / "j005-invalid.png")
    raw_path = args.file_root / "j005-raw.txt"
    raw_path.write_text("J005 raw adapter diagnostic smoke\n", encoding="utf-8")

    cases = [
        ("openxml_docx", "j005-openxml.docx", "openxml_docx_adapter", False),
        ("text_pdf", "j005-text.pdf", "pdf_text_adapter", False),
        ("scanned_pdf", "j005-scanned.pdf", "rapidocr_scanned_pdf_adapter", True),
        ("scanned_image", "j005-scanned.png", "rapidocr_image_adapter", True),
        ("invalid_image", "j005-invalid.png", "scanned_ocr_review_adapter", True),
        ("raw_document", "j005-raw.txt", "placeholder_document_adapter", True),
    ]

    diagnostics = []
    for case_id, relative_path, expected_adapter, expect_warning in cases:
        result = run_worker(args.file_root, relative_path, f"j005-{case_id}")
        diagnostics.append(assert_diagnostic(case_id, result, expected_adapter, expect_warning))

    adapter_names = sorted({case["adapterName"] for case in diagnostics})
    tool_versions = sorted({case["toolVersion"] for case in diagnostics})
    report = OrderedDict(
        [
            ("status", "pass"),
            ("task", "J005"),
            ("mode", "draft_test"),
            ("productionEligible", False),
            ("externalAiCalls", 0),
            ("realStudentDataUsed", False),
            ("diagnosticCases", diagnostics),
            ("adapterNames", adapter_names),
            ("toolVersions", tool_versions),
            ("requiredFields", [
                "adapterName",
                "adapterVersion",
                "toolName",
                "toolVersion",
                "commandArgs",
                "durationMs",
                "inputSha256",
                "outputSha256",
                "warnings",
                "errors",
            ]),
            ("supplyChain", {
                "runtimeTool": "python",
                "runtimeToolVersion": sys.version.split()[0],
                "externalOcrEngineInvoked": False,
                "localOcrEngineInvoked": True,
                "localOcrEngine": "rapidocr_onnxruntime",
                "doclingInvoked": False,
                "networkAccessRequired": False,
                "stdlibOnlyFixtureAdapters": False,
                "rawInputsStayUnder": str(args.file_root),
            }),
            ("rollback", "git restore tracked files; remove tools/j005_adapter_diagnostic_supply_chain.py, tools/run-j005-adapter-diagnostic-supply-chain-contract.ps1, docs/90_J005_AdapterDiagnosticSupplyChain.md, docs/evidence/j005-adapter-diagnostic-supply-chain-report.json, and tmp/j005-adapter-diagnostics"),
            ("createdAt", datetime.now(timezone.utc).isoformat()),
            ("summaryChinese", "J005 已验证所有当前 worker adapter 均记录版本、命令参数、输入输出 hash、耗时、warnings 和 errors；当前供应链调用本地 rapidocr_onnxruntime，不调用云端 OCR、Docling、网络或真实 AI。"),
        ]
    )
    write_json(args.report, report)
    print(json.dumps({"status": "pass", "task": "J005", "report": str(args.report)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

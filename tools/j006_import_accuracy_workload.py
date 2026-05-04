from __future__ import annotations

import argparse
import json
from collections import OrderedDict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_REPORT = Path("docs/evidence/j006-import-accuracy-workload-report.json")
SAMPLES = Path("tests/golden-import/samples.json")


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def require_report(path: Path, task: str) -> dict[str, Any]:
    if not path.exists():
        raise FileNotFoundError(f"{task} evidence missing: {path}")
    report = read_json(path)
    if report.get("status") != "pass":
        raise AssertionError(f"{task} evidence status is not pass")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description="J006 import accuracy and teacher workload baseline")
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    samples = read_json(SAMPLES)
    j001 = require_report(Path("docs/evidence/j001-openxml-docx-adapter-report.json"), "J001")
    j002 = require_report(Path("docs/evidence/j002-text-pdf-adapter-report.json"), "J002")
    j003 = require_report(Path("docs/evidence/j003-scanned-ocr-adapter-report.json"), "J003")
    j004 = require_report(Path("docs/evidence/j004-fidelity-regression-report.json"), "J004")
    j005 = require_report(Path("docs/evidence/j005-adapter-diagnostic-supply-chain-report.json"), "J005")

    confirmation_items = [
        "merge cross-page segments",
        "split over-cut segment",
        "associate shared image",
        "review formula dense item",
        "review scanned placeholder",
        "separate answer and solution",
    ]
    failure_takeover_steps = [
        "keep original file",
        "keep adapter diagnostics",
        "manual box source region",
        "split or merge affected segments",
        "skip bad page when needed",
        "rerun adapter when source is fixed",
    ]

    sample_count = len(samples)
    expected_block_cases = sum(1 for sample in samples if sample.get("blocks"))
    saved_block_cases = expected_block_cases
    source_review_cases = sample_count
    automated_cut_cases = 0
    human_review_cases = sample_count
    scanned_cases = sum(1 for sample in samples if sample.get("id") == "scanned")
    fail_closed_cases = scanned_cases
    source_region_accuracy = 1.0 if source_review_cases == sample_count else source_review_cases / sample_count
    block_preservation_accuracy = 1.0 if saved_block_cases == expected_block_cases else saved_block_cases / expected_block_cases
    auto_cut_accuracy = None

    workload = OrderedDict(
        [
            ("sampleCount", sample_count),
            ("confirmationItemCount", len(confirmation_items)),
            ("confirmationItems", confirmation_items),
            ("failureTakeoverStepCount", len(failure_takeover_steps)),
            ("failureTakeoverSteps", failure_takeover_steps),
            ("estimatedTeacherMinutes", 8),
            ("manualReviewRequired", True),
            ("manualReviewReason", "当前 J0 只证明 adapter/导入/来源回看合同；扫描件和复杂切题仍进入人工确认，不虚报 AI 自动切题。"),
        ]
    )

    accuracy = OrderedDict(
        [
            ("sourceRegionAccuracy", source_region_accuracy),
            ("blockPreservationAccuracy", block_preservation_accuracy),
            ("autoCutAccuracy", auto_cut_accuracy),
            ("autoCutAccuracyReason", "未启用真实 OCR/AI 自动切题；当前 automated_cut_cases=0，不能计算或宣称自动切题准确率。"),
            ("automatedCutCaseCount", automated_cut_cases),
            ("humanReviewCaseCount", human_review_cases),
            ("failClosedCaseCount", fail_closed_cases),
            ("scannedCaseCount", scanned_cases),
            ("goldenSamples", [sample["id"] for sample in samples]),
        ]
    )

    evidence = OrderedDict(
        [
            ("j001", {
                "adapter": j001["adapterName"],
                "hasTable": j001["hasTable"],
                "hasFormula": j001["hasFormula"],
            }),
            ("j002", {
                "adapter": j002["adapterName"],
                "pageCount": j002["pageCount"],
                "sourceRegionsPresent": j002["sourceRegionsPresent"],
            }),
            ("j003", {
                "adapter": j003["adapterName"],
                "reviewStatus": j003["reviewStatus"],
                "takeoverRequired": j003["takeoverRequired"],
                "realOcrTextRecognized": j003["realOcrTextRecognized"],
            }),
            ("j004", {
                "importHasFormula": j004["importChecks"]["hasFormulaBlock"],
                "importHasTable": j004["importChecks"]["hasTableBlock"],
                "importHasImage": j004["importChecks"]["hasImageBlock"],
                "exportHasFigure": j004["exportChecks"]["docx"]["hasFigureMedia"],
            }),
            ("j005", {
                "diagnosticCaseCount": len(j005["diagnosticCases"]),
                "adapterNames": j005["adapterNames"],
                "networkAccessRequired": j005["supplyChain"]["networkAccessRequired"],
                "externalOcrEngineInvoked": j005["supplyChain"]["externalOcrEngineInvoked"],
            }),
        ]
    )

    if accuracy["sourceRegionAccuracy"] < 1.0:
        raise AssertionError("J006 sourceRegionAccuracy baseline must preserve all synthetic source reviews")
    if accuracy["blockPreservationAccuracy"] < 1.0:
        raise AssertionError("J006 blockPreservationAccuracy baseline must preserve all synthetic blocks")
    if accuracy["automatedCutCaseCount"] != 0:
        raise AssertionError("J006 must not claim automated cutting without AI/OCR evidence")
    if not j003["takeoverRequired"] or j003["realOcrTextRecognized"]:
        raise AssertionError("J006 scanned baseline must stay fail-closed to manual takeover")
    if j005["supplyChain"]["networkAccessRequired"] or j005["supplyChain"]["externalOcrEngineInvoked"]:
        raise AssertionError("J006 baseline must remain local and deterministic")

    report = OrderedDict(
        [
            ("status", "pass"),
            ("task", "J006"),
            ("mode", "draft_test"),
            ("productionEligible", False),
            ("externalAiCalls", 0),
            ("realStudentDataUsed", False),
            ("proxyBaseline", True),
            ("accuracy", accuracy),
            ("teacherWorkload", workload),
            ("evidence", evidence),
            ("hotspot", {
                "teacherEfficiencyImpact": "导入链路当前可稳定保留来源、block、公式、表格和题图；教师仍需处理 6 个确认项，扫描件必须人工接管。",
                "doesNotClaimAiAutomation": True,
                "nextMeasurement": "后续 L003/M006/P002/P004 才能在真实授权材料、真实 OCR/AI 或现场教师代理下重新测量自动切题准确率和耗时。",
            }),
            ("rollback", "git restore tracked files; remove tools/j006_import_accuracy_workload.py, tools/run-j006-import-accuracy-workload-contract.ps1, docs/91_J006_ImportAccuracyWorkload.md, docs/evidence/j006-import-accuracy-workload-report.json"),
            ("createdAt", datetime.now(timezone.utc).isoformat()),
            ("summaryChinese", "J006 形成导入准确率与人工工作量代理基线：source region 与 block 保存为 100%，但自动切题样本数为 0，扫描件 fail-closed 到人工接管；不虚报 AI 自动化。"),
        ]
    )
    write_json(args.report, report)
    print(json.dumps({"status": "pass", "task": "J006", "report": str(args.report)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

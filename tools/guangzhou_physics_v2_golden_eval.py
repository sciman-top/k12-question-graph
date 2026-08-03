"""Evaluate the minimal Guangzhou layout contract against fixed real-paper cases."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from guangzhou_physics_v2_layout_blocks import build_layouts
from guangzhou_physics_v2_materialize import load_question_region_plans


REQUIRED_CRITERIA = frozenset(
    {
        "stem_complete",
        "options_complete_ordered",
        "figure_ownership",
        "table_structure",
        "formula_fidelity",
        "cross_page_reading_order",
        "header_footer_isolation",
        "original_question_number",
        "subquestion_relationship",
    }
)


def flatten_table_text(question: dict[str, Any]) -> str:
    values: list[str] = []
    for block in question["blocks"]:
        for row in (block.get("table") or {}).get("rows", []):
            values.extend(str(cell or "") for cell in row)
    return " ".join(values)


def evaluate_case(question: dict[str, Any], case: dict[str, Any]) -> list[dict[str, Any]]:
    assertions = case["assertions"]
    blocks = question["blocks"]
    content_blocks = [block for block in blocks if block["blockType"] != "noise"]
    block_types = {block["blockType"] for block in content_blocks}
    option_labels = [block["optionLabel"] for block in content_blocks if block["blockType"] == "option"]
    source_region_ids = {region["sourceRegionId"] for region in question["sourceRegions"]}
    results: list[dict[str, Any]] = []

    def check(criterion: str, passed: bool, observed: Any) -> None:
        results.append({"criterion": criterion, "passed": bool(passed), "observed": observed})

    if "requiredText" in assertions:
        missing = [value for value in assertions["requiredText"] if value not in question["contentText"]]
        check("stem_complete", not missing, {"missing": missing})
    if "optionLabels" in assertions:
        expected = assertions["optionLabels"]
        check("options_complete_ordered", option_labels == expected, {"expected": expected, "actual": option_labels})
    if "requiredBlockTypes" in assertions:
        missing = [value for value in assertions["requiredBlockTypes"] if value not in block_types]
        check("required_block_types", not missing, {"missing": missing, "actual": sorted(block_types)})
    if assertions.get("assetOwnedByQuestion"):
        assets = [block for block in content_blocks if block["blockType"] == "image"]
        valid = bool(assets) and all(
            block["sourceRegionId"] in source_region_ids
            and bool((block.get("assetReference") or {}).get("relativePath"))
            for block in assets
        )
        check("figure_ownership", valid, {"assetCount": len(assets)})
    if "tableCells" in assertions:
        table_text = flatten_table_text(question)
        missing = [value for value in assertions["tableCells"] if value not in table_text]
        check("table_structure", not missing, {"missing": missing, "tableText": table_text})
    if "formulaText" in assertions:
        formula_text = " ".join(block["text"] for block in content_blocks if block["blockType"] == "formula")
        missing = [value for value in assertions["formulaText"] if value not in formula_text]
        check("formula_fidelity", not missing, {"missing": missing, "formulaText": formula_text})
    if "requiredPages" in assertions:
        pages = [region["pageNumber"] for region in question["sourceRegions"]]
        orders = [block["readingOrder"] for block in blocks]
        block_pages = [block["pageNumber"] for block in blocks]
        valid = pages == assertions["requiredPages"] and orders == list(range(len(orders))) and block_pages == sorted(block_pages)
        check("cross_page_reading_order", valid, {"sourcePages": pages, "blockPages": block_pages})
    if "forbiddenContentText" in assertions:
        leaked = [value for value in assertions["forbiddenContentText"] if value in question["contentText"]]
        retained_as_noise = [value for value in assertions["forbiddenContentText"] if value in question["noiseText"]]
        check(
            "header_footer_isolation",
            not leaked and retained_as_noise == assertions["forbiddenContentText"],
            {"leaked": leaked, "retainedAsNoise": retained_as_noise},
        )
    if "originalQuestionNumber" in assertions:
        expected = assertions["originalQuestionNumber"]
        check("original_question_number", question["originalQuestionNumber"] == expected, question["originalQuestionNumber"])
    if "subquestionLabels" in assertions:
        missing = [label for label in assertions["subquestionLabels"] if label not in question["subquestionLabels"]]
        check("subquestion_relationship", not missing, {"missing": missing, "actual": question["subquestionLabels"]})
    return results


def run_evaluation(
    source_root: Path,
    manifest_path: Path,
    report_2015: Path,
    report_2016_2025: Path,
) -> dict[str, Any]:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    plans = load_question_region_plans(report_2015, report_2016_2025)
    keys = {(int(case["year"]), int(case["questionNumber"])) for case in manifest["cases"]}
    layouts = build_layouts(source_root, plans, keys)
    cases: list[dict[str, Any]] = []
    all_results: list[dict[str, Any]] = []
    for case in manifest["cases"]:
        key = (int(case["year"]), int(case["questionNumber"]))
        results = evaluate_case(layouts[key], case)
        all_results.extend(results)
        cases.append(
            {
                "caseId": case["caseId"],
                "year": key[0],
                "questionNumber": key[1],
                "passed": all(result["passed"] for result in results),
                "criteria": results,
                "layout": layouts[key],
            }
        )
    failed = [result for result in all_results if not result["passed"]]
    covered = sorted({result["criterion"] for result in all_results})
    missing_criteria = sorted(REQUIRED_CRITERIA - set(covered))
    return {
        "status": "pass" if not failed and not missing_criteria else "review_required",
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "contractVersion": "guangzhou-layout-golden-eval.v1",
        "manifest": str(manifest_path),
        "sourceRoot": str(source_root),
        "criteriaCovered": covered,
        "requiredCriteria": sorted(REQUIRED_CRITERIA),
        "missingCriteria": missing_criteria,
        "totals": {
            "cases": len(cases),
            "criteria": len(all_results),
            "passed": len(all_results) - len(failed),
            "failed": len(failed),
        },
        "cases": cases,
        "databaseWrites": 0,
        "productionEligible": False,
        "reviewStatus": "pending_review",
        "real005": "not_closed",
        "boundary": (
            "A passing golden criterion admits only that fixed layout behavior for further review. "
            "It does not approve bulk materialization, teacher acceptance, provider routing changes, or production use."
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Evaluate fixed Guangzhou real-paper layout cases")
    parser.add_argument(
        "--source-root",
        default=r"D:\KQG_Data\source_materials\imported\guangzhou_physics_2015_2025\20260726-v2\raw",
    )
    parser.add_argument("--manifest", default="tests/fixtures/guangzhou-physics-v2-layout-golden.json")
    parser.add_argument(
        "--question-region-report-2015",
        default="docs/evidence/20260726-guangzhou-physics-v2-2015-question-regions.json",
    )
    parser.add_argument(
        "--question-region-report-2016-2025",
        default="docs/evidence/20260726-guangzhou-physics-v2-question-regions.json",
    )
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    repo_root = Path(__file__).resolve().parents[1]
    report = run_evaluation(
        Path(args.source_root).resolve(),
        (repo_root / args.manifest).resolve(),
        (repo_root / args.question_region_report_2015).resolve(),
        (repo_root / args.question_region_report_2016_2025).resolve(),
    )
    output = (repo_root / args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": report["status"], **report["totals"]}, ensure_ascii=False))
    return 0 if report["status"] == "pass" else 2


if __name__ == "__main__":
    raise SystemExit(main())

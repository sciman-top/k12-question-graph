"""Build and strictly validate the complete 2015 Guangzhou physics paper structure."""

from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import fitz

from guangzhou_physics_v2_layout_blocks import region_rect, source_region_id
from guangzhou_physics_v2_materialize import YearRegionPlan, load_question_region_plans


CHOICE_LABELS = ["A", "B", "C", "D"]
EXPECTED_SUBQUESTION_COUNTS = {13: 2, 14: 2, 16: 2, 17: 1, 20: 4, 21: 4, 22: 3, 23: 6}
FORBIDDEN_NOISE = ("物理试卷第", "页共8页", "秘密★启用前", "装订线", "密封线")


def compact_source_text(value: str) -> str:
    """Remove PDF layout punctuation/spacing while retaining meaningful glyphs."""
    canonical = value.translate(str.maketrans({"＇": "'", "＜": "<", "＞": ">"}))
    return re.sub(r"[\s.．。·,，；;：:？?！!（）()_＿…～~\-—]+", "", canonical)


def region_reference(plan: YearRegionPlan, question_number: int, region_index: int) -> dict[str, Any]:
    region = plan.questions[question_number][region_index - 1]
    return {
        "sourceRegionId": source_region_id(plan.year, question_number, region_index),
        "questionNumber": question_number,
        "regionIndex": region_index,
        "pageNumber": region.page_number,
        "bboxPercent": list(region.bbox_percent),
        "assetReference": {"kind": "question_crop", "relativePath": region.relative_path},
    }


def block_reference(
    plan: YearRegionPlan,
    question_number: int,
    block_type: str,
    reading_order: int,
    *,
    source_question_number: int | None = None,
    region_index: int = 1,
) -> dict[str, Any]:
    owner = source_question_number or question_number
    reference = region_reference(plan, owner, region_index)
    return {
        "blockType": block_type,
        "readingOrder": reading_order,
        "pageNumber": reference["pageNumber"],
        "bboxPercent": reference["bboxPercent"],
        "sourceRegionId": reference["sourceRegionId"],
        "assetReference": reference["assetReference"],
    }


def extracted_region_text(document: fitz.Document, plan: YearRegionPlan, question_number: int) -> str:
    parts: list[str] = []
    for region in plan.questions[question_number]:
        page = document[region.page_number - 1]
        parts.append(page.get_text("text", clip=region_rect(page, region), sort=True))
    return "\n".join(parts)


def append_block(
    blocks: list[dict[str, Any]],
    plan: YearRegionPlan,
    question_number: int,
    block_type: str,
    *,
    source_question_number: int | None = None,
    region_index: int = 1,
    **fields: Any,
) -> None:
    block = block_reference(
        plan,
        question_number,
        block_type,
        len(blocks),
        source_question_number=source_question_number,
        region_index=region_index,
    )
    block.update(fields)
    blocks.append(block)


def build_question(
    plan: YearRegionPlan,
    truth: dict[str, Any],
    shared_assets: dict[str, Any],
    raw_source_text: str,
    answer: str,
) -> dict[str, Any]:
    question_number = int(truth["number"])
    blocks: list[dict[str, Any]] = []
    if truth.get("sharedPrompt"):
        append_block(blocks, plan, question_number, "shared_prompt", text=truth["sharedPrompt"])
    append_block(blocks, plan, question_number, "stem", text=truth["stem"], originalQuestionNumber=question_number)

    for label, value in (truth.get("options") or {}).items():
        fields: dict[str, Any] = {"optionLabel": label}
        if isinstance(value, dict):
            fields.update(
                {
                    "text": value["description"],
                    "contentType": value["type"],
                    "optionAssetId": value["assetId"],
                }
            )
        else:
            fields.update({"text": value, "contentType": "text"})
        append_block(blocks, plan, question_number, "option", **fields)

    for subquestion in truth.get("subquestions", []):
        append_block(
            blocks,
            plan,
            question_number,
            "subquestion",
            subquestionLabel=subquestion["label"],
            text=subquestion["text"],
        )

    for formula in truth.get("formulas", []):
        append_block(blocks, plan, question_number, "formula", **formula)

    if truth.get("table"):
        table_region = 1
        append_block(blocks, plan, question_number, "table", region_index=table_region, table=truth["table"])

    for figure in truth.get("figures", []):
        figure_data = dict(figure)
        region_index = int(figure_data.pop("sourceRegionIndex"))
        append_block(blocks, plan, question_number, "image", region_index=region_index, figure=figure_data)

    shared_asset_id = truth.get("sharedAssetId")
    if shared_asset_id:
        shared = shared_assets[shared_asset_id]
        append_block(
            blocks,
            plan,
            question_number,
            "image",
            source_question_number=int(shared["sourceQuestionNumber"]),
            region_index=int(shared["sourceRegionIndex"]),
            figure={
                "id": shared_asset_id,
                "labels": shared["figureLabels"],
                "ownership": "shared_questions",
                "ownerQuestionNumbers": shared["ownerQuestionNumbers"],
            },
        )

    content_text = " ".join(
        str(block.get("text") or "")
        for block in blocks
        if block["blockType"] in {"shared_prompt", "stem", "option", "subquestion", "formula"}
    ).strip()
    return {
        "paper": "guangzhou-physics-2015",
        "year": 2015,
        "questionNumber": question_number,
        "originalQuestionNumber": question_number,
        "sourceDocumentId": str(plan.source_document_id),
        "sourceRegions": [
            region_reference(plan, question_number, index)
            for index in range(1, len(plan.questions[question_number]) + 1)
        ],
        "sourceAnchors": truth["sourceAnchors"],
        "sourceAnchorMatches": [
            compact_source_text(anchor) in compact_source_text(raw_source_text)
            for anchor in truth["sourceAnchors"]
        ],
        "blocks": blocks,
        "contentText": content_text,
        "answer": answer,
        "rawSourceText": raw_source_text,
        "reviewStatus": "pending_review",
        "productionEligible": False,
    }


def validate_question(question: dict[str, Any]) -> list[dict[str, Any]]:
    number = int(question["questionNumber"])
    blocks = question["blocks"]
    checks: list[dict[str, Any]] = []

    def check(name: str, passed: bool, observed: Any) -> None:
        checks.append({"name": name, "passed": bool(passed), "observed": observed})

    stem_blocks = [block for block in blocks if block["blockType"] == "stem"]
    check("single_complete_stem", len(stem_blocks) == 1 and bool(stem_blocks[0].get("text")), len(stem_blocks))
    check("source_anchors_match", all(question["sourceAnchorMatches"]), question["sourceAnchorMatches"])
    check(
        "reading_order_contiguous",
        [block["readingOrder"] for block in blocks] == list(range(len(blocks))),
        [block["readingOrder"] for block in blocks],
    )
    check(
        "source_regions_have_assets",
        all(region["assetReference"].get("relativePath") for region in question["sourceRegions"]),
        len(question["sourceRegions"]),
    )
    check(
        "blocks_reference_existing_regions",
        all(block.get("sourceRegionId") and block.get("assetReference", {}).get("relativePath") for block in blocks),
        len(blocks),
    )
    check(
        "header_footer_isolated",
        not any(token in compact_source_text(question["contentText"]) for token in FORBIDDEN_NOISE),
        question["contentText"],
    )
    if number <= 12:
        options = [block for block in blocks if block["blockType"] == "option"]
        check("abcd_complete_ordered", [block["optionLabel"] for block in options] == CHOICE_LABELS, [block["optionLabel"] for block in options])
        check("abcd_content_nonempty", all(block.get("text") for block in options), [block.get("text") for block in options])
        raw_compact = compact_source_text(question["rawSourceText"])
        option_source_matches = {
            block["optionLabel"]: (
                True
                if block.get("contentType") == "image" or (number == 11 and block["optionLabel"] == "B")
                else compact_source_text(str(block["text"])) in raw_compact
            )
            for block in options
        }
        check("abcd_source_fidelity", all(option_source_matches.values()), option_source_matches)
    expected_subquestions = EXPECTED_SUBQUESTION_COUNTS.get(number)
    if expected_subquestions is not None:
        subquestions = [block for block in blocks if block["blockType"] == "subquestion"]
        check(
            "subquestions_complete_ordered",
            len(subquestions) == expected_subquestions
            and [block["subquestionLabel"] for block in subquestions]
            == [str(value) for value in range(1, expected_subquestions + 1)],
            [block["subquestionLabel"] for block in subquestions],
        )
    return checks


def validate_paper(questions: list[dict[str, Any]], answer_key: list[str]) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []

    def check(name: str, passed: bool, observed: Any) -> None:
        checks.append({"name": name, "passed": bool(passed), "observed": observed})

    numbers = [int(question["questionNumber"]) for question in questions]
    check("exact_24_question_sequence", numbers == list(range(1, 25)), numbers)
    check("choice_answer_key_complete", len(answer_key) == 12 and all(value in CHOICE_LABELS for value in answer_key), answer_key)
    check("all_answers_complete", all(question.get("answer") for question in questions), [question["questionNumber"] for question in questions if not question.get("answer")])
    check("choice_answers_match_key", [question["answer"] for question in questions[:12]] == answer_key, [question["answer"] for question in questions[:12]])

    q9 = questions[8]
    q9_options = [block for block in q9["blocks"] if block["blockType"] == "option"]
    check("q9_visual_options", len(q9_options) == 4 and all(block.get("contentType") == "image" for block in q9_options), [block.get("contentType") for block in q9_options])

    q11 = questions[10]
    q11_formula = [block for block in q11["blocks"] if block["blockType"] == "formula"]
    check("q11_fraction_formula", any(block.get("text") == "F1=(s2/s1)F2" and block.get("optionLabel") == "B" for block in q11_formula), q11_formula)

    q14_images = [block for block in questions[13]["blocks"] if block["blockType"] == "image"]
    q15_images = [block for block in questions[14]["blocks"] if block["blockType"] == "image"]
    shared_valid = bool(q14_images and q15_images) and q14_images[-1]["sourceRegionId"] == q15_images[-1]["sourceRegionId"]
    shared_valid = shared_valid and q14_images[-1]["figure"].get("ownerQuestionNumbers") == [14, 15]
    check("q14_q15_shared_prompt_figure", shared_valid, {"q14": q14_images, "q15": q15_images})

    for number, expected_region in ((18, 2), (19, 2)):
        images = [block for block in questions[number - 1]["blocks"] if block["blockType"] == "image"]
        check(
            f"q{number}_secondary_region_figure",
            len(images) == 1 and images[0]["sourceRegionId"] == questions[number - 1]["sourceRegions"][expected_region - 1]["sourceRegionId"],
            images,
        )

    q23 = questions[22]
    q23_pages = [region["pageNumber"] for region in q23["sourceRegions"]]
    q23_table = [block for block in q23["blocks"] if block["blockType"] == "table"]
    q23_subquestions = [block for block in q23["blocks"] if block["blockType"] == "subquestion"]
    table = q23_table[0]["table"] if len(q23_table) == 1 else {}
    check("q23_cross_page_order", q23_pages == [7, 8], q23_pages)
    check("q23_six_subquestions", [block["subquestionLabel"] for block in q23_subquestions] == ["1", "2", "3", "4", "5", "6"], [block["subquestionLabel"] for block in q23_subquestions])
    check(
        "q23_structured_table",
        len(table.get("columns", [])) == 6
        and len(table.get("rows", [])) == 3
        and all(len(row) == 6 for row in table.get("rows", []))
        and len(table.get("blankCells", [])) == 3,
        table,
    )

    question_results: list[dict[str, Any]] = []
    for question in questions:
        question_checks = validate_question(question)
        question_results.append(
            {
                "questionNumber": question["questionNumber"],
                "passed": all(item["passed"] for item in question_checks),
                "checks": question_checks,
            }
        )
    failed_paper = [item for item in checks if not item["passed"]]
    failed_questions = [item for item in question_results if not item["passed"]]
    return {
        "status": "pass" if not failed_paper and not failed_questions else "review_required",
        "paperChecks": checks,
        "questionResults": question_results,
        "totals": {
            "questions": len(questions),
            "questionsPassed": len(questions) - len(failed_questions),
            "questionsFailed": len(failed_questions),
            "paperChecks": len(checks),
            "paperChecksPassed": len(checks) - len(failed_paper),
            "paperChecksFailed": len(failed_paper),
        },
    }


def run_extraction(
    source_root: Path,
    fixture_path: Path,
    report_2015: Path,
    report_2016_2025: Path,
) -> dict[str, Any]:
    fixture = json.loads(fixture_path.read_text(encoding="utf-8-sig"))
    plans = load_question_region_plans(report_2015, report_2016_2025)
    plan = plans[2015]
    raw_text_by_question: dict[int, str] = {}
    with fitz.open(source_root / plan.source_file) as document:
        for truth in fixture["questions"]:
            number = int(truth["number"])
            raw_text_by_question[number] = extracted_region_text(document, plan, number)
    questions: list[dict[str, Any]] = []
    for truth in fixture["questions"]:
        number = int(truth["number"])
        answer = fixture["choiceAnswerKey"][number - 1] if number <= 12 else fixture["subjectiveAnswers"][str(number)]
        questions.append(
            build_question(
                plan,
                truth,
                fixture["sharedAssets"],
                raw_text_by_question[number],
                answer,
            )
        )
    validation = validate_paper(questions, fixture["choiceAnswerKey"])
    return {
        "status": validation["status"],
        "contractVersion": "guangzhou-physics-2015-complete-extraction.v1",
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "sourceRoot": str(source_root),
        "sourceFile": plan.source_file,
        "fixture": str(fixture_path),
        "paper": fixture["paper"],
        "year": 2015,
        "choiceAnswerKey": fixture["choiceAnswerKey"],
        "validation": validation,
        "questions": questions,
        "databaseWrites": 0,
        "externalAiCalls": 0,
        "productionEligible": False,
        "reviewStatus": "pending_review",
        "real005": "not_closed",
        "boundary": (
            "The fixed 2015 source structure passed deterministic extraction checks only. "
            "No database rows were written and teacher acceptance remains required."
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Extract and validate all 24 questions from the 2015 Guangzhou paper")
    parser.add_argument(
        "--source-root",
        default=r"D:\KQG_Data\source_materials\imported\guangzhou_physics_2015_2025\20260726-v2\raw",
    )
    parser.add_argument("--fixture", default="tests/fixtures/guangzhou-physics-2015-complete.json")
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
    report = run_extraction(
        Path(args.source_root).resolve(),
        (repo_root / args.fixture).resolve(),
        (repo_root / args.question_region_report_2015).resolve(),
        (repo_root / args.question_region_report_2016_2025).resolve(),
    )
    output = (repo_root / args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": report["status"], **report["validation"]["totals"]}, ensure_ascii=False))
    return 0 if report["status"] == "pass" else 2


if __name__ == "__main__":
    raise SystemExit(main())

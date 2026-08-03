from __future__ import annotations

import json
import sys
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from guangzhou_physics_2015_complete_extraction import run_extraction  # noqa: E402
from guangzhou_physics_2015_complete_materialize import materialized_structure_blocks  # noqa: E402


SOURCE_ROOT = Path(
    r"D:\KQG_Data\source_materials\imported\guangzhou_physics_2015_2025\20260726-v2\raw"
)
FIXTURE = ROOT / "tests/fixtures/guangzhou-physics-2015-complete.json"
REPORT_2015 = ROOT / "docs/evidence/20260726-guangzhou-physics-v2-2015-question-regions.json"
REPORT_2016_2025 = ROOT / "docs/evidence/20260726-guangzhou-physics-v2-question-regions.json"


def build_report() -> dict:
    return run_extraction(SOURCE_ROOT, FIXTURE, REPORT_2015, REPORT_2016_2025)


def test_fixture_has_complete_24_question_truth() -> None:
    fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))

    assert [question["number"] for question in fixture["questions"]] == list(range(1, 25))
    assert fixture["choiceAnswerKey"] == ["B", "A", "C", "B", "A", "D", "A", "D", "B", "C", "C", "D"]
    for question in fixture["questions"][:12]:
        assert list(question["options"]) == ["A", "B", "C", "D"]


def test_complete_2015_extraction_passes_strict_validation() -> None:
    report = build_report()

    assert report["status"] == "pass"
    assert report["validation"]["totals"] == {
        "questions": 24,
        "questionsPassed": 24,
        "questionsFailed": 0,
        "paperChecks": 12,
        "paperChecksPassed": 12,
        "paperChecksFailed": 0,
    }
    assert report["databaseWrites"] == 0
    assert report["productionEligible"] is False
    assert report["real005"] == "not_closed"


def test_visual_formula_shared_and_cross_page_cases_are_explicit() -> None:
    report = build_report()
    questions = {question["questionNumber"]: question for question in report["questions"]}

    q9_options = [block for block in questions[9]["blocks"] if block["blockType"] == "option"]
    assert [block["contentType"] for block in q9_options] == ["image"] * 4

    q11_formulas = [block for block in questions[11]["blocks"] if block["blockType"] == "formula"]
    assert {block["text"] for block in q11_formulas} == {"F1=(s2/s1)F2"}

    q14_image = next(block for block in questions[14]["blocks"] if block["blockType"] == "image")
    q15_image = next(block for block in questions[15]["blocks"] if block["blockType"] == "image")
    assert q14_image["sourceRegionId"] == q15_image["sourceRegionId"]
    assert q15_image["figure"]["ownerQuestionNumbers"] == [14, 15]

    assert [region["pageNumber"] for region in questions[23]["sourceRegions"]] == [7, 8]
    q23_subquestions = [block for block in questions[23]["blocks"] if block["blockType"] == "subquestion"]
    assert [block["subquestionLabel"] for block in q23_subquestions] == ["1", "2", "3", "4", "5", "6"]


def test_materialized_blocks_match_api_and_teacher_ui_contracts() -> None:
    report = build_report()
    questions = {question["questionNumber"]: question for question in report["questions"]}

    q9_blocks = materialized_structure_blocks(uuid.UUID(int=9), questions[9])
    options = [block for block in q9_blocks if block["type"] == "option"]
    images = [block for block in q9_blocks if block["type"] == "image"]
    assert [block["content"]["label"] for block in options] == ["A", "B", "C", "D"]
    assert all("optionLabel" not in block["content"] for block in options)
    assert len(images) == 2
    assert all(block["content"]["status"] == "extracted" for block in images)

    q23_blocks = materialized_structure_blocks(uuid.UUID(int=23), questions[23])
    table = next(block for block in q23_blocks if block["type"] == "table")
    subquestions = [block for block in q23_blocks if block["type"] == "subquestion"]
    assert table["content"]["table"]["columns"] == ["数据序号", "1", "2", "3", "4", "5"]
    assert [block["content"]["label"] for block in subquestions] == ["1", "2", "3", "4", "5", "6"]

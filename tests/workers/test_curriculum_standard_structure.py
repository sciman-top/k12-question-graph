import copy
import hashlib
import json
import pathlib
import sys
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOLS_ROOT = REPO_ROOT / "tools"
FIXTURE_PATH = REPO_ROOT / "tests" / "golden-import" / "curriculum-standard-structure-fixture.json"
if str(TOOLS_ROOT) not in sys.path:
    sys.path.insert(0, str(TOOLS_ROOT))

import curriculum_standard_structure as structure  # noqa: E402


PRIMARY_NUMERALS = {"1": "一", "2": "二", "3": "三", "4": "四", "5": "五"}


def load_fixture() -> dict:
    return json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))


def build_synthetic_pages(
    fixture: dict,
    *,
    missing_code: str | None = None,
    duplicate_code: str | None = None,
) -> list[str]:
    pages: list[list[str]] = [[] for _ in range(fixture["source"]["pageCount"])]
    secondary_by_parent: dict[str, list[dict]] = {}
    for secondary in fixture["expected"]["secondaryThemes"]:
        secondary_by_parent.setdefault(secondary["parentCode"], []).append(secondary)

    for primary in fixture["expected"]["primaryThemes"]:
        primary_code = primary["code"]
        heading_page = primary["headingPdfPage"]
        pages[heading_page - 1].append(f"({PRIMARY_NUMERALS[primary_code]}){primary['title']}")
        secondaries = secondary_by_parent[primary_code]
        pages[secondaries[0]["headingPdfPage"] - 1].append("【内容要求】")
        for secondary in secondaries:
            target = pages[secondary["headingPdfPage"] - 1]
            target.append(f"{secondary['code']}{secondary['title']}")
            for index in range(1, secondary["officialRequirementCount"] + 1):
                code = f"{secondary['code']}.{index}"
                if code == missing_code:
                    continue
                target.extend(
                    [
                        f"{code}合成要求{code}第一段，",
                        f"继续说明{code}。",
                        f"例 {index} 合成样例，不属于要求原文。",
                    ]
                )
                if code == duplicate_code:
                    target.append(f"{code}重复要求应触发人工接管。")
            target.append("活动建议：")
        pages[secondaries[-1]["headingPdfPage"] - 1].append("【学业要求】")
    return ["\n".join(lines) for lines in pages]


def source_context(fixture: dict) -> dict:
    source = fixture["source"]
    return {
        "material_id": source["materialId"],
        "source_document_id": source["sourceDocumentId"],
        "source_document_version": source["sourceDocumentVersion"],
        "source_document_sha256": source["sourceDocumentSha256"],
    }


class CurriculumStandardStructureTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = load_fixture()
        self.pages = build_synthetic_pages(self.fixture)
        self.synthetic_fixture = copy.deepcopy(self.fixture)
        self.synthetic_fixture["expected"].pop("requirementSetSha256")
        self.synthetic_fixture["expected"].pop("multiPageRequirementCodes")
        self.synthetic_fixture.pop("selectedRequirementAnchors")

    def test_golden_fixture_is_metadata_only_and_has_the_expected_shape(self) -> None:
        serialized = json.dumps(self.fixture, ensure_ascii=False)
        expected = self.fixture["expected"]
        self.assertNotIn('"source_text"', serialized)
        self.assertFalse(self.fixture["source"]["sharingAllowed"])
        self.assertEqual(len(expected["primaryThemes"]), expected["primaryThemeCount"])
        self.assertEqual(len(expected["secondaryThemes"]), expected["secondaryThemeCount"])
        self.assertEqual(
            sum(item["officialRequirementCount"] for item in expected["secondaryThemes"]),
            expected["officialRequirementCount"],
        )
        self.assertEqual(
            {page["role"] for page in self.fixture["representativePages"]},
            {"table_of_contents", "curriculum_content", "academic_quality", "item_development"},
        )
        for page in self.fixture["representativePages"]:
            self.assertRegex(page["normalizedTextSha256"], r"^[0-9a-f]{64}$")
        self.assertEqual(
            self.fixture["expected"]["multiPageRequirementCodes"],
            ["1.3.2", "2.2.7", "3.5.1", "5.3.2"],
        )
        self.assertRegex(
            self.fixture["expected"]["requirementSetSha256"],
            r"^[0-9a-f]{64}$",
        )
        self.assertEqual(len(self.fixture["selectedRequirementAnchors"]), 7)
        for anchor in self.fixture["selectedRequirementAnchors"]:
            self.assertRegex(anchor["sourceTextSha256"], r"^[0-9a-f]{64}$")
            self.assertEqual(
                len(anchor["pdfPageNumbers"]),
                len(anchor["textBlockSha256"]),
            )

    def test_extracts_five_eighteen_eighty_nine_candidate_contract(self) -> None:
        result = structure.extract_structure_from_pages(
            self.pages,
            source_context(self.fixture),
            self.synthetic_fixture,
        )

        self.assertEqual(result["extraction"]["status"], "pass")
        self.assertFalse(result["extraction"]["manual_takeover_required"])
        self.assertEqual(len(result["hierarchy"]), 5)
        self.assertEqual(sum(len(theme["children"]) for theme in result["hierarchy"]), 18)
        self.assertEqual(len(result["curriculum_requirements"]), 89)
        self.assertEqual(
            len({item["official_item_code"] for item in result["curriculum_requirements"]}),
            89,
        )

        for requirement in result["curriculum_requirements"]:
            self.assertEqual(requirement["schema_version"], "curriculum-requirement.v1")
            self.assertEqual(requirement["record_type"], "curriculum_requirement")
            self.assertTrue(requirement["source_text"])
            self.assertEqual(requirement["behavior_verbs"], [])
            self.assertEqual(requirement["cognitive_demands"], [])
            self.assertEqual(requirement["ability_dimensions"], [])
            self.assertEqual(requirement["knowledge_stable_ids"], [])
            self.assertEqual(requirement["facets"], [])
            self.assertEqual(requirement["status"], "candidate")
            self.assertEqual(requirement["review_status"], "pending_review")
            self.assertFalse(requirement["production_eligible"])
            self.assertTrue(requirement["evidence_anchors"])
            self.assertNotIn("合成样例", requirement["source_text"])
            for anchor in requirement["evidence_anchors"]:
                self.assertIsNone(anchor["source_region_id"])
                self.assertRegex(anchor["text_block_sha256"], r"^[0-9a-f]{64}$")

    def test_cross_page_requirement_has_one_anchor_per_page_fragment(self) -> None:
        pages = [""] * 14
        pages[10] = "(一)物质"
        pages[11] = "【内容要求】\n1.1物质的形态和变化\n1.1.1第一页面内容，"
        pages[12] = "第二页面内容。\n【学业要求】"

        parsed = structure.parse_curriculum_content(pages, source_context(self.fixture))
        requirement = parsed["requirements"][0]

        self.assertEqual(requirement["official_item_code"], "1.1.1")
        self.assertEqual(requirement["source_text"], "第一页面内容，第二页面内容。")
        self.assertEqual(
            [anchor["pdf_page_number"] for anchor in requirement["evidence_anchors"]],
            [12, 13],
        )
        self.assertEqual(
            [anchor["printed_page_number"] for anchor in requirement["evidence_anchors"]],
            [9, 10],
        )
        self.assertEqual(
            requirement["evidence_anchors"][0]["text_block_sha256"],
            hashlib.sha256("第一页面内容，".encode("utf-8")).hexdigest(),
        )

    def test_missing_official_item_fails_closed_without_formal_candidates(self) -> None:
        pages = build_synthetic_pages(self.fixture, missing_code="3.4.7")
        result = structure.extract_structure_from_pages(
            pages,
            source_context(self.fixture),
            self.synthetic_fixture,
        )

        self.assertEqual(result["extraction"]["status"], "manual_takeover_required")
        self.assertTrue(result["extraction"]["manual_takeover_required"])
        self.assertEqual(result["hierarchy"], [])
        self.assertEqual(result["curriculum_requirements"], [])
        self.assertTrue(any("3.4" in issue for issue in result["extraction"]["issues"]))

    def test_duplicate_official_item_fails_closed_without_formal_candidates(self) -> None:
        pages = build_synthetic_pages(self.fixture, duplicate_code="2.2.5")
        result = structure.extract_structure_from_pages(
            pages,
            source_context(self.fixture),
            self.synthetic_fixture,
        )

        self.assertEqual(result["extraction"]["status"], "manual_takeover_required")
        self.assertEqual(result["hierarchy"], [])
        self.assertEqual(result["curriculum_requirements"], [])
        self.assertTrue(any("duplicate official item code: 2.2.5" in issue for issue in result["extraction"]["issues"]))

    def test_selected_source_hash_drift_fails_closed_even_when_counts_match(self) -> None:
        baseline = structure.extract_structure_from_pages(
            self.pages,
            source_context(self.fixture),
            self.synthetic_fixture,
        )
        requirement = next(
            item
            for item in baseline["curriculum_requirements"]
            if item["official_item_code"] == "1.1.1"
        )
        drift_fixture = copy.deepcopy(self.synthetic_fixture)
        drift_fixture["selectedRequirementAnchors"] = [
            {
                "officialItemCode": "1.1.1",
                "sourceTextSha256": "0" * 64,
                "pdfPageNumbers": [
                    anchor["pdf_page_number"]
                    for anchor in requirement["evidence_anchors"]
                ],
                "printedPageNumbers": [
                    anchor["printed_page_number"]
                    for anchor in requirement["evidence_anchors"]
                ],
                "textBlockSha256": [
                    anchor["text_block_sha256"]
                    for anchor in requirement["evidence_anchors"]
                ],
            }
        ]

        result = structure.extract_structure_from_pages(
            self.pages,
            source_context(self.fixture),
            drift_fixture,
        )

        self.assertEqual(result["extraction"]["status"], "manual_takeover_required")
        self.assertEqual(result["hierarchy"], [])
        self.assertEqual(result["curriculum_requirements"], [])
        self.assertTrue(
            any(
                "selected golden requirement drift for 1.1.1" in issue
                for issue in result["extraction"]["issues"]
            )
        )

    def test_page_mapping_contract_is_explicit_before_stable_offset(self) -> None:
        mapping = self.fixture["pageMapping"]
        self.assertIsNone(structure.printed_page_number(1, mapping))
        self.assertEqual(structure.printed_page_number(2, mapping), 1)
        self.assertEqual(structure.printed_page_number(3, mapping), 2)
        self.assertEqual(structure.printed_page_number(4, mapping), 1)
        self.assertEqual(structure.printed_page_number(51, mapping), 48)

    def test_unknown_theme_title_fails_closed(self) -> None:
        fixture = copy.deepcopy(self.synthetic_fixture)
        fixture["expected"]["primaryThemes"][0]["title"] = "未知主题"
        result = structure.extract_structure_from_pages(
            self.pages,
            source_context(self.fixture),
            fixture,
        )

        self.assertEqual(result["extraction"]["status"], "manual_takeover_required")
        self.assertTrue(any("primary theme" in issue for issue in result["extraction"]["issues"]))


if __name__ == "__main__":
    unittest.main()

from __future__ import annotations

import sys
import unittest
from pathlib import Path

TOOLS_ROOT = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS_ROOT))

import guangzhou_three_source_alignment as alignment  # noqa: E402


class GuangzhouThreeSourceAlignmentTests(unittest.TestCase):
    def test_historical_year_is_retrospective_and_not_original_basis(self) -> None:
        result = alignment.build_alignment(index_fixture(2020), crosswalk_fixture(), regimes_fixture())
        candidate = result["alignmentCandidates"][0]
        self.assertEqual(candidate["alignmentType"], "retrospective_crosswalk")
        self.assertFalse(candidate["originalBasis"])

    def test_contemporaneous_year_remains_inferred_without_report_citation(self) -> None:
        result = alignment.build_alignment(index_fixture(2025), crosswalk_fixture(), regimes_fixture())
        candidate = result["alignmentCandidates"][0]
        self.assertEqual(candidate["alignmentType"], "contemporaneous_inferred")
        self.assertNotEqual(candidate["alignmentType"], "source_cited")
        self.assertIn("report_question_anchor_missing", result["bundles"][0]["conflictReasons"])

    def test_conflicting_or_missing_facts_are_preserved_for_review(self) -> None:
        index = index_fixture(2025)
        index["questions"][0]["candidates"]["primaryKnowledgeCandidateId"] = "UNKNOWN"
        result = alignment.build_alignment(index, crosswalk_fixture(), regimes_fixture())
        self.assertEqual(result["alignmentCandidates"], [])
        self.assertIn("curriculum_mapping_candidate_missing", result["bundles"][0]["conflictReasons"])

    def test_overlapping_regimes_fail_closed(self) -> None:
        regimes = regimes_fixture()
        regimes["regimes"].append(dict(regimes["regimes"][1]))
        with self.assertRaisesRegex(ValueError, "curriculum_regime_count"):
            alignment.build_alignment(index_fixture(2025), crosswalk_fixture(), regimes)


def index_fixture(year: int) -> dict:
    return {"questions": [{
        "questionItemId": "q1", "year": year, "questionNumber": 1,
        "anchors": {"paper": [{"sourceRegionId": "p"}], "answer": [{"sourceRegionId": "a"}], "report": []},
        "sourceDocuments": {"report": {"sourceDocumentId": "r", "fileAssetId": "f"}},
        "candidates": {"primaryKnowledgeCandidateId": "K1", "knowledgeCandidateIds": [], "primaryExamPointCandidateId": "E1"},
    }]}


def crosswalk_fixture() -> dict:
    return {"mappings": [{
        "source_stable_id": "CR-1-F01", "parent_requirement_stable_id": "CR-1",
        "target_knowledge_code": "K1", "confidence": 0.9,
        "evidence_anchor_sha256": "abc", "review_reasons": ["high_impact_asset_mapping"],
    }]}


def regimes_fixture() -> dict:
    return {"regimes": [
        {"fromYear": 2015, "toYear": 2024, "allowedAlignmentType": "retrospective_crosswalk", "standardVersion": "historical-unverified"},
        {"fromYear": 2025, "toYear": 2025, "allowedAlignmentType": "contemporaneous_inferred", "standardVersion": "2022-2025-revision"},
    ]}


if __name__ == "__main__":
    unittest.main()

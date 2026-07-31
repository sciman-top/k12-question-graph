from __future__ import annotations

import sys
import unittest
from pathlib import Path

TOOLS_ROOT = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS_ROOT))

import guangzhou_exam_evidence_index as indexer  # noqa: E402


class GuangzhouExamEvidenceIndexTests(unittest.TestCase):
    def test_index_uses_ids_and_routes_missing_report_to_review(self) -> None:
        snapshot = fixture_snapshot()
        result = indexer.build_index(snapshot, fixture_role_map())
        question = result["questions"][0]

        self.assertEqual(question["anchors"]["paper"][0]["sourceRegionId"], "rp")
        self.assertEqual(question["anchors"]["answer"][0]["sourceDocumentId"], "da")
        self.assertEqual(question["anchors"]["report"], [])
        self.assertEqual(question["sourceDocuments"]["report"]["sourceDocumentId"], "dr")
        self.assertEqual(question["candidates"]["primaryKnowledgeCandidateId"], "K1")
        self.assertEqual(result["reviewItems"][0]["reason"], "report_question_anchor_missing")
        self.assertTrue(result["readiness"]["questionCorpusReady"])
        self.assertFalse(result["readiness"]["reportEvidenceReady"])
        self.assertFalse(result["readiness"]["allFieldExtractionReady"])
        self.assertNotIn("sourceTitle", question["joinKeys"])

    def test_missing_paper_or_answer_is_blocker(self) -> None:
        snapshot = fixture_snapshot()
        snapshot["blocks"] = [row for row in snapshot["blocks"] if row["source_type"] != "answer_or_solution"]

        result = indexer.build_index(snapshot, fixture_role_map())

        self.assertIn("answer_anchor_missing:2020:1", result["blockers"])

    def test_2020_paper_and_answer_must_share_file_asset(self) -> None:
        snapshot = fixture_snapshot()
        snapshot["sources"][1]["file_asset_id"] = "different"

        result = indexer.build_index(snapshot, fixture_role_map())

        self.assertIn("shared_file_role_mismatch:2020:paper:answer", result["blockers"])

    def test_expected_years_and_question_count_fail_closed(self) -> None:
        role_map = fixture_role_map()
        role_map["expectedYears"] = [2019, 2020]
        role_map["expectedQuestionCount"] = 2

        result = indexer.build_index(fixture_snapshot(), role_map)

        self.assertTrue(any(value.startswith("question_year_coverage_mismatch:") for value in result["blockers"]))
        self.assertIn("question_count_mismatch:expected=2:actual=1", result["blockers"])

    def test_duplicate_year_question_number_is_blocker(self) -> None:
        snapshot = fixture_snapshot()
        snapshot["questions"].append(dict(snapshot["questions"][0], question_item_id="q2"))

        result = indexer.build_index(snapshot, fixture_role_map())

        self.assertIn("duplicate_year_question_number", result["blockers"])

    def test_missing_stem_or_answer_content_blocks_question_corpus(self) -> None:
        snapshot = fixture_snapshot()
        snapshot["blocks"][0]["content"] = {"text": ""}
        snapshot["blocks"][1]["content"] = {"value": "", "solution": ""}

        result = indexer.build_index(snapshot, fixture_role_map())

        self.assertIn("question_stem_missing:2020:1", result["readinessBlockers"])
        self.assertIn("answer_content_missing:2020:1", result["readinessBlockers"])
        self.assertFalse(result["readiness"]["questionCorpusReady"])

    def test_per_year_question_sequence_is_required_for_readiness(self) -> None:
        role_map = fixture_role_map()
        role_map["expectedQuestionCountsByYear"] = {"2020": 2}

        result = indexer.build_index(fixture_snapshot(), role_map)

        self.assertIn("question_sequence_mismatch:2020:missing=2:unexpected=", result["readinessBlockers"])
        self.assertFalse(result["readiness"]["questionCorpusReady"])


def fixture_role_map() -> dict:
    return {
        "roles": {"paper": "local_exam_paper", "answer": "answer_or_solution", "report": "exam_analysis_report"},
        "joinAuthority": ["question_item_id", "question_block_id", "source_region_id", "source_document_id"],
        "displayOnlyFields": ["source_title"],
        "expectedYears": [2020],
        "expectedQuestionCount": 1,
        "expectedQuestionCountsByYear": {"2020": 1},
        "sharedFileRoleRequirements": [{"year": 2020, "roles": ["paper", "answer"], "requireSameFileAssetId": True}],
    }


def fixture_snapshot() -> dict:
    return {
        "questions": [{
            "question_item_id": "q1", "year": 2020, "question_number": 1,
            "primary_knowledge_candidate_id": "K1", "knowledge_candidate_ids": ["K2"],
            "primary_exam_point_candidate_id": "E1",
            "status": "pending_review", "production_eligible": False,
        }],
        "sources": [
            {"year": 2020, "source_type": "local_exam_paper", "source_document_id": "dp", "file_asset_id": "shared"},
            {"year": 2020, "source_type": "answer_or_solution", "source_document_id": "da", "file_asset_id": "shared"},
            {"year": 2020, "source_type": "exam_analysis_report", "source_document_id": "dr", "file_asset_id": "report"},
        ],
        "blocks": [
            {"question_item_id": "q1", "question_block_id": "bp", "block_type": "stem", "content": {"text": "题干"}, "source_region_id": "rp", "source_document_id": "dp", "source_type": "local_exam_paper"},
            {"question_item_id": "q1", "question_block_id": "ba", "block_type": "answer", "content": {"value": "A", "solution": "解析"}, "source_region_id": "ra", "source_document_id": "da", "source_type": "answer_or_solution"},
        ],
    }


if __name__ == "__main__":
    unittest.main()

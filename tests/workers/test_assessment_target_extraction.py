from __future__ import annotations

import sys
import unittest
from pathlib import Path

TOOLS_ROOT = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS_ROOT))

import assessment_target_extraction as extraction  # noqa: E402


class AssessmentTargetExtractionTests(unittest.TestCase):
    def test_every_scope_gets_exactly_one_primary_candidate(self) -> None:
        result = extraction.build_candidates(scope_fixture(), alignment_fixture())
        self.assertEqual(len(result["targets"]), 2)
        self.assertTrue(result["invariants"]["one_primary_per_scope"])
        self.assertTrue(result["invariants"]["all_scopes_covered"])

    def test_existing_question_facts_populate_semantic_candidates(self) -> None:
        target = extraction.build_candidates(scope_fixture(), alignment_fixture())["targets"][0]
        semantic = {row["field"]: row for row in target["field_provenance"]}
        self.assertEqual(semantic["ability_dimensions"]["source_kind"], "explicit_fact")
        self.assertEqual(target["primary_knowledge_id"], "K1")
        self.assertEqual(target["ability_dimensions"], ["信息提取", "科学推理"])
        self.assertEqual(target["cognitive_demands"], ["信息提取", "推理"])
        self.assertEqual(target["context_type"], "real_world")
        self.assertEqual(target["representation_types"], ["diagram", "text"])
        self.assertEqual(target["task_type"], "single_choice")
        self.assertEqual(target["score_weight"], 3.0)
        self.assertNotIn("语义待教师复核", target["target_statement"])

    def test_unknown_knowledge_routes_to_review_without_fake_id(self) -> None:
        alignments = alignment_fixture()
        alignments["alignmentCandidates"] = []
        alignments["bundles"][0]["questionFacts"]["primaryKnowledgeCandidateId"] = None
        result = extraction.build_candidates(scope_fixture(), alignments)
        self.assertIsNone(result["targets"][0]["primary_knowledge_id"])
        self.assertIn("unknown_primary_knowledge", result["review_queue"][0]["reasons"])

    def test_source_facts_are_preserved_as_refs(self) -> None:
        target = extraction.build_candidates(scope_fixture(), alignment_fixture())["targets"][0]
        self.assertEqual(target["evidence_refs"][0]["source_region_id"], "22222222-2222-2222-2222-222222222222")
        self.assertTrue(target["question_scope"]["scope_key"].startswith("question-scope:v1:"))

    def test_question_level_alignment_is_not_copied_to_subquestion_scope(self) -> None:
        result = extraction.build_candidates(scope_fixture(), alignment_fixture())
        whole, subquestion = result["targets"]
        self.assertEqual(whole["curriculum_alignment_ids"], ["CAL-1"])
        self.assertEqual(subquestion["curriculum_alignment_ids"], [])
        self.assertIsNone(subquestion["primary_knowledge_id"])


def scope_fixture() -> dict:
    question_id = "11111111-1111-1111-1111-111111111111"
    return {"questions": [{
        "questionId": question_id, "questionNumber": 1,
        "scopes": [
            {"scopeKey": f"question-scope:v1:{question_id}:whole_question", "scopeType": "whole_question", "questionId": question_id, "questionBlockRef": None},
            {"scopeKey": f"question-scope:v1:{question_id}:subquestion:S1", "scopeType": "subquestion", "questionId": question_id, "questionBlockRef": {"id": "44444444-4444-4444-4444-444444444444"}},
        ],
    }]}


def alignment_fixture() -> dict:
    return {
        "bundles": [{
            "questionItemId": "11111111-1111-1111-1111-111111111111",
            "paperAnchors": [{"sourceDocumentId": "33333333-3333-3333-3333-333333333333", "sourceRegionId": "22222222-2222-2222-2222-222222222222"}],
            "answerAnchors": [{"sourceDocumentId": "55555555-5555-5555-5555-555555555555", "sourceRegionId": "66666666-6666-6666-6666-666666666666"}],
            "conflictReasons": [],
            "questionFacts": {
                "primaryKnowledgeCandidateId": "K1",
                "primaryKnowledgeLabel": "机械运动",
                "officialExamPointSummary": "考查运动和相互作用主题",
                "abilityDimensions": ["信息提取", "科学推理"],
                "questionType": "single_choice",
                "scoreWeight": 3.0,
                "stemText": "小明观察图示装置，判断运动状态。",
                "blockTypes": ["stem", "image", "answer"],
            },
        }],
        "alignmentCandidates": [{"questionItemId": "11111111-1111-1111-1111-111111111111", "alignmentId": "CAL-1", "knowledgeCandidateId": "K1"}],
    }


if __name__ == "__main__":
    unittest.main()

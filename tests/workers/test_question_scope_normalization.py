from __future__ import annotations

import sys
import unittest
import uuid
from pathlib import Path


TOOLS_ROOT = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS_ROOT))

import question_scope_normalization as scopes  # noqa: E402
import guangzhou_physics_v2_materialize as materialize  # noqa: E402


class QuestionScopeNormalizationTests(unittest.TestCase):
    def test_whole_question_scope_has_stable_key_and_no_block_reference(self) -> None:
        result = scopes.normalize_question_scopes("QPHY-C003-2016-01", [], [])

        self.assertEqual(
            result["scopes"],
            [
                {
                    "scopeKey": "question-scope:v1:QPHY-C003-2016-01:whole_question",
                    "scopeType": "whole_question",
                    "questionId": "QPHY-C003-2016-01",
                    "questionBlockRef": None,
                    "reviewStatus": "pending_review",
                    "productionEligible": False,
                }
            ],
        )

    def test_whole_marker_does_not_create_a_subquestion_block(self) -> None:
        result = scopes.normalize_question_scopes(
            "QPHY-C003-2016-01",
            [
                {
                    "subquestion_id": "QPHY-C003-2016-01-S01",
                    "subquestion_number": "whole",
                    "stem_summary": "整题摘要",
                }
            ],
            [],
        )

        self.assertEqual(len(result["scopes"]), 1)
        self.assertEqual(result["blockCandidates"], [])
        self.assertEqual(result["wholeMarkerRows"], 1)

    def test_explicit_subquestion_creates_stable_pending_block_scope(self) -> None:
        result = scopes.normalize_question_scopes(
            "QPHY-C003-2016-13",
            [
                {
                    "subquestion_id": "QPHY-C003-2016-13-S02",
                    "subquestion_number": "1",
                    "stem_summary": "第一小问",
                }
            ],
            [],
        )

        candidate = result["blockCandidates"][0]
        scope = result["scopes"][1]
        self.assertEqual(candidate["type"], "subquestion")
        self.assertEqual(candidate["stableKey"], "QPHY-C003-2016-13-S02")
        self.assertEqual(candidate["reviewStatus"], "pending_review")
        self.assertFalse(candidate["productionEligible"])
        self.assertEqual(scope["questionBlockRef"], {
            "id": candidate["questionBlockId"],
            "blockType": "subquestion",
            "stableKey": "QPHY-C003-2016-13-S02",
        })
        self.assertEqual(scope["scopeKey"], candidate["scopeKey"])

    def test_punctuated_scoring_summary_stays_at_whole_question_scope(self) -> None:
        result = scopes.normalize_question_scopes(
            "QPHY-C003-2016-21",
            [],
            [{"scoring_point_summary": "列式正确；代入数据正确，结果正确。"}],
        )

        self.assertEqual(len(result["scopes"]), 1)
        self.assertEqual(result["blockCandidates"], [])
        self.assertEqual(result["wholeQuestionScoringSummaryRows"], 1)

    def test_only_explicit_scoring_point_id_creates_scoring_point_scope(self) -> None:
        result = scopes.normalize_question_scopes(
            "QPHY-C003-2016-21",
            [],
            [
                {
                    "scoring_point_id": "SP-QPHY-C003-2016-21-01",
                    "scoring_point_summary": "列式正确",
                }
            ],
        )

        candidate = result["blockCandidates"][0]
        scope = result["scopes"][1]
        self.assertEqual(candidate["type"], "scoring_point")
        self.assertEqual(candidate["reviewStatus"], "pending_review")
        self.assertEqual(scope["scopeType"], "scoring_point")
        self.assertIsNotNone(scope["questionBlockRef"])

    def test_duplicate_block_stable_keys_fail_closed(self) -> None:
        duplicate = {
            "subquestion_id": "QPHY-C003-2016-13-S01",
            "subquestion_number": "1",
            "stem_summary": "第一小问",
        }

        with self.assertRaisesRegex(ValueError, "duplicate_question_block_stable_key"):
            scopes.normalize_question_scopes("QPHY-C003-2016-13", [duplicate, duplicate], [])

    def test_materializer_skips_whole_marker_and_keeps_summary_on_whole_scope(self) -> None:
        candidate = {
            "legacyQuestionId": "QPHY-C003-2016-01",
            "stem": "题干",
            "answer": "D",
            "solution": "步骤一；步骤二。",
            "subquestions": [
                {
                    "subquestion_id": "QPHY-C003-2016-01-S01",
                    "subquestion_number": "whole",
                    "stem_summary": "整题摘要",
                }
            ],
            "scoringRows": [{"scoring_point_summary": "步骤一；步骤二。"}],
        }

        blocks = materialize.build_blocks(candidate, scopes_uuid(1), scopes_uuid(2))

        self.assertNotIn("subquestion", [block["type"] for block in blocks])
        self.assertNotIn("scoring_point", [block["type"] for block in blocks])
        self.assertEqual(blocks[-1]["type"], "answer")
        self.assertTrue(blocks[-1]["content"]["scopeKey"].endswith(":whole_question"))

    def test_materializer_keeps_each_explicit_scoring_point(self) -> None:
        candidate = {
            "legacyQuestionId": "QPHY-C003-2016-21",
            "stem": "题干",
            "answer": "",
            "solution": "",
            "subquestions": [],
            "scoringRows": [
                {"scoring_point_id": "SP-01", "scoring_point_summary": "列式"},
                {"scoring_point_id": "SP-02", "scoring_point_summary": "结果"},
            ],
        }

        blocks = materialize.build_blocks(candidate, scopes_uuid(1), scopes_uuid(2))
        scoring_blocks = [block for block in blocks if block["type"] == "scoring_point"]

        self.assertEqual([block["content"]["stableKey"] for block in scoring_blocks], ["SP-01", "SP-02"])
        self.assertEqual(len({block["content"]["questionBlockId"] for block in scoring_blocks}), 2)


def scopes_uuid(value: int) -> uuid.UUID:
    return uuid.UUID(int=value)


if __name__ == "__main__":
    unittest.main()

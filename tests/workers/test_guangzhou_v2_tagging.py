from __future__ import annotations

import sys
import unittest
from pathlib import Path


TOOLS_ROOT = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS_ROOT))

import guangzhou_physics_v2_tagging as tagging  # noqa: E402


class GuangzhouV2TaggingTests(unittest.TestCase):
    def test_2015_crosswalk_covers_all_24_questions(self) -> None:
        self.assertEqual(set(range(1, 25)), set(tagging.EXAM_POINT_CROSSWALK_2015))
        self.assertTrue(all(tagging.EXAM_POINT_CROSSWALK_2015.values()))

    def test_difficulty_candidate_keeps_observed_and_estimated_scales_separate(self) -> None:
        estimated, candidate = tagging.difficulty_candidate(
            0.8,
            "2018 year report p2",
            {
                "stable_id": "EPHY-C003-001",
                "metadata": {"difficulty_band": "medium-to-hard"},
            },
        )
        self.assertEqual(0.7, estimated)
        self.assertEqual(0.8, candidate["observed"]["value"])
        self.assertEqual(0.2, candidate["observed"]["normalizedHardness"])
        self.assertTrue(candidate["comparison"]["conflictRequiresReview"])
        self.assertEqual("pending_review", candidate["comparison"]["resolutionStatus"])

    def test_split_tokens_accepts_database_lists_and_csv_strings(self) -> None:
        self.assertEqual(["a", "b"], tagging.split_tokens(["a", "b", ""]))
        self.assertEqual(["a", "b"], tagging.split_tokens("a；b"))


if __name__ == "__main__":
    unittest.main()

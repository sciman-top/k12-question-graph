import pathlib
import sys
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOLS_ROOT = REPO_ROOT / "tools"
if str(TOOLS_ROOT) not in sys.path:
    sys.path.insert(0, str(TOOLS_ROOT))

import guangzhou_physics_v2_rebaseline as rebaseline  # noqa: E402


def source_index(year: int, paper: str = "paper", answer: str = "answer", report: str = "report"):
    return {
        (year, "exam_paper"): {paper},
        (year, "answer_solution"): {answer},
        (year, "exam_year_report"): {report},
    }


class RebaselineTests(unittest.TestCase):
    def test_roles_for_distinguishes_combined_and_answer_sources(self) -> None:
        self.assertEqual(rebaseline.roles_for("local_exam_paper", "2020广州中考（含答案）.pdf"), ["exam_paper", "answer_solution"])
        self.assertEqual(rebaseline.roles_for("local_exam_paper", "2025广州中考（解析版）.pdf"), ["answer_solution"])
        self.assertEqual(rebaseline.roles_for("answer_or_solution", "2025广州中考（答案）.pdf"), ["answer_solution"])

    def test_classifies_matched_changed_and_blocked(self) -> None:
        questions = [
            {"question_id": "Q1", "year": "2024", "question_number": "1", "review_status": "pending_review", "production_eligible": "false"},
            {"question_id": "Q2", "year": "2025", "question_number": "1", "review_status": "pending_review", "production_eligible": "false"},
            {"question_id": "Q3", "year": "2026", "question_number": "1", "review_status": "pending_review", "production_eligible": "false"},
        ]
        answers = [{"year": str(year), "question_number": "1"} for year in (2024, 2025, 2026)]
        old_index = source_index(2024) | source_index(2025) | source_index(2026)
        new_index = source_index(2024) | source_index(2025, answer="new-answer")

        rows = rebaseline.classify_questions(questions, answers, old_index, new_index)

        self.assertEqual([row["classification"] for row in rows], ["matched", "changed_pending_review", "blocked"])
        self.assertEqual(rows[1]["changedRoles"], ["answer_solution"])
        self.assertIn("new_missing_exam_paper", rows[2]["blockers"])


if __name__ == "__main__":
    unittest.main()

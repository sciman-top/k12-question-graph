from __future__ import annotations

import sys
import unittest
from pathlib import Path


TOOLS_ROOT = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS_ROOT))

import real005b_question_structure_diagnostics as diagnostics  # noqa: E402


class Real005BQuestionStructureDiagnosticsTests(unittest.TestCase):
    def test_unified_source_smoke_requires_all_234_pending_review_questions(self) -> None:
        report = {
            "status": "pass",
            "workflowKey": diagnostics.REVIEWED_WORKFLOW_KEY,
            "questionCount": 234,
            "pendingReviewQuestionCount": 234,
            "reviewQueueCount": 234,
            "sourceReviewPass": True,
        }

        self.assertTrue(diagnostics.reviewed_source_smoke_covers_workflow(report))

        report["questionCount"] = 210
        self.assertFalse(diagnostics.reviewed_source_smoke_covers_workflow(report))


if __name__ == "__main__":
    unittest.main()

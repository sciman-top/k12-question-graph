from __future__ import annotations

import sys
import unittest
from pathlib import Path

TOOLS_ROOT = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS_ROOT))

import assessment_target_import as importer  # noqa: E402


class AssessmentTargetImportTests(unittest.TestCase):
    def test_rejects_unsafe_or_duplicate_candidate_package(self) -> None:
        package = fixture_package()
        package["governance"]["production_eligible"] = True
        with self.assertRaisesRegex(importer.AssessmentTargetImportError, "unsafe"):
            importer.validate_package(package)

        package = fixture_package()
        package["targets"].append(dict(package["targets"][0]))
        with self.assertRaisesRegex(importer.AssessmentTargetImportError, "duplicate"):
            importer.validate_package(package)

    def test_deterministic_ids_are_stable_and_distinct(self) -> None:
        self.assertEqual(importer.deterministic_id("a"), importer.deterministic_id("a"))
        self.assertNotEqual(importer.deterministic_id("a"), importer.deterministic_id("b"))


def fixture_package() -> dict:
    return {
        "governance": {"status": "candidate", "review_status": "pending_review", "production_eligible": False, "active_write": False},
        "targets": [{"question_scope": {"scope_key": "scope-1"}, "review_status": "pending_review", "production_eligible": False}],
    }


if __name__ == "__main__":
    unittest.main()

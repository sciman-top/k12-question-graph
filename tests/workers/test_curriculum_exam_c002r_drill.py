from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import sys


sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import curriculum_exam_c002r_drill as drill  # noqa: E402


class CurriculumExamC002RDrillTests(unittest.TestCase):
    def test_accepts_only_generated_isolated_database_names(self) -> None:
        drill.validate_isolated_database_name("kqg_cek027_20260731_130000_1234")

        for unsafe in ("k12_question_graph", "kqg_cek027", "kqg_cek027_prod_1"):
            with self.subTest(unsafe=unsafe):
                with self.assertRaisesRegex(ValueError, "refuses a database name"):
                    drill.validate_isolated_database_name(unsafe)

    def test_requires_isolation_marker_and_exact_filestore_shape(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            file_store = Path(root) / "KQG_Data" / "isolated" / "cek027-test" / "file_store"
            file_store.mkdir(parents=True)
            (file_store.parent / ".cek027-isolated").write_text("CEK-27", encoding="ascii")

            with patch.object(Path, "resolve", return_value=Path("D:/KQG_Data/isolated/cek027-test/file_store")):
                with patch.object(Path, "is_file", return_value=True):
                    drill.validate_isolated_file_store(file_store)

    def test_plan_validation_fails_closed(self) -> None:
        valid = {
            "schemaVersion": "cek024-curriculum-exam-c002r-plan.v1",
            "taskId": "CEK-24",
            "status": "pass",
            "readOnly": True,
            "databaseWrite": False,
            "activeWrite": False,
            "planningSnapshotUnchanged": True,
            "candidateCounts": 297,
            "mappingCount": 94,
            "profileCount": 24,
            "productionEligible": False,
            "rollbackRequirements": [{"snapshotRequired": True} for _ in range(6)],
            "historicalReferencePolicy": {"silentRewriteAllowed": False},
        }
        self.assertEqual(drill.validate_plan(valid), [])

        invalid = dict(valid)
        invalid["activeWrite"] = True
        self.assertIn("cek024_candidate_boundary_missing", drill.validate_plan(invalid))

        stale = dict(valid)
        stale["candidateCounts"] = 296
        self.assertIn("cek024_candidate_count_or_production_boundary_mismatch", drill.validate_plan(stale))

    def test_preconditions_require_the_complete_revision_baseline(self) -> None:
        counts = {
            "curriculum_assets": 273,
            "profile_assets": 24,
            "mappings": 94,
            "targets": 444,
            "alignments": 133,
            "migrations": 2,
            "candidate_assets": 297,
            "pending_mappings": 94,
            "pending_targets": 444,
            "pending_alignments": 133,
            "pending_migrations": 2,
            "all_active_assets": 452,
        }
        self.assertEqual(drill.precondition_blockers(counts), [])

        counts["pending_targets"] = 443
        self.assertIn("targets_not_pending", drill.precondition_blockers(counts))

    def test_stage_validators_require_full_review_and_activation(self) -> None:
        reviewed = {
            "reviewed_assets": 297,
            "approved_mappings": 94,
            "reviewed_targets": 444,
            "reviewed_alignments": 133,
            "dry_run_migrations": 2,
            "pending_mappings": 0,
            "pending_targets": 0,
            "pending_alignments": 0,
            "pending_migrations": 0,
            "open_revision_reviews": 0,
        }
        self.assertTrue(drill.reviewed_stage_valid(reviewed))
        reviewed["open_revision_reviews"] = 1
        self.assertFalse(drill.reviewed_stage_valid(reviewed))

        active = {
            "revision_active_assets": 297,
            "all_active_assets": 749,
            "active_targets": 444,
            "active_alignments": 133,
            "approved_mappings": 94,
            "applied_migrations": 2,
        }
        self.assertTrue(drill.active_stage_valid(active))
        active["all_active_assets"] = 748
        self.assertFalse(drill.active_stage_valid(active))

    def test_production_decision_is_always_no_go(self) -> None:
        decision = drill.production_decision()

        self.assertEqual(decision["decision"], "no_go")
        self.assertFalse(decision["productionActiveSwitchAllowed"])
        self.assertIn("real005_not_closed", decision["blockers"])


if __name__ == "__main__":
    unittest.main()

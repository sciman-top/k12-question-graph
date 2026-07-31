from __future__ import annotations

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


TOOLS_ROOT = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS_ROOT))

import import_c002_candidate_assets as candidate_import  # noqa: E402


class RegionalExamProfileImportTests(unittest.TestCase):
    def test_builds_candidate_exam_point_asset_with_traceability(self) -> None:
        assets = candidate_import.build_regional_profile_assets(profile_package())

        self.assertEqual(len(assets), 1)
        asset = assets[0]
        self.assertEqual(asset["asset_type"], "exam_point")
        self.assertEqual(asset["status"], "candidate")
        self.assertEqual(asset["metadata"]["semantic_type"], "RegionalExamPointProfile")
        self.assertEqual(asset["metadata"]["review_status"], "pending_review")
        self.assertFalse(asset["metadata"]["production_eligible"])
        self.assertEqual(asset["source_evidence"]["evidenceTargetIds"], [TARGET_ID])
        self.assertEqual(asset["source_evidence"]["traceability"]["anchorRoles"], ["answer", "paper", "report"])

    def test_rejects_profile_that_is_not_candidate_safe(self) -> None:
        package = profile_package()
        package["profiles"][0]["profile"]["production_eligible"] = True

        with self.assertRaisesRegex(ValueError, "candidate-safe"):
            candidate_import.build_regional_profile_assets(package)

    def test_rejects_trend_claim_with_fewer_than_three_occurrence_years(self) -> None:
        package = profile_package()
        package["profiles"][0]["profile"]["trend"]["status"] = "rising"
        package["profiles"][0]["diagnostics"]["occurrenceYears"] = [2024]

        with self.assertRaisesRegex(ValueError, "trend requires at least three"):
            candidate_import.build_regional_profile_assets(package)

    def test_rejects_declared_anchor_roles_without_matching_anchors(self) -> None:
        package = profile_package()
        package["profiles"][0]["traceability"]["anchors"] = [
            {"role": "paper", "sourceRegionId": "30000000-0000-0000-0000-000000000001"}
        ]

        with self.assertRaisesRegex(ValueError, "traceability anchors incomplete"):
            candidate_import.build_regional_profile_assets(package)

    def test_rejects_invalid_evidence_target_id(self) -> None:
        package = profile_package()
        package["profiles"][0]["traceability"]["assessmentTargetIds"] = ["not-a-uuid"]

        with self.assertRaisesRegex(ValueError, "evidence target ids invalid"):
            candidate_import.build_regional_profile_assets(package)

    def test_migration_upsert_binds_created_by_parameter(self) -> None:
        connection = PlaceholderCheckingConnection()

        migration_id = candidate_import.upsert_migration(
            connection,
            {"assets": 1},
            "D:/KQG_Backups/fixture/manifest.json",
            import_key=candidate_import.REGIONAL_PROFILE_IMPORT_KEY,
            created_by="regional_exam_profile_import",
        )

        self.assertEqual(migration_id, "00000000-0000-0000-0000-000000000099")

    def test_apply_verifies_backup_before_any_database_query(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            package_path = root / "profiles.json"
            package_path.write_text(json.dumps(profile_package()), encoding="utf-8")
            report_path = root / "report.json"
            manifest_path = root / "manifest.json"
            manifest_path.write_text("{}", encoding="utf-8")
            connection = NoQueryConnection()

            with mock.patch.object(
                candidate_import,
                "verify_backup_manifest",
                side_effect=ValueError("backup verification failed"),
            ) as verifier:
                with self.assertRaisesRegex(ValueError, "backup verification failed"):
                    candidate_import.run_regional_profile_import(
                        connection,
                        package_path,
                        report_path,
                        str(manifest_path),
                        apply=True,
                    )

            verifier.assert_called_once_with(manifest_path)
            self.assertEqual(connection.execute_count, 0)

    def test_regional_upsert_uses_atomic_import_key_guard(self) -> None:
        connection = GuardCheckingConnection()
        asset = candidate_import.build_regional_profile_assets(profile_package())[0]

        ids = candidate_import.upsert_assets(
            connection,
            [asset],
            conflict_import_key=candidate_import.REGIONAL_PROFILE_IMPORT_KEY,
        )

        self.assertEqual(ids[("exam_point", "EPHY-GUANGZHOU-FIXTURE")], "00000000-0000-0000-0000-000000000099")
        self.assertIn("domain_asset_versions.status = 'candidate'", connection.query)
        self.assertIn("source_evidence->>'importKey' = %s", connection.query)
        self.assertEqual(connection.parameters[-1], candidate_import.REGIONAL_PROFILE_IMPORT_KEY)


class PlaceholderCheckingConnection:
    def execute(self, query: str, parameters: tuple) -> "PlaceholderCheckingCursor":
        if query.count("%s") != len(parameters):
            raise AssertionError("SQL placeholder and parameter counts differ")
        return PlaceholderCheckingCursor()


class PlaceholderCheckingCursor:
    def fetchone(self) -> dict[str, str]:
        return {"id": "00000000-0000-0000-0000-000000000099"}


class NoQueryConnection:
    def __init__(self) -> None:
        self.execute_count = 0

    def execute(self, *_args, **_kwargs):
        self.execute_count += 1
        raise AssertionError("database must not be queried before backup verification")


class GuardCheckingConnection:
    def __init__(self) -> None:
        self.query = ""
        self.parameters: tuple = ()

    def execute(self, query: str, parameters: tuple) -> PlaceholderCheckingCursor:
        self.query = query
        self.parameters = parameters
        if query.count("%s") != len(parameters):
            raise AssertionError("SQL placeholder and parameter counts differ")
        return PlaceholderCheckingCursor()


TARGET_ID = "10000000-0000-0000-0000-000000000001"


def profile_package() -> dict:
    profile = {
        "schema_version": "regional-exam-point-profile.v1",
        "semantic_type": "RegionalExamPointProfile",
        "storage_asset_type": "exam_point",
        "stable_id": "EPHY-GUANGZHOU-FIXTURE",
        "region": "guangzhou",
        "subject": "physics",
        "stage": "junior_middle_school",
        "year_range": {
            "start_year": 2021,
            "end_year": 2024,
            "comparable_exam_years": [2021, 2022, 2023, 2024],
        },
        "standard_regime": {
            "regime_id": "historical",
            "regime_type": "single_standard",
            "standard_versions": ["historical"],
            "exam_years": [2021, 2022, 2023, 2024],
            "interpretation_guard": "descriptive only",
        },
        "knowledge_stable_ids": ["KPHY-FIXTURE-001"],
        "frequency_weight": {
            "numerator_occurrences": 3,
            "denominator_comparable_exam_papers": 4,
            "value": 0.75,
            "comparable_exam_years": [2021, 2022, 2023, 2024],
            "evidence_target_ids": [TARGET_ID],
        },
        "score_weight": {
            "numerator_profile_score": 9,
            "denominator_total_exam_score": 360,
            "value": 0.025,
            "comparable_exam_years": [2021, 2022, 2023, 2024],
            "evidence_target_ids": [TARGET_ID],
        },
        "difficulty_distribution": {
            "direction": "higher_is_easier",
            "denominator_observed_items": 1,
            "buckets": [{"label": "easy", "count": 1}],
            "comparable_exam_years": [2024],
            "evidence_target_ids": [TARGET_ID],
        },
        "trend": {
            "status": "stable",
            "minimum_comparable_years": 3,
            "comparable_exam_years": [2021, 2022, 2023, 2024],
            "evidence_target_ids": [TARGET_ID],
        },
        "version": 1,
        "status": "candidate",
        "review_status": "pending_review",
        "production_eligible": False,
    }
    return {
        "status": "pass",
        "taskId": "CEK-22",
        "checkedAt": "2026-07-30T22:00:00+08:00",
        "profiles": [
            {
                "profile": copy.deepcopy(profile),
                "diagnostics": {
                    "windowId": "recent_comparable",
                    "sourceState": "explicit_candidate",
                    "occurrenceYears": [2022, 2023, 2024],
                },
                "traceability": {
                    "assessmentTargetIds": [TARGET_ID],
                    "questionItemIds": ["20000000-0000-0000-0000-000000000001"],
                    "anchorRoles": ["answer", "paper", "report"],
                    "anchors": [
                        {"role": "paper", "sourceRegionId": "30000000-0000-0000-0000-000000000001"},
                        {"role": "answer", "sourceRegionId": "30000000-0000-0000-0000-000000000002"},
                        {"role": "report", "sourceRegionId": "30000000-0000-0000-0000-000000000003"},
                    ],
                },
            }
        ],
    }


if __name__ == "__main__":
    unittest.main()

from __future__ import annotations

import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import curriculum_exam_c002r_plan as planner  # noqa: E402


class CurriculumExamC002RPlanTests(unittest.TestCase):
    def test_candidate_is_based_on_active_without_in_place_edit(self) -> None:
        plan = planner.build_plan(snapshot(), cek20(), cek23())

        self.assertEqual(plan["candidateVersion"]["basedOnActiveVersion"], "c002-active-v1")
        self.assertTrue(plan["candidateVersion"]["noInPlaceActiveEdit"])
        self.assertTrue(plan["noActiveWrite"])

    def test_routes_risk_and_unmaterialized_sources_to_review_groups(self) -> None:
        plan = planner.build_plan(snapshot(), cek20(), cek23())
        groups = {item["groupId"]: item for item in plan["reviewGroups"]}

        self.assertEqual(groups["complex_mappings"]["itemCount"], 2)
        self.assertEqual(groups["low_confidence_mappings"]["itemCount"], 1)
        self.assertEqual(groups["regional_profiles"]["itemCount"], 2)
        self.assertEqual(groups["error_patterns"]["status"], "blocked_no_persisted_candidates")

    def test_all_impacts_have_unique_rollback_keys(self) -> None:
        plan = planner.build_plan(snapshot(), cek20(), cek23())
        impacts = plan["impactReport"]["impacts"]
        keys = [item["rollbackKey"] for item in impacts]

        self.assertEqual(
            {item["impactType"] for item in impacts},
            {"question_binding", "paper_blueprint", "search_index", "analysis_metric", "export_template", "score_import_template"},
        )
        self.assertEqual(len(keys), len(set(keys)))
        self.assertTrue(all(item["requiresRollbackSnapshot"] for item in impacts))

    def test_historical_references_are_frozen_without_silent_rewrite(self) -> None:
        plan = planner.build_plan(snapshot(), cek20(), cek23())

        self.assertFalse(plan["historicalReferencePolicy"]["silentRewriteAllowed"])
        self.assertEqual(plan["historicalReferencePolicy"]["analysisAction"], "freeze_historical_snapshot")
        self.assertEqual(plan["historicalReferencePolicy"]["questionListAction"], "preserve_version_binding")

    def test_rejects_failed_upstream_evidence(self) -> None:
        failed = cek23()
        failed["status"] = "blocked"

        with self.assertRaisesRegex(ValueError, "passing CEK-20 and CEK-23"):
            planner.build_plan(snapshot(), cek20(), failed)

    def test_rejects_non_candidate_or_stale_cek23_evidence(self) -> None:
        unsafe = cek23()
        unsafe["governance"]["candidateOnly"] = False
        with self.assertRaisesRegex(ValueError, "candidate-only CEK-23"):
            planner.build_plan(snapshot(), cek20(), unsafe)

        stale = cek23()
        stale["import"]["counts"]["profileAssets"] = 1
        with self.assertRaisesRegex(ValueError, "profile count does not match"):
            planner.build_plan(snapshot(), cek20(), stale)

    def test_rejects_cek20_without_c002r_impact_requirement(self) -> None:
        unsafe = cek20()
        unsafe["governance"]["requiresC002RImpactReport"] = False

        with self.assertRaisesRegex(ValueError, "C002R impact report"):
            planner.build_plan(snapshot(), unsafe, cek23())


def snapshot() -> dict:
    return {
        "activeBaseline": {"status": "active", "activeImportKey": "c002-import", "activeVersionLabel": "c002-active-v1", "activeAssetCount": 452, "fingerprint": "active-hash"},
        "candidateAssets": {"curriculum": 273, "profiles": 2},
        "mappings": [
            {"mappingId": "M1", "mappingType": "broader", "fromStableId": "C1", "toStableId": "K1", "confidence": 0.88},
            {"mappingId": "M2", "mappingType": "narrower", "fromStableId": "C2", "toStableId": "K2", "confidence": 0.84},
            {"mappingId": "M3", "mappingType": "equivalent", "fromStableId": "C3", "toStableId": "K3", "confidence": 0.95},
        ],
        "profileSummaries": [
            {"stableId": "P1", "regimeType": "transition", "trendStatus": "insufficient_evidence"},
            {"stableId": "P2", "regimeType": "single_standard", "trendStatus": "stable"},
        ],
        "references": {"questionBindings": 234, "paperBlueprints": 3, "searchAssets": 452, "analyses": 4, "exports": 5, "scoreTemplates": 6},
        "questionFingerprint": "question-hash",
    }


def cek20() -> dict:
    return {"status": "pass", "governance": {"databaseWrite": False, "requiresC002RImpactReport": True}}


def cek23() -> dict:
    return {"status": "pass", "import": {"counts": {"profileAssets": 2}}, "governance": {"candidateOnly": True}}


if __name__ == "__main__":
    unittest.main()

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "tools" / "curriculum_candidate_import.py"
SPEC = importlib.util.spec_from_file_location("curriculum_candidate_import", MODULE_PATH)
assert SPEC and SPEC.loader
module = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = module
SPEC.loader.exec_module(module)


ANCHOR = {"text_block_sha256": "a" * 64, "source_document_id": "doc-1"}


def requirement_envelope() -> dict:
    facet = {
        "record_type": "requirement_facet",
        "stable_id": "CR-1-F01",
        "parent_requirement_stable_id": "CR-1",
        "facet_statement": "描述欧姆定律",
        "content_object": "欧姆定律",
        "confidence": 0.92,
        "status": "candidate",
        "review_status": "pending_review",
        "production_eligible": False,
        "evidence_anchors": [ANCHOR],
    }
    return {
        "governance": {
            "status": "candidate",
            "review_status": "pending_review",
            "production_eligible": False,
            "c002_active_write": False,
        },
        "requirements": [{
            "parent_requirement_stable_id": "CR-1",
            "official_item_code": "1.1.1",
            "source_text_sha256": "b" * 64,
            "source_anchor_sha256s": ["a" * 64],
            "facets": [{"facet": facet}],
        }],
    }


def crosswalk() -> dict:
    return {
        "governance": {
            "status": "candidate",
            "review_status": "pending_review",
            "production_eligible": False,
            "database_write": False,
            "c002_active_write": False,
        },
        "mappings": [{
            "mapping_id": "MAP-1",
            "source_stable_id": "CR-1-F01",
            "target_knowledge_code": "KPHY-1",
            "mapping_type": "equivalent",
            "confidence": 0.92,
            "evidence_anchor_sha256": "a" * 64,
            "review_status": "pending_review",
            "auto_apply_allowed": False,
            "rollback_required": True,
        }],
        "knowledge_candidates": [],
    }


class CurriculumCandidateImportTests(unittest.TestCase):
    def test_builds_canonical_parent_and_facet_assets_with_legacy_alias(self) -> None:
        package = module.build_package(requirement_envelope(), crosswalk())

        self.assertEqual([a["asset_type"] for a in package["assets"]], ["curriculum_requirement", "requirement_facet"])
        for asset in package["assets"]:
            self.assertEqual(asset["status"], "candidate")
            self.assertEqual(asset["source_evidence"]["reviewStatus"], "pending_review")
            self.assertFalse(asset["source_evidence"]["productionEligible"])
            self.assertTrue(asset["source_evidence"]["anchorSha256s"])
            self.assertEqual(asset["metadata"]["legacyAssetType"], "curriculum_standard_item")

    def test_mapping_references_facet_and_active_knowledge_stable_id(self) -> None:
        package = module.build_package(requirement_envelope(), crosswalk())
        mapping = package["mappings"][0]

        self.assertEqual(mapping["source_key"], ("requirement_facet", "CR-1-F01"))
        self.assertEqual(mapping["target_key"], ("knowledge_point", "KPHY-1"))
        self.assertEqual(mapping["review_status"], "pending_review")
        self.assertTrue(mapping["rollback_required"])

    def test_rejects_unsafe_envelopes_and_detached_mapping(self) -> None:
        unsafe = requirement_envelope()
        unsafe["governance"]["production_eligible"] = True
        with self.assertRaisesRegex(module.CurriculumImportError, "safe candidate"):
            module.build_package(unsafe, crosswalk())

        detached = crosswalk()
        detached["mappings"][0]["source_stable_id"] = "MISSING"
        with self.assertRaisesRegex(module.CurriculumImportError, "unknown facet"):
            module.build_package(requirement_envelope(), detached)


if __name__ == "__main__":
    unittest.main()

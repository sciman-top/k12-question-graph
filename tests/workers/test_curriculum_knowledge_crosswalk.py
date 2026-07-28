from __future__ import annotations

import copy
import importlib.util
import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "tools" / "curriculum_knowledge_crosswalk.py"
SPEC = importlib.util.spec_from_file_location("curriculum_knowledge_crosswalk", MODULE_PATH)
assert SPEC and SPEC.loader
crosswalk = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = crosswalk
SPEC.loader.exec_module(crosswalk)


def node(code: str, title: str, aliases: list[str] | None = None) -> dict:
    return {
        "code": code,
        "title": title,
        "level": 3,
        "nodeType": "concept",
        "parentCode": "PHY-JH-TEST",
        "aliases": aliases or [],
    }


def facet(
    stable_id: str,
    content: str,
    *,
    confidence: float = 0.92,
    parent: str = "CR-TEST-1",
) -> dict:
    return {
        "facet": {
            "record_type": "requirement_facet",
            "stable_id": stable_id,
            "parent_requirement_stable_id": parent,
            "official_item_code": "1.1.1",
            "facet_statement": f"描述{content}",
            "behavior_verb": "描述",
            "content_object": content,
            "confidence": confidence,
            "status": "candidate",
            "review_status": "pending_review",
            "production_eligible": False,
            "evidence_anchors": [{"text_block_sha256": "a" * 64}],
        },
        "review": {"reasons": []},
    }


def envelope(items: list[dict]) -> dict:
    return {
        "schema_version": "curriculum-requirement-extraction.v1",
        "governance": {
            "status": "candidate",
            "review_status": "pending_review",
            "production_eligible": False,
            "knowledge_asset_write": False,
            "c002_active_write": False,
        },
        "requirements": [
            {
                "parent_requirement_stable_id": "CR-TEST-1",
                "official_item_code": "1.1.1",
                "facets": items,
            }
        ],
    }


class CurriculumKnowledgeCrosswalkTests(unittest.TestCase):
    def test_schema_definitions_preserve_question_contract_and_lock_asset_enums(self) -> None:
        schema = json.loads(
            (ROOT / "schemas" / "ai" / "knowledge_mapping.schema.json").read_text(
                encoding="utf-8"
            )
        )

        self.assertIn("prerequisite", schema["properties"]["suggestions"]["items"]["properties"]["mapping_type"]["enum"])
        asset_types = schema["$defs"]["curriculum_asset_mapping"]["properties"]["mapping_type"]["enum"]
        self.assertEqual(asset_types, ["equivalent", "broader", "narrower"])
        self.assertNotIn("prerequisite", asset_types)

    def test_exact_title_and_alias_matches_use_only_asset_scope_types(self) -> None:
        source = envelope(
            [
                facet("CR-TEST-1-F01", "欧姆定律"),
                facet("CR-TEST-1-F02", "串并联"),
            ]
        )
        knowledge = {
            "seedId": "C002_TEST",
            "nodes": [
                node("PHY-OHM", "欧姆定律"),
                node("PHY-CIRCUIT", "串联与并联电路", ["串并联"]),
            ],
        }

        result = crosswalk.build_crosswalk(source, knowledge)

        self.assertEqual(len(result["mappings"]), 2)
        self.assertEqual(
            {item["mapping_type"] for item in result["mappings"]}, {"equivalent"}
        )
        self.assertEqual(
            {item["match_basis"] for item in result["mappings"]},
            {"title_exact", "alias_exact"},
        )
        self.assertEqual(result["knowledge_candidates"], [])

    def test_containment_direction_is_explicit_and_never_prerequisite(self) -> None:
        source = envelope(
            [
                facet("CR-TEST-1-F01", "欧姆定律及其应用"),
                facet("CR-TEST-1-F02", "浮力"),
            ]
        )
        knowledge = {
            "seedId": "C002_TEST",
            "nodes": [
                node("PHY-OHM", "欧姆定律"),
                node("PHY-BUOYANCY", "浮力与阿基米德原理"),
            ],
        }

        result = crosswalk.build_crosswalk(source, knowledge)
        by_source = {item["source_stable_id"]: item for item in result["mappings"]}

        self.assertEqual(by_source["CR-TEST-1-F01"]["mapping_type"], "broader")
        self.assertEqual(by_source["CR-TEST-1-F02"]["mapping_type"], "narrower")
        self.assertNotIn("prerequisite", json.dumps(result, ensure_ascii=False))

    def test_unmatched_facet_only_creates_non_production_knowledge_candidate(self) -> None:
        result = crosswalk.build_crosswalk(
            envelope([facet("CR-TEST-1-F01", "量子彩虹装置")]),
            {"seedId": "C002_TEST", "nodes": [node("PHY-OHM", "欧姆定律")]},
        )

        self.assertEqual(result["mappings"], [])
        candidate = result["knowledge_candidates"][0]
        self.assertEqual(candidate["status"], "candidate")
        self.assertEqual(candidate["review_status"], "pending_review")
        self.assertFalse(candidate["production_eligible"])
        self.assertFalse(result["governance"]["knowledge_node_write"])
        self.assertFalse(result["governance"]["c002_active_write"])

    def test_active_domain_asset_snapshot_records_read_only_database_access(self) -> None:
        knowledge = {
            "seedId": "C002_ACTIVE_DOMAIN_ASSETS",
            "source": "domain_asset_versions",
            "status": "active",
            "nodes": [node("KPHY-ACTIVE-001", "欧姆定律")],
        }

        result = crosswalk.build_crosswalk(
            envelope([facet("CR-TEST-1-F01", "欧姆定律")]), knowledge
        )

        self.assertTrue(result["governance"]["database_read"])
        self.assertFalse(result["governance"]["database_write"])
        self.assertEqual(result["knowledge_snapshot"]["source"], "domain_asset_versions")
        self.assertEqual(result["knowledge_snapshot"]["status"], "active")

    def test_many_to_many_and_low_confidence_are_high_priority_with_rollback(self) -> None:
        source = envelope(
            [
                facet("CR-TEST-1-F01", "欧姆定律和电功率", confidence=0.70),
                facet("CR-TEST-1-F02", "欧姆定律应用"),
            ]
        )
        knowledge = {
            "seedId": "C002_TEST",
            "nodes": [node("PHY-OHM", "欧姆定律"), node("PHY-POWER", "电功率")],
        }

        result = crosswalk.build_crosswalk(source, knowledge)

        self.assertGreaterEqual(len(result["mappings"]), 3)
        for mapping in result["mappings"]:
            self.assertEqual(mapping["review_status"], "pending_review")
            self.assertFalse(mapping["auto_apply_allowed"])
            self.assertTrue(mapping["rollback_required"])
        high = [item for item in result["review_queue"] if item["priority"] == "high"]
        self.assertTrue(high)
        reasons = {reason for item in high for reason in item["reasons"]}
        self.assertTrue({"one_to_many", "many_to_one", "low_confidence"} <= reasons)

    def test_output_is_deterministic_and_does_not_mutate_inputs(self) -> None:
        source = envelope([facet("CR-TEST-1-F01", "欧姆定律")])
        knowledge = {"seedId": "C002_TEST", "nodes": [node("PHY-OHM", "欧姆定律")]}
        before_source = copy.deepcopy(source)
        before_knowledge = copy.deepcopy(knowledge)

        first = crosswalk.build_crosswalk(source, knowledge)
        second = crosswalk.build_crosswalk(source, knowledge)

        self.assertEqual(first, second)
        self.assertEqual(source, before_source)
        self.assertEqual(knowledge, before_knowledge)
        crosswalk.validate_crosswalk(first)
        first["warnings"].append("drift")
        with self.assertRaisesRegex(crosswalk.CrosswalkError, "hash mismatch"):
            crosswalk.validate_crosswalk(first)

    def test_rejects_unsafe_inputs_and_duplicate_stable_ids(self) -> None:
        unsafe = envelope([facet("CR-TEST-1-F01", "欧姆定律")])
        unsafe["governance"]["c002_active_write"] = True
        with self.assertRaisesRegex(crosswalk.CrosswalkError, "safe candidate"):
            crosswalk.build_crosswalk(unsafe, {"seedId": "C002_TEST", "nodes": []})

        duplicate = envelope(
            [facet("CR-TEST-1-F01", "甲"), facet("CR-TEST-1-F01", "乙")]
        )
        with self.assertRaisesRegex(crosswalk.CrosswalkError, "duplicate facet"):
            crosswalk.build_crosswalk(duplicate, {"seedId": "C002_TEST", "nodes": []})


if __name__ == "__main__":
    unittest.main()

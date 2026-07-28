import copy
import json
import pathlib
import sys
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOLS_ROOT = REPO_ROOT / "tools"
EVAL_SUITE_PATH = (
    REPO_ROOT
    / "configs"
    / "ai-evals"
    / "curriculum-requirement-extraction.sample.json"
)
if str(TOOLS_ROOT) not in sys.path:
    sys.path.insert(0, str(TOOLS_ROOT))

import curriculum_requirement_facets as facets  # noqa: E402


ANCHOR_HASH = "1" * 64


def source_requirement(source_text: str) -> dict:
    return {
        "schema_version": "curriculum-requirement.v1",
        "record_type": "curriculum_requirement",
        "stable_id": "CR-PHY-JM-SYNTHETIC-1.1.1",
        "parent_stable_id": "CS-PHY-JM-SYNTHETIC-1.1",
        "standard_version": "synthetic-v1",
        "official_item_code": "1.1.1",
        "requirement_type": "content_requirement",
        "source_text": source_text,
        "behavior_verbs": [],
        "cognitive_demands": [],
        "ability_dimensions": [],
        "knowledge_stable_ids": [],
        "evidence_anchors": [
            {
                "source_document_id": "00000000-0000-0000-0000-000000000001",
                "source_region_id": None,
                "source_document_version": "synthetic-v1",
                "source_document_sha256": "a" * 64,
                "pdf_page_number": 1,
                "printed_page_number": 1,
                "section_path": ["synthetic", "1.1.1"],
                "official_item_code": "1.1.1",
                "text_block_sha256": ANCHOR_HASH,
                "evidence_role": "curriculum_requirement_source",
            }
        ],
        "confidence": 0.95,
        "status": "candidate",
        "review_status": "pending_review",
        "production_eligible": False,
        "facets": [],
    }


def source_candidate(*requirements: dict) -> dict:
    return {
        "schema_version": "curriculum-standard-structure.v1",
        "extraction": {
            "status": "pass",
            "manual_takeover_required": False,
        },
        "curriculum_requirements": list(requirements),
    }


class CurriculumRequirementFacetTests(unittest.TestCase):
    def test_composite_requirement_splits_and_retains_parent_anchor(self) -> None:
        requirement = source_requirement(
            "经历探究过程，知道现象甲，了解规律乙。能运用规律乙解释现象丙。"
        )

        result = facets.extract_requirement(requirement)

        self.assertTrue(result["composite"])
        self.assertEqual(len(result["facets"]), 4)
        self.assertEqual(
            [item["facet"]["behavior_verb"] for item in result["facets"]],
            ["经历", "知道", "了解", "解释"],
        )
        for item in result["facets"]:
            facet = item["facet"]
            self.assertEqual(
                facet["parent_requirement_stable_id"], requirement["stable_id"]
            )
            self.assertEqual(
                facet["evidence_anchors"][0]["text_block_sha256"], ANCHOR_HASH
            )
            self.assertEqual(
                facet["evidence_anchors"][0]["evidence_role"],
                "curriculum_facet_source",
            )
            self.assertIn("multiple_facets", item["review"]["reasons"])

    def test_shared_object_compound_splits_and_routes_high_priority(self) -> None:
        result = facets.extract_requirement(source_requirement("会看、会画简单的电路图。"))

        self.assertEqual(len(result["facets"]), 2)
        self.assertEqual(
            [item["facet"]["behavior_verb"] for item in result["facets"]],
            ["识读", "绘制"],
        )
        self.assertEqual(
            {item["facet"]["content_object"] for item in result["facets"]},
            {"简单的电路图"},
        )
        for item in result["facets"]:
            self.assertLess(item["facet"]["confidence"], facets.REVIEW_THRESHOLD)
            self.assertEqual(item["review"]["priority"], "high")
            self.assertIn("low_confidence", item["review"]["reasons"])
            self.assertIn("compound_behavior", item["review"]["reasons"])

    def test_unknown_behavior_fails_closed_to_blocked_review(self) -> None:
        candidate = source_candidate(
            source_requirement("物理量甲与物理量乙之间存在某种关系。")
        )

        envelope = facets.build_rule_envelope(candidate)
        result = envelope["requirements"][0]

        self.assertEqual(result["facets"], [])
        self.assertEqual(result["unresolved_reasons"], ["missing_behavior_verb"])
        unresolved = envelope["review_queue"][0]
        self.assertIsNone(unresolved["facet_stable_id"])
        self.assertEqual(unresolved["priority"], "blocked")

    def test_explicit_tool_and_imperative_measurement_clauses_are_parsed(self) -> None:
        requirement = source_requirement(
            "用刻度尺测量长度，用表测量时间。能发现现象甲，并能进行简单计算。"
        )

        result = facets.extract_requirement(requirement)

        self.assertEqual(result["unresolved_reasons"], [])
        self.assertEqual(
            [item["facet"]["behavior_verb"] for item in result["facets"]],
            ["测量", "测量", "发现", "计算"],
        )
        self.assertEqual(
            [item["facet"]["condition_or_performance"] for item in result["facets"][:2]],
            ["使用刻度尺", "使用表"],
        )
        self.assertIn("low_confidence", result["facets"][-1]["review"]["reasons"])

    def test_safe_governance_condition_and_field_provenance(self) -> None:
        envelope = facets.build_rule_envelope(
            source_candidate(source_requirement("通过实验，认识物理量甲。"))
        )
        candidate = envelope["requirements"][0]["facets"][0]
        facet = candidate["facet"]

        self.assertEqual(facet["condition_or_performance"], "通过实验")
        self.assertEqual(facet["behavior_verb"], "认识")
        self.assertEqual(facet["content_object"], "物理量甲")
        self.assertTrue(facet["cognitive_demands"][0].endswith("-RECOGNIZE"))
        self.assertEqual(facet["ability_dimensions"], [])
        self.assertEqual(facet["status"], "candidate")
        self.assertEqual(facet["review_status"], "pending_review")
        self.assertFalse(facet["production_eligible"])
        self.assertEqual(
            {item["field"] for item in candidate["field_provenance"]},
            {
                "facet_statement",
                "behavior_verb",
                "content_object",
                "condition_or_performance",
                "cognitive_demands",
                "ability_dimensions",
            },
        )
        self.assertEqual(envelope["generation"]["external_model_calls"], 0)
        self.assertIsNone(envelope["generation"]["model"])
        self.assertFalse(envelope["governance"]["database_write"])

    def test_output_trace_is_deterministic_and_detects_drift(self) -> None:
        candidate = source_candidate(source_requirement("知道物理量甲。"))

        first = facets.build_rule_envelope(candidate)
        second = facets.build_rule_envelope(candidate)

        self.assertEqual(first, second)
        facets.validate_envelope_trace(first)
        first["warnings"].append("drift")
        with self.assertRaisesRegex(facets.FacetExtractionError, "hash mismatch"):
            facets.validate_envelope_trace(first)

    def test_source_requirement_is_not_mutated(self) -> None:
        requirement = source_requirement("知道物理量甲。了解规律乙。")
        before = copy.deepcopy(requirement)

        facets.build_rule_envelope(source_candidate(requirement))

        self.assertEqual(requirement, before)

    def test_hydrates_offline_ai_case_with_trace_and_review_metadata(self) -> None:
        suite = json.loads(EVAL_SUITE_PATH.read_text(encoding="utf-8"))

        hydrated = facets.hydrate_eval_suite(suite)
        output = hydrated["cases"][0]["output"]

        self.assertFalse(hydrated["allow_real_model_calls"])
        self.assertEqual(output["generation"]["method"], "ai")
        self.assertEqual(output["generation"]["external_model_calls"], 0)
        self.assertRegex(output["generation"]["input_sha256"], r"^[0-9a-f]{64}$")
        self.assertRegex(output["generation"]["output_sha256"], r"^[0-9a-f]{64}$")
        reasons = output["requirements"][0]["facets"][0]["review"]["reasons"]
        self.assertIn("low_confidence", reasons)
        self.assertIn("ai_generated", reasons)
        facets.validate_envelope_trace(output)
        output["requirements"][0]["facets"][0]["field_provenance"][0][
            "generation_method"
        ] = "rules"
        output["generation"]["output_sha256"] = facets.sha256_json(
            facets.output_payload(output)
        )
        with self.assertRaisesRegex(
            facets.FacetExtractionError, "generation method differs"
        ):
            facets.validate_envelope_trace(output)

    def test_rejects_unsafe_source_candidate(self) -> None:
        requirement = source_requirement("知道物理量甲。")
        requirement["production_eligible"] = True

        with self.assertRaisesRegex(facets.FacetExtractionError, "not a safe candidate"):
            facets.build_rule_envelope(source_candidate(requirement))


if __name__ == "__main__":
    unittest.main()

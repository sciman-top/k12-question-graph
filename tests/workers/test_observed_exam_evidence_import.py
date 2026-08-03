from __future__ import annotations

import sys
import unittest
from pathlib import Path

TOOLS_ROOT = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS_ROOT))

import observed_exam_evidence_import as importer  # noqa: E402


class ObservedExamEvidenceImportTests(unittest.TestCase):
    def test_rejects_unsafe_or_duplicate_package(self) -> None:
        package = fixture_package()
        package["governance"]["production_eligible"] = True
        with self.assertRaisesRegex(importer.ObservedExamEvidenceImportError, "unsafe"):
            importer.validate_package(package)

        package = fixture_package()
        package["observed_errors"].append(dict(package["observed_errors"][0]))
        with self.assertRaisesRegex(importer.ObservedExamEvidenceImportError, "duplicate"):
            importer.validate_package(package)

    def test_rejects_missing_source_region(self) -> None:
        package = fixture_package()
        package["observed_performance"][0]["difficulty_observed"]["anchor"]["source_region_id"] = None
        with self.assertRaisesRegex(importer.ObservedExamEvidenceImportError, "source region"):
            importer.validate_package(package)

    def test_normalizes_percent_metric_and_preserves_ratio(self) -> None:
        self.assertEqual(importer.metric_ratio({"unit": "percent", "parsed_value": 62.5}), 0.625)
        self.assertEqual(importer.metric_ratio({"unit": "ratio", "parsed_value": 0.625}), 0.625)

    def test_performance_anchor_uses_first_present_metric(self) -> None:
        row = fixture_package()["observed_performance"][0]
        self.assertEqual(importer.performance_anchor(row)["source_region_id"], "22222222-2222-4222-8222-222222222222")

    def test_deterministic_ids_are_stable_and_distinct(self) -> None:
        self.assertEqual(importer.deterministic_id("a"), importer.deterministic_id("a"))
        self.assertNotEqual(importer.deterministic_id("a"), importer.deterministic_id("b"))

    def test_rejects_overwrite_of_reviewed_evidence(self) -> None:
        with self.assertRaisesRegex(importer.ObservedExamEvidenceImportError, "overwrite blocked"):
            importer._reject_reviewed_overwrites(ReviewedEvidenceConnection(), fixture_package())


class ReviewedEvidenceConnection:
    def execute(self, query: str, params: object) -> "ReviewedEvidenceConnection":
        self._rows = (
            [{"stable_key": "observed-performance:44444444-4444-4444-8444-444444444444"}]
            if "from observed_performance_evidence" in query
            else []
        )
        return self

    def fetchall(self) -> list[dict[str, str]]:
        return self._rows


def fixture_package() -> dict:
    anchor = {
        "source_document_id": "11111111-1111-4111-8111-111111111111",
        "source_region_id": "22222222-2222-4222-8222-222222222222",
        "source_document_version": "sha256:abc",
        "source_document_sha256": "a" * 64,
        "pdf_page_number": 1,
        "printed_page_number": None,
        "section_path": ["test"],
        "official_item_code": "QPHY-C003-2025-01",
        "text_block_sha256": "b" * 64,
        "evidence_role": "performance_statistic_source",
    }
    scope = {
        "scope_key": "question-scope:v1:33333333-3333-4333-8333-333333333333:whole_question",
        "scope_type": "whole_question",
        "question_item_id": "33333333-3333-4333-8333-333333333333",
        "question_block_id": None,
    }
    metric = {
        "raw_value": "0.625",
        "parsed_value": 0.625,
        "unit": "ratio",
        "scale_direction": "higher_is_easier",
        "sample_scope": "report cohort",
        "sample_size": None,
        "anchor": anchor,
    }
    error_anchor = dict(anchor, evidence_role="error_observation_source")
    recommendation_anchor = dict(anchor, evidence_role="teaching_recommendation_source")
    return {
        "governance": {
            "status": "candidate",
            "review_status": "pending_review",
            "production_eligible": False,
            "active_write": False,
        },
        "observed_performance": [{
            "evidence_id": "44444444-4444-4444-8444-444444444444",
            "assessment_target_id": "55555555-5555-4555-8555-555555555555",
            "question_scope": scope,
            "maximum_score": None,
            "average_score": None,
            "score_rate": None,
            "difficulty_observed": metric,
            "discrimination": None,
            "option_distribution": None,
            "status": "candidate",
            "review_status": "pending_review",
            "production_eligible": False,
        }],
        "observed_errors": [{
            "evidence_id": "66666666-6666-4666-8666-666666666666",
            "assessment_target_id": "55555555-5555-4555-8555-555555555555",
            "question_scope": scope,
            "record_kind": "summary_candidate",
            "content": "error",
            "generation_method": "rules",
            "confidence": 0.8,
            "anchor": error_anchor,
            "status": "candidate",
            "review_status": "pending_review",
            "production_eligible": False,
        }],
        "teaching_recommendations": [{
            "recommendation_id": "77777777-7777-4777-8777-777777777777",
            "assessment_target_id": "55555555-5555-4555-8555-555555555555",
            "question_scope": scope,
            "content": "recommendation",
            "author_kind": "legacy_candidate",
            "generation_method": "rules",
            "confidence": 0.8,
            "anchor": recommendation_anchor,
            "status": "candidate",
            "review_status": "pending_review",
            "production_eligible": False,
        }],
        "review_queue": [{
            "assessment_target_id": "55555555-5555-4555-8555-555555555555",
            "scope_key": scope["scope_key"],
            "status": "pending_review",
            "priority": "high",
            "reasons": ["candidate_only"],
            "year": 2025,
            "question_number": 1,
        }],
    }


if __name__ == "__main__":
    unittest.main()

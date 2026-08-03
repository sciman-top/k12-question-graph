from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path

TOOLS_ROOT = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS_ROOT))

import regional_exam_profile_aggregation as aggregation  # noqa: E402


class RegionalExamProfileAggregationTests(unittest.TestCase):
    def test_recent_window_uses_latest_same_score_and_standard_cohort(self) -> None:
        config = fixture_config()
        config["windows"]["full"]["years"] = [2021, 2022, 2023, 2024, 2025]
        config["papers"] = [paper_fixture(year) for year in range(2021, 2026)]

        self.assertEqual(aggregation.select_recent_comparable_years(config), [2021, 2022, 2023, 2024])

    def test_builds_candidate_profile_with_complete_score_denominator(self) -> None:
        result = aggregate_fixture()
        profile = full_profile(result)["profile"]

        self.assertEqual(profile["frequency_weight"]["denominator_comparable_exam_papers"], 3)
        self.assertEqual(profile["frequency_weight"]["numerator_occurrences"], 3)
        self.assertEqual(profile["score_weight"]["denominator_total_exam_score"], 270)
        self.assertEqual(profile["score_weight"]["numerator_profile_score"], 9)
        self.assertEqual(profile["status"], "candidate")
        self.assertEqual(profile["review_status"], "pending_review")
        self.assertFalse(profile["production_eligible"])

    def test_cross_standard_full_window_blocks_trend_claim(self) -> None:
        item = full_profile(aggregate_fixture())

        self.assertEqual(item["profile"]["standard_regime"]["regime_type"], "transition")
        self.assertEqual(item["profile"]["trend"]["status"], "insufficient_evidence")
        self.assertEqual(item["diagnostics"]["comparability"], "degraded")

    def test_profiles_trace_to_paper_answer_and_report(self) -> None:
        item = full_profile(aggregate_fixture())

        self.assertEqual(set(item["traceability"]["anchorRoles"]), {"answer", "paper", "report"})
        self.assertEqual(len(item["traceability"]["assessmentTargetIds"]), 3)

    def test_incomplete_score_numerator_is_blocked_not_imputed(self) -> None:
        targets, observed, questions, config = fixtures()
        metadata = json.loads(targets["items"][1]["metadata"])
        metadata["scoreWeight"] = None
        targets["items"][1]["metadata"] = json.dumps(metadata)

        result = aggregation.aggregate_profiles(targets, observed, questions, config)
        blocked = next(row for row in result["blocked"] if row["windowId"] == "fixture_full")

        self.assertIn("incomplete_score_numerator", blocked["reasons"])
        self.assertFalse(any(row["diagnostics"]["windowId"] == "fixture_full" for row in result["profiles"]))

    def test_missing_observed_difficulty_is_blocked_not_imputed(self) -> None:
        targets, observed, questions, config = fixtures()
        observed["performance"] = []

        result = aggregation.aggregate_profiles(targets, observed, questions, config)
        blocked = next(row for row in result["blocked"] if row["windowId"] == "fixture_full")

        self.assertIn("observed_difficulty", blocked["reasons"])

    def test_candidate_and_reviewed_sources_are_split_and_labelled(self) -> None:
        targets, observed, questions, config = fixtures()
        reviewed_target = copy.deepcopy(targets["items"][0])
        reviewed_target["id"] = "90000000-0000-0000-0000-000000000009"
        reviewed_target["status"] = "reviewed"
        reviewed_target["reviewStatus"] = "approved"
        reviewed_metadata = json.loads(reviewed_target["metadata"])
        reviewed_metadata["candidateOnly"] = False
        reviewed_target["metadata"] = json.dumps(reviewed_metadata)
        reviewed_observed = copy.deepcopy(observed["performance"][0])
        reviewed_observed["id"] = "91000000-0000-0000-0000-000000000009"
        reviewed_observed["assessmentTargetId"] = reviewed_target["id"]
        reviewed_observed["status"] = "reviewed"
        reviewed_observed["reviewStatus"] = "approved"
        reviewed_evidence = json.loads(reviewed_observed["evidence"])
        reviewed_evidence["candidateOnly"] = False
        reviewed_observed["evidence"] = json.dumps(reviewed_evidence)
        targets["items"].append(reviewed_target)
        observed["performance"].append(reviewed_observed)

        result = aggregation.aggregate_profiles(targets, observed, questions, config)
        states = {row["diagnostics"]["sourceState"] for row in result["profiles"]}

        self.assertEqual(states, {"explicit_candidate", "reviewed"})
        self.assertEqual(result["aggregation"]["crossStateMixes"], 0)

    def test_profile_diagnostics_include_requested_distributions(self) -> None:
        diagnostics = full_profile(aggregate_fixture())["diagnostics"]

        for key in (
            "cooccurrenceCounts",
            "abilityDistribution",
            "cognitiveDistribution",
            "taskTypeDistribution",
            "contextTypeDistribution",
            "representationTypeDistribution",
        ):
            self.assertTrue(diagnostics[key], key)

    def test_score_denominator_requires_source_evidence(self) -> None:
        targets, observed, questions, config = fixtures()
        del config["papers"][0]["scoreEvidence"]["sourceLiteral"]

        with self.assertRaisesRegex(aggregation.RegionalExamProfileAggregationError, "score evidence"):
            aggregation.aggregate_profiles(targets, observed, questions, config)

    def test_score_denominator_rejects_missing_evidence_object(self) -> None:
        targets, observed, questions, config = fixtures()
        del config["papers"][0]["scoreEvidence"]

        with self.assertRaisesRegex(aggregation.RegionalExamProfileAggregationError, "score evidence"):
            aggregation.aggregate_profiles(targets, observed, questions, config)


def aggregate_fixture() -> dict:
    return aggregation.aggregate_profiles(*fixtures())


def full_profile(result: dict) -> dict:
    return next(row for row in result["profiles"] if row["diagnostics"]["windowId"] == "fixture_full")


def fixtures() -> tuple[dict, dict, dict, dict]:
    targets = []
    observed = []
    questions = {}
    for index, year in enumerate((2023, 2024, 2025), 1):
        question_id = f"00000000-0000-0000-0000-{year:012d}"
        target_id = f"10000000-0000-0000-0000-{year:012d}"
        paper_region_id = f"20000000-0000-0000-0000-{year:012d}"
        answer_region_id = f"30000000-0000-0000-0000-{year:012d}"
        report_region_id = f"40000000-0000-0000-0000-{year:012d}"
        metadata = {
            "candidateOnly": True,
            "scoreWeight": 3.0,
            "abilityDimensions": ["科学推理"],
            "cognitiveDemands": ["推理"],
            "taskType": "single_choice",
            "contextType": "real_world",
            "representationTypes": ["diagram", "text"],
            "evidenceRefs": [
                {
                    "role": "question_stem_source",
                    "source_document_id": paper_fixture(year)["scoreEvidence"]["sourceDocumentId"],
                    "source_region_id": paper_region_id,
                },
                {
                    "role": "answer_or_solution_source",
                    "source_document_id": f"50000000-0000-0000-0000-{year:012d}",
                    "source_region_id": answer_region_id,
                },
            ],
        }
        targets.append({
            "id": target_id,
            "stableKey": f"AT-FIXTURE-{year}",
            "questionItemId": question_id,
            "scopeType": "whole_question",
            "status": "candidate",
            "reviewStatus": "pending_review",
            "productionEligible": False,
            "primaryKnowledgeAssetVersionId": "00000000-0000-0000-0000-000000000001",
            "metadata": json.dumps(metadata, ensure_ascii=False),
            "curriculumAlignments": [],
        })
        observed.append({
            "id": f"60000000-0000-0000-0000-{year:012d}",
            "assessmentTargetId": target_id,
            "difficultyObserved": 0.5 + index * 0.1,
            "difficultyDirection": "higher_is_easier",
            "status": "candidate",
            "reviewStatus": "pending_review",
            "productionEligible": False,
            "evidence": json.dumps({
                "candidateOnly": True,
                "anchor": {
                    "source_document_id": f"70000000-0000-0000-0000-{year:012d}",
                    "source_region_id": report_region_id,
                    "pdf_page_number": 3,
                },
            }),
        })
        questions[question_id] = {
            "id": question_id,
            "subject": "physics",
            "stage": "junior_middle_school",
            "customFields": {
                "year": year,
                "materialBatchKey": "fixture_batch",
                "primaryKnowledgeCandidateId": "KPHY-FIXTURE-001",
                "knowledgeCandidateIds": ["KPHY-FIXTURE-002"],
            },
            "blocks": [{
                "blockType": "year_report_evidence",
                "sourceRegionId": report_region_id,
                "content": {"pageNumber": 3},
            }],
        }
    return {"items": targets}, {"performance": observed}, questions, fixture_config()


def fixture_config() -> dict:
    return {
        "schemaVersion": "guangzhou-profile-comparability.v1",
        "region": "guangzhou",
        "subject": "physics",
        "stage": "junior_middle_school",
        "materialBatchKey": "fixture_batch",
        "expectedQuestionCount": 3,
        "expectedQuestionCountsByYear": {"2023": 1, "2024": 1, "2025": 1},
        "windows": {
            "full": {"id": "fixture_full", "years": [2023, 2024, 2025]},
            "recentComparable": {"id": "fixture_recent", "minimumYears": 2, "maximumYears": 5},
        },
        "papers": [paper_fixture(year) for year in (2023, 2024, 2025)],
        "standardRegimes": {
            "historical": {
                "standardVersions": ["historical"],
                "interpretationGuard": "historical source boundary",
            },
            "current": {
                "standardVersions": ["current"],
                "interpretationGuard": "current source boundary",
            },
        },
        "trend": {"minimumComparableYears": 3, "slopeThreshold": 0.05},
        "rules": {
            "requireCompleteScoreNumerator": True,
            "requireObservedDifficulty": True,
            "requirePaperAnswerReportAnchors": True,
        },
        "difficultyBuckets": [
            {"label": "hard", "minimumInclusive": 0.0, "maximumExclusive": 0.4},
            {"label": "moderate", "minimumInclusive": 0.4, "maximumExclusive": 0.7},
            {"label": "easy", "minimumInclusive": 0.7, "maximumExclusive": 1.0, "includeMaximum": True},
        ],
    }


def paper_fixture(year: int) -> dict:
    historical = year < 2025
    return {
        "year": year,
        "questionCount": 18,
        "totalScore": 90,
        "scoreRegime": "questions18_total90",
        "standardRegime": "historical" if historical else "current",
        "sha256": f"{year:04d}" * 16,
        "scoreEvidence": {
            "sourceDocumentId": f"80000000-0000-0000-0000-{year:012d}",
            "pdfPageNumbers": [1],
            "sourceLiteral": "满分90分",
            "basis": "header_total_score",
        },
    }


if __name__ == "__main__":
    unittest.main()

from __future__ import annotations

import sys
import unittest
from pathlib import Path

TOOLS_ROOT = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS_ROOT))

import guangzhou_year_report_evidence as evidence  # noqa: E402


class GuangzhouYearReportEvidenceTests(unittest.TestCase):
    def test_page_verified_values_generate_candidate_only_evidence(self) -> None:
        result = evidence.build_package(
            [observation_fixture()], alignment_fixture(), target_fixture(), pages_fixture()
        )

        row = result["observed_performance"][0]
        self.assertEqual(row["difficulty_observed"]["parsed_value"], 0.72)
        self.assertEqual(row["difficulty_observed"]["scale_direction"], "higher_is_easier")
        self.assertIsNone(row["maximum_score"])
        self.assertEqual(row["difficulty_observed"]["anchor"]["source_region_id"], "00000000-0000-4000-8000-000000000131")
        self.assertEqual(row["difficulty_observed"]["anchor"]["source_document_sha256"], "a" * 64)
        self.assertFalse(row["production_eligible"])
        self.assertEqual(result["generation"]["external_model_calls"], 0)

    def test_number_missing_from_page_is_not_emitted_and_is_blocked(self) -> None:
        pages = pages_fixture()
        pages[2025]["pages"][1] = "第1题 页面不含统计数值"

        result = evidence.build_package(
            [observation_fixture()], alignment_fixture(), target_fixture(), pages
        )

        self.assertEqual(result["observed_performance"], [])
        self.assertEqual(result["review_queue"][0]["priority"], "blocked")
        self.assertIn("difficulty_value_not_found_on_page", result["review_queue"][0]["reasons"])

    def test_option_distribution_sum_anomaly_enters_review(self) -> None:
        row = observation_fixture()
        row["option_distribution_summary"] = "A:20%;B:20%"
        pages = pages_fixture()
        pages[2025]["pages"][1] += " A 20% B 20%"

        result = evidence.build_package([row], alignment_fixture(), target_fixture(), pages)

        self.assertIn("option_distribution_sum_anomaly", result["review_queue"][0]["reasons"])

    def test_option_distribution_out_of_range_is_not_emitted(self) -> None:
        row = observation_fixture()
        row["option_distribution_summary"] = "A:10%;B:72%;C:10%;D:8%;未选:2013%"
        pages = pages_fixture()
        pages[2025]["pages"][1] += " 未选 2013%"

        result = evidence.build_package([row], alignment_fixture(), target_fixture(), pages)

        candidate = result["observed_performance"][0]
        self.assertIsNone(candidate["option_distribution"])
        self.assertIn("option_distribution_value_out_of_range", result["review_queue"][0]["reasons"])

    def test_metric_specific_source_page_is_used_when_notes_name_statistical_table(self) -> None:
        row = observation_fixture()
        row["discrimination_value"] = "0.64"
        row["notes"] = "难度来自逐题页;区分度来自统计表p1"
        pages = pages_fixture()
        pages[2025]["pages"][0] = "统计表 第1题 区分度 0.64"

        result = evidence.build_package([row], alignment_fixture(), target_fixture(), pages)

        metric = result["observed_performance"][0]["discrimination"]
        self.assertEqual(metric["parsed_value"], 0.64)
        self.assertEqual(metric["anchor"]["pdf_page_number"], 1)

    def test_missing_year_observation_is_not_imputed(self) -> None:
        alignment = alignment_fixture()
        missing = dict(alignment["bundles"][0])
        missing.update({"year": 2015, "questionNumber": 1})
        alignment["bundles"].append(missing)

        result = evidence.build_package(
            [observation_fixture()], alignment, target_fixture(), pages_fixture()
        )

        missing_review = next(row for row in result["review_queue"] if row["year"] == 2015)
        self.assertIn("c003_observation_missing", missing_review["reasons"])
        self.assertEqual(result["missing_fields"]["observation"], 1)

    def test_duplicate_observation_fails_closed(self) -> None:
        row = observation_fixture()
        with self.assertRaisesRegex(ValueError, "duplicate_observation"):
            evidence.build_package(
                [row, dict(row)], alignment_fixture(), target_fixture(), pages_fixture()
            )

    def test_missing_2015_observation_is_derived_from_report_anchor(self) -> None:
        alignment = alignment_fixture()
        alignment["bundles"][0].update({"year": 2015, "questionNumber": 1})
        alignment["bundles"][0]["reportAnchors"][0]["pageNumber"] = 1
        pages = {2015: {"sha256": "b" * 64, "pages": ["1. 真实题干 考查的科学内容：运动和相互作用主题 分析：难度：0.81，区分度：0.50"]}}

        rows = evidence.derive_missing_observations([], alignment, pages)

        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["difficulty_value"], "0.81")
        self.assertEqual(rows[0]["discrimination_value"], "0.50")
        self.assertEqual(rows[0]["generation_method"], "report_heading_rule_candidate")


def observation_fixture() -> dict[str, str]:
    return {
        "year": "2025",
        "question_number": "1",
        "evidence_locations": "年报p2;逐题分析",
        "difficulty_value": "0.72",
        "discrimination_value": "0.51",
        "option_distribution_summary": "A:10%;B:72%;C:10%;D:8%",
        "common_errors_summary": "学生容易混淆音调和响度，需要结合真实情境辨析概念",
        "teaching_suggestion_summary": "教学过程中应通过对比实验帮助学生区分音调和响度",
        "confidence": "0.9",
        "notes": "难度来自逐题页;区分度来自逐题页",
    }


def alignment_fixture() -> dict:
    return {"bundles": [{
        "year": 2025,
        "questionNumber": 1,
        "questionItemId": "00000000-0000-4000-8000-000000000151",
        "reportDocument": {"sourceDocumentId": "00000000-0000-4000-8000-000000000121"},
        "reportAnchors": [{"sourceRegionId": "00000000-0000-4000-8000-000000000131", "pageNumber": 2}],
    }]}


def target_fixture() -> dict:
    return {"targets": [{
        "target_id": "AT-TEST-1",
        "question_scope": {
            "scope_key": "question-scope:v1:test:whole_question",
            "scope_type": "whole_question",
            "question_item_id": "00000000-0000-4000-8000-000000000151",
            "question_block_id": None,
        },
    }]}


def pages_fixture() -> dict:
    text = (
        "第1题 难度 0.72 区分度 0.51 A 10% B 72% C 10% D 8% "
        "学生容易混淆音调和响度，需要结合真实情境辨析概念。"
        "教学过程中应通过对比实验帮助学生区分音调和响度。"
    )
    return {2025: {"sha256": "a" * 64, "pages": ["封面", text]}}


if __name__ == "__main__":
    unittest.main()

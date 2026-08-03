from __future__ import annotations

import sys
import unittest
from pathlib import Path

TOOLS_ROOT = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS_ROOT))

import guangzhou_report_anchor_materialize as materializer  # noqa: E402


class GuangzhouReportAnchorMaterializeTests(unittest.TestCase):
    def test_parse_report_page(self) -> None:
        self.assertEqual(materializer.parse_report_page("年报p12;逐题分析"), 12)
        self.assertIsNone(materializer.parse_report_page("待定位"))

    def test_heading_locator_prefers_stem_match_and_monotonic_page(self) -> None:
        pages = [
            "目录\n1. 命题原则",
            "1. 咸鱼放在冰箱冷冻室里一晚，冷冻室内有咸鱼味。考查的科学内容。",
            "2. 其他题目",
            "附录\n1. 无关编号",
        ]
        page, confidence = materializer.locate_heading_page(
            pages,
            1,
            "1. 咸鱼放在冰箱冷冻室里一晚，冷冻室内有咸鱼味。",
        )
        self.assertEqual(page, 2)
        self.assertGreater(confidence, 0.7)

    def test_page_plan_combines_2015_pdf_and_later_observations(self) -> None:
        questions = [
            {"question_item_id": "q15", "year": 2015, "question_number": 1, "stem": "1. 真实题干"},
            {"question_item_id": "q16", "year": 2016, "question_number": 1, "stem": "1. 另一题干"},
        ]
        observations = [{"year": "2016", "question_number": "1", "evidence_locations": "年报p7"}]

        plan = materializer.build_page_plan(questions, observations, ["目录", "1. 真实题干 分析"])

        self.assertEqual([(row["year"], row["pageNumber"]) for row in plan], [(2015, 2), (2016, 7)])
        self.assertEqual(plan[0]["localizationMethod"], "heading_and_stem_similarity")

    def test_extra_metric_page_plan_only_adds_unmaterialized_pages(self) -> None:
        base = [{"questionItemId": "q1", "year": 2015, "questionNumber": 1, "pageNumber": 2}]
        package = {"observed_performance": [{
            "question_scope": {"question_item_id": "q1"},
            "difficulty_observed": {"anchor": {"pdf_page_number": 3, "source_region_id": None}},
            "discrimination": {"anchor": {"pdf_page_number": 3, "source_region_id": None}},
            "option_distribution": None,
        }]}

        result = materializer.build_extra_evidence_plan(package, base)

        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["pageNumber"], 3)
        self.assertEqual(result[0]["anchorKind"], "metric_page")


if __name__ == "__main__":
    unittest.main()

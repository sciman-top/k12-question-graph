from __future__ import annotations

import sys
import tempfile
import unittest
import uuid
from pathlib import Path
from types import SimpleNamespace

import fitz


TOOLS_ROOT = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS_ROOT))

import guangzhou_physics_v2_golden_eval as golden_eval  # noqa: E402
import guangzhou_physics_v2_layout_blocks as layout_blocks  # noqa: E402


class GuangzhouV2LayoutBlockTests(unittest.TestCase):
    def test_required_golden_criteria_cover_all_admission_dimensions(self) -> None:
        self.assertEqual(
            {
                "stem_complete",
                "options_complete_ordered",
                "figure_ownership",
                "table_structure",
                "formula_fidelity",
                "cross_page_reading_order",
                "header_footer_isolation",
                "original_question_number",
                "subquestion_relationship",
            },
            set(golden_eval.REQUIRED_CRITERIA),
        )

    def test_option_parts_preserve_complete_order(self) -> None:
        self.assertEqual(
            [("A", "甲"), ("B", "乙"), ("C", "丙"), ("D", "丁")],
            layout_blocks.option_parts("A. 甲 B. 乙 C. 丙 D. 丁"),
        )

    def test_layout_contract_reuses_stable_source_region_and_reading_order(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            pdf_path = Path(temp_dir) / "paper.pdf"
            document = fitz.open()
            page = document.new_page(width=595, height=842)
            page.insert_text((70, 100), "1. Complete stem")
            page.insert_text((70, 130), "A. first B. second C. third D. fourth")
            document.save(pdf_path)
            document.close()
            region = SimpleNamespace(page_number=1, bbox_percent=(5.0, 5.0, 90.0, 20.0), relative_path="q01.png")
            plan = SimpleNamespace(
                year=2025,
                source_document_id=uuid.UUID("11111111-1111-1111-1111-111111111111"),
                source_file="paper.pdf",
                questions={1: (region,)},
            )

            result = layout_blocks.build_question_layout(pdf_path, plan, 1)

        expected_region_id = layout_blocks.source_region_id(2025, 1, 1)
        self.assertEqual("guangzhou-question-layout.v1", result["contractVersion"])
        self.assertEqual(expected_region_id, result["sourceRegions"][0]["sourceRegionId"])
        self.assertTrue(all(block["sourceRegionId"] == expected_region_id for block in result["blocks"]))
        self.assertEqual(list(range(len(result["blocks"]))), [block["readingOrder"] for block in result["blocks"]])
        self.assertEqual(["A", "B", "C", "D"], [block["optionLabel"] for block in result["blocks"] if block["blockType"] == "option"])
        self.assertFalse(result["productionEligible"])

    def test_evaluator_keeps_noise_out_of_content_and_checks_asset_ownership(self) -> None:
        question = {
            "contentText": "1. stem A B C D",
            "noiseText": "第1页/共8页",
            "originalQuestionNumber": 1,
            "subquestionLabels": [],
            "sourceRegions": [{"sourceRegionId": "region-1", "pageNumber": 1}],
            "blocks": [
                {
                    "blockType": "image",
                    "sourceRegionId": "region-1",
                    "assetReference": {"relativePath": "q01.png"},
                    "pageNumber": 1,
                    "readingOrder": 0,
                    "text": "",
                },
                {
                    "blockType": "noise",
                    "sourceRegionId": "region-1",
                    "assetReference": {"relativePath": "q01.png"},
                    "pageNumber": 1,
                    "readingOrder": 1,
                    "text": "第1页/共8页",
                },
            ],
        }
        case = {
            "assertions": {
                "requiredBlockTypes": ["image"],
                "assetOwnedByQuestion": True,
                "forbiddenContentText": ["第1页/共8页"],
            }
        }

        results = golden_eval.evaluate_case(question, case)

        self.assertTrue(all(result["passed"] for result in results), results)


if __name__ == "__main__":
    unittest.main()

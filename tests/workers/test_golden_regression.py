"""golden 输出回归:规范化 document model 与稳定语义断言。

golden 文件由 tests/golden-import/golden_runner.py 显式重建;外部二进制与 OCR
引擎被强制 mock 为不可用,保证任何环境可比。真实 OCR 链路的验收属于 P001
目标机实测,不在本回归范围。
"""

import pathlib
import sys
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
GOLDEN_IMPORT_ROOT = REPO_ROOT / "tests" / "golden-import"
if str(GOLDEN_IMPORT_ROOT) not in sys.path:
    sys.path.insert(0, str(GOLDEN_IMPORT_ROOT))

import golden_runner  # noqa: E402


class GoldenDocumentModelRegressionTests(unittest.TestCase):
    def test_docx_blocks_keeps_semantic_contract(self) -> None:
        normalized = golden_runner.assert_matches_golden(self, "docx-blocks")

        self.assertEqual("openxml_docx_adapter", normalized["adapterName"])
        self.assertEqual([], normalized["warnings"])
        pages = normalized["documentModel"]["pages"]
        self.assertEqual(1, len(pages))
        blocks = pages[0]["layoutBlocks"]
        self.assertEqual(
            ["question_stem", "option", "answer", "explanation", "table", "formula", "image"],
            [block["blockType"] for block in blocks],
        )
        formula_blocks = [block for block in blocks if block["blockType"] == "formula"]
        self.assertEqual(1, len(formula_blocks))
        formula = formula_blocks[0]["formula"]["formulas"][0]
        # 抓取保真与转换进度分离(见 worker README 与 2026-08-25 评审定案)。
        self.assertEqual("verified", formula["reviewStatus"])
        self.assertEqual("pending_conversion", formula["conversionStatus"])
        self.assertIsNone(formula["latex"])
        self.assertIsNone(formula["mathml"])
        self.assertIn("v=s/t", formula["omml"])
        table_blocks = [block for block in blocks if block["blockType"] == "table"]
        self.assertEqual(1, len(table_blocks))
        self.assertIn("装置", table_blocks[0]["textPreview"])
        image_blocks = [block for block in blocks if block["blockType"] == "image"]
        self.assertEqual(1, len(image_blocks))
        self.assertEqual("rId7", image_blocks[0]["textPreview"])

    def test_pdf_text_questions_keeps_semantic_contract(self) -> None:
        normalized = golden_runner.assert_matches_golden(self, "pdf-text-questions")

        self.assertEqual("pdf_text_adapter", normalized["adapterName"])
        pages = normalized["documentModel"]["pages"]
        self.assertEqual(1, len(pages))
        blocks = pages[0]["layoutBlocks"]
        self.assertEqual(
            ["question_stem", "question_stem", "option", "option", "answer", "explanation"],
            [block["blockType"] for block in blocks],
        )
        # decode_pdf_literal 必须按 UTF-8 优先解码,否则中文答案/解析分类失效。
        self.assertEqual("答案 A", blocks[4]["textPreview"])
        self.assertIn("真空不能传声", blocks[5]["textPreview"])

    def test_pdf_sparse_ocr_takeover_keeps_fail_closed_contract(self) -> None:
        normalized = golden_runner.assert_matches_golden(self, "pdf-sparse-ocr-takeover")

        self.assertEqual("scanned_ocr_review_adapter", normalized["adapterName"])
        pages = normalized["documentModel"]["pages"]
        self.assertEqual(2, len(pages))
        for page in pages:
            takeover_blocks = [
                block
                for block in page["layoutBlocks"]
                if block["blockType"] == "ocr_candidate"
            ]
            self.assertEqual(1, len(takeover_blocks), "每页必须保留一个人工接管块")
            block = takeover_blocks[0]
            self.assertTrue(block["takeoverRequired"])
            self.assertEqual("pending_review", block["reviewStatus"])
        self.assertTrue(
            any("manual review takeover" in warning for warning in normalized["warnings"])
        )


if __name__ == "__main__":
    unittest.main()

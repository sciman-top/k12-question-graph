import pathlib
import sys
import unittest
from unittest import mock


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
WORKER_ROOT = REPO_ROOT / "workers" / "document"
if str(WORKER_ROOT) not in sys.path:
    sys.path.insert(0, str(WORKER_ROOT))

import worker  # noqa: E402


class WorkerHelpersTests(unittest.TestCase):
    def test_sha256_json_is_stable_across_key_order(self) -> None:
        left = {"jobId": "a", "pages": [{"pageNumber": 1, "text": "ok"}]}
        right = {"pages": [{"text": "ok", "pageNumber": 1}], "jobId": "a"}

        self.assertEqual(worker.sha256_json(left), worker.sha256_json(right))

    def test_split_pdf_text_blocks_marks_question_and_answer_boundaries(self) -> None:
        text = "\n".join(
            [
                "2024 学业质量检测",
                "第一部分 选择题",
                "1. 下列关于力的说法正确的是",
                "A. 受力一定改变运动状态",
                "答案 B",
            ]
        )

        blocks, body_started = worker.split_pdf_text_blocks(text, page_number=1, body_started=False)

        self.assertTrue(body_started)
        self.assertGreaterEqual(len(blocks), 2)
        self.assertEqual(blocks[0]["blockType"], "document_header")
        self.assertEqual(blocks[1]["blockType"], "question_stem")
        self.assertTrue(any(block["blockType"] == "answer" for block in blocks))

    def test_split_pdf_text_blocks_keeps_exam_instructions_in_header_until_section(self) -> None:
        text = "\n".join(
            [
                "2015 年广州市初中毕业生学业考试",
                "注意事项:",
                "1. 答题前，考生务必填写考生号。",
                "2. 第一部分每小题选出答案后涂黑。",
                "第一部分（共 36 分）",
                "一、选择题（每小题 3 分）",
                "1. 咸鱼放在冰箱冷冻室里一晚，冷冻室内有咸鱼味。",
                "A. 分子间存在引力",
            ]
        )

        blocks, body_started = worker.split_pdf_text_blocks(text, page_number=1, body_started=False)

        self.assertTrue(body_started)
        self.assertGreaterEqual(len(blocks), 3)
        self.assertEqual(blocks[0]["blockType"], "document_header")
        self.assertIn("注意事项", blocks[0]["textPreview"])
        self.assertEqual(blocks[1]["blockType"], "question_stem")
        self.assertTrue(blocks[1]["textPreview"].startswith("1. 咸鱼放在冰箱"))

    def test_split_pdf_text_blocks_splits_consecutive_question_numbers(self) -> None:
        text = "\n".join(
            [
                "9. 图 8 所示玻璃管两端开口处蒙的橡皮膜绷紧程度相同。",
                "哪幅图能反映橡皮膜受到水的压强后的凹凸情况。",
                "10. 规格相同的瓶装了不同的液体，放在横梁已平衡的天平上。",
                "A. 甲瓶液体质量较大",
                "14.(1)在图 14 中标示出物距。",
                "15. 墙上的喜羊羊是实像还是虚像？",
            ]
        )

        blocks, body_started = worker.split_pdf_text_blocks(text, page_number=3, body_started=True)

        self.assertTrue(body_started)
        question_blocks = [block for block in blocks if block["blockType"] == "question_stem"]
        previews = [block["textPreview"] for block in question_blocks]
        self.assertEqual(len(question_blocks), 4)
        self.assertTrue(previews[0].startswith("9. 图 8"))
        self.assertTrue(previews[1].startswith("10. 规格相同"))
        self.assertTrue(previews[2].startswith("14.(1)在图 14"))
        self.assertTrue(previews[3].startswith("15. 墙上的喜羊羊"))

    def test_build_ocr_review_pages_creates_takeover_blocks(self) -> None:
        pages = worker.build_ocr_review_pages(
            page_count=2,
            source="pdf_scanned_ocr_review",
            warning="OCR unavailable",
            page_objects=[11, 12],
        )

        self.assertEqual(len(pages), 2)
        self.assertEqual(pages[0]["layoutBlocks"][0]["blockType"], "ocr_candidate")
        self.assertTrue(pages[0]["layoutBlocks"][0]["takeoverRequired"])
        self.assertEqual(pages[1]["layoutBlocks"][0]["sourceRegion"]["pageObject"], 12)

    def test_sparse_pdf_text_requires_ocr_fallback(self) -> None:
        sparse_pages = [
            {
                "pageNumber": page_number,
                "layoutBlocks": [
                    {
                        "blockType": "document_header",
                        "textPreview": f"物理试卷{page_number}",
                    }
                ],
            }
            for page_number in range(1, 7)
        ]
        normal_pages = [
            {
                "pageNumber": 1,
                "layoutBlocks": [
                    {
                        "blockType": "answer",
                        "textPreview": "参考答案 " + ("有效答案和解析内容" * 40),
                    }
                ],
            }
        ]

        self.assertTrue(worker.pdf_text_is_too_sparse(sparse_pages))
        self.assertFalse(worker.pdf_text_is_too_sparse(normal_pages))

    def test_resolve_pdftoppm_prefers_executable_on_windows(self) -> None:
        candidates = {
            "pdftoppm.exe": r"C:\tools\poppler\pdftoppm.exe",
            "pdftoppm": r"C:\broken-wrapper\pdftoppm.cmd",
        }
        with (
            mock.patch.object(worker.platform, "system", return_value="Windows"),
            mock.patch.object(worker.shutil, "which", side_effect=candidates.get) as which,
        ):
            resolved = worker.resolve_pdftoppm()

        self.assertEqual(resolved, candidates["pdftoppm.exe"])
        which.assert_called_once_with("pdftoppm.exe")


if __name__ == "__main__":
    unittest.main()

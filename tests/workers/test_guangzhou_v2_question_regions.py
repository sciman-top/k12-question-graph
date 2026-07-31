import pathlib
import sys
import tempfile
import unittest

from PIL import Image, ImageDraw


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOLS_ROOT = REPO_ROOT / "tools"
if str(TOOLS_ROOT) not in sys.path:
    sys.path.insert(0, str(TOOLS_ROOT))

import guangzhou_physics_v2_question_regions as regions  # noqa: E402


class GuangzhouV2QuestionRegionTests(unittest.TestCase):
    def test_anchor_numbers_rejects_multi_question_heading_and_accepts_embedded_anchor(self) -> None:
        self.assertEqual(regions.anchor_numbers("16、17题结合题目要求"), [])
        self.assertEqual(regions.anchor_numbers("②16. 图a所示"), [16])

    def test_multi_question_heading_becomes_the_first_question_visual_start(self) -> None:
        heading = regions.Anchor(14, 4, 520, 42, "14、15题结合手指投影灯回答")
        selected = {
            13: regions.Anchor(13, 4, 403, 40, "13."),
            14: regions.Anchor(14, 4, 571, 40, "14.(1)"),
            15: regions.Anchor(15, 4, 698, 40, "15."),
        }

        starts = regions.apply_shared_prompt_starts(selected, [heading])

        self.assertEqual(starts[13].top, 403)
        self.assertEqual(starts[14].top, 520)
        self.assertEqual(starts[15].top, 698)

    def test_2015_cross_question_figure_layout_uses_auditable_split_regions(self) -> None:
        paper_sha256 = "534d8eee3b99446d514af736aaf4cd8e36f2803154f7778c0f656f1832b7510c"

        q18 = regions.manual_visual_crop_specs(paper_sha256, 18)
        q19 = regions.manual_visual_crop_specs(paper_sha256, 19)

        self.assertEqual([(spec.page_number, spec.order) for spec in q18], [(5, 1), (5, 2)])
        self.assertEqual([(spec.page_number, spec.order) for spec in q19], [(5, 1), (5, 2)])
        self.assertLess(q18[0].bottom, q18[1].top)
        self.assertEqual(q18[1].right, 42.0)
        self.assertEqual(q19[1].left, 45.0)
        self.assertLess(q19[0].bottom, 90.0)

    def test_select_question_anchors_skips_exam_instructions_before_choice_section(self) -> None:
        anchors = [
            regions.Anchor(1, 1, 100, 50, "1.答题前"),
            regions.Anchor(1, 1, 300, 50, "1.实际试题"),
            regions.Anchor(2, 1, 400, 50, "2.实际试题"),
            regions.Anchor(3, 2, 80, 50, "3.实际试题"),
        ]

        selected, takeovers = regions.select_question_anchors(anchors, {1: 250}, 3)

        self.assertEqual(selected[1].top, 300)
        self.assertEqual(selected[2].top, 400)
        self.assertEqual(selected[3].page_number, 2)
        self.assertEqual(takeovers, [])

    def test_following_question_sequence_requires_three_consecutive_numbers(self) -> None:
        last = regions.Anchor(24, 8, 100, 50, "24. final question")
        anchors = [
            last,
            regions.Anchor(2, 9, 80, 50, "2. isolated formula"),
            regions.Anchor(13, 10, 90, 50, "13. answer"),
            regions.Anchor(14, 10, 180, 50, "14. answer"),
            regions.Anchor(15, 10, 260, 50, "15. answer"),
        ]

        boundary = regions.following_question_sequence_start(anchors, last)

        self.assertIsNotNone(boundary)
        self.assertEqual(boundary.question_number, 13)
        self.assertEqual(boundary.page_number, 10)

    def test_following_question_sequence_ignores_isolated_later_number(self) -> None:
        last = regions.Anchor(18, 7, 600, 50, "18. final question")
        anchors = [last, regions.Anchor(2, 8, 300, 50, "2. isolated formula")]

        self.assertIsNone(regions.following_question_sequence_start(anchors, last))

    def test_section_boundary_segment_detects_transition_but_not_question_continuation(self) -> None:
        self.assertTrue(regions.is_section_boundary_segment("三、解析题（共24分） 解析题应写出必要步骤"))
        self.assertTrue(regions.is_section_boundary_segment("第二部分（共64分） 二、填空作图题"))
        self.assertFalse(regions.is_section_boundary_segment("（2）继续完成上页实验，并记录数据"))

    def test_crop_percent_creates_nonblank_region(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = pathlib.Path(temp_dir)
            source = root / "page.png"
            target = root / "crop.png"
            image = Image.new("RGB", (400, 400), "white")
            ImageDraw.Draw(image).rectangle((40, 80, 360, 300), fill="black")
            image.save(source)

            quality = regions.crop_percent(source, target, 5, 10, 95, 90)

            self.assertTrue(target.exists())
            self.assertTrue(quality["nonBlank"])


if __name__ == "__main__":
    unittest.main()

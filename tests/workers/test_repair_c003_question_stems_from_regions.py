import pathlib
import sys
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOLS_ROOT = REPO_ROOT / "tools"
if str(TOOLS_ROOT) not in sys.path:
    sys.path.insert(0, str(TOOLS_ROOT))

from repair_c003_question_stems_from_regions import (  # noqa: E402
    collapse_region_text,
    extract_question_stem_from_region_text,
    is_exam_instruction_stem,
)


class RepairC003QuestionStemsFromRegionsTests(unittest.TestCase):
    def test_collapse_region_text_removes_exam_identity_and_binding_marks(self) -> None:
        collapsed = collapse_region_text(
            "考生号： 123456 装 订 线 15. 真实物理题干 "
            "物理试卷 第 4 页 共 8 页 物理试卷6 [PAGE 6]"
        )

        self.assertEqual("123456 15. 真实物理题干", collapsed)

    def test_collapse_region_text_removes_spaced_vertical_identity_marks(self) -> None:
        collapsed = collapse_region_text(
            "姓 … 名 ： … 号 … 生 … 考 装 … 订 … 线 4. 真实物理题干"
        )

        self.assertEqual("4. 真实物理题干", collapsed)

    def test_extract_question_stem_trims_previous_question_tail(self) -> None:
        region_text = (
            "A. 9t B. 9kg C. 9g D. 9mg "
            "2. 如图1，手机与音叉的位置保持不变。"
            "利用手机软件测出音叉发出的声音从30dB变为50dB。 …………… 订 ：号生考"
        )

        stem = extract_question_stem_from_region_text(region_text, 2)

        self.assertTrue(stem.startswith("2. 如图1"))
        self.assertNotIn("9kg", stem)
        self.assertNotIn("订", stem)
        self.assertNotIn("号生考", stem)

    def test_instruction_classifier_rejects_exam_notice_but_keeps_real_question(self) -> None:
        instruction = (
            "4. 考生必须保持答题卡的整洁，考试结束后，将本试卷和答题卡一并交回。"
            "一、选择题：本题共10小题。"
        )
        real_question = "4. 如图，把吸盘压在竖直的玻璃墙上静止不动，则吸盘所受摩擦力（ ）"

        self.assertTrue(is_exam_instruction_stem(instruction))
        self.assertFalse(is_exam_instruction_stem(real_question))

    def test_extract_question_stem_rejects_wrong_or_missing_anchor(self) -> None:
        with self.assertRaisesRegex(ValueError, "question_anchor_missing:3"):
            extract_question_stem_from_region_text("2. 只有第二题", 3)

    def test_extract_question_stem_trims_next_question_and_section_instructions(self) -> None:
        next_question = extract_question_stem_from_region_text(
            "8. 液态氮制作冰淇淋的题干。9. 下一题不应进入第八题。",
            8,
        )
        section_instruction = extract_question_stem_from_region_text(
            "19. 滑轮组机械效率题干。三、解析题（共24分）解析题应写出必要步骤。",
            19,
        )

        self.assertEqual("8. 液态氮制作冰淇淋的题干。", next_question)
        self.assertEqual("19. 滑轮组机械效率题干。", section_instruction)

    def test_extract_question_stem_skips_combined_number_instruction_anchor(self) -> None:
        stem = extract_question_stem_from_region_text(
            "16、17题结合题目要求，涉及计算的应写出步骤。16. 电阻随温度变化的真实题干。",
            16,
        )
        previous = extract_question_stem_from_region_text(
            "15. 液体温度变化的真实题干。16~17题结合题目要求，只写答案不得分。",
            15,
        )

        self.assertEqual("16. 电阻随温度变化的真实题干。", stem)
        self.assertEqual("15. 液体温度变化的真实题干。", previous)


if __name__ == "__main__":
    unittest.main()

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

from pypdf import PdfWriter


TOOLS_ROOT = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS_ROOT))

import guangzhou_physics_v2_materialize as materialize  # noqa: E402
import real005b_reviewed_question_materialize as reviewed_materialize  # noqa: E402


class GuangzhouV2MaterializeTests(unittest.TestCase):
    def test_reviewed_materialize_connection_allows_local_passwordless_auth(self) -> None:
        without_password = reviewed_materialize.build_connection_kwargs(
            "127.0.0.1", 5432, "k12_question_graph", "postgres", ""
        )
        with_password = reviewed_materialize.build_connection_kwargs(
            "127.0.0.1", 5432, "k12_question_graph", "postgres", "secret"
        )

        self.assertNotIn("password", without_password)
        self.assertEqual("secret", with_password["password"])

    def test_2015_candidate_selection_prefers_current_v2_over_legacy(self) -> None:
        rows = [
            {"id": "legacy", "custom_fields": {"questionNo": 1, "sourceWorkflowKey": "guangzhou_2015_real_ingest_v1"}},
            {"id": "current", "custom_fields": {"questionNo": 1, "sourceWorkflowKey": materialize.WORKFLOW_KEY}},
        ]

        selected = reviewed_materialize.select_2015_candidate_rows(rows)

        self.assertEqual(["current"], [row["id"] for row in selected])

    def test_2015_candidate_selection_rejects_duplicate_current_rows(self) -> None:
        rows = [
            {"id": "current-a", "custom_fields": {"questionNo": 1, "sourceWorkflowKey": materialize.WORKFLOW_KEY}},
            {"id": "current-b", "custom_fields": {"questionNo": 1, "sourceWorkflowKey": materialize.WORKFLOW_KEY}},
        ]

        with self.assertRaisesRegex(ValueError, "duplicate_2015_candidate:1"):
            reviewed_materialize.select_2015_candidate_rows(rows)

    def test_2015_candidate_stem_is_cleaned_before_materialization(self) -> None:
        blocks = [
            {
                "type": "stem",
                "content": {
                    "text": "考生号： 装订线 19. 如图所示，物体保持静止。物理试卷 第 6 页 共 8 页 [PAGE 6]"
                },
            }
        ]

        stem = reviewed_materialize.extract_2015_candidate_stem(blocks, 19)

        self.assertEqual("19. 如图所示，物体保持静止。", stem)

    def test_expected_question_total_is_234(self) -> None:
        self.assertEqual(234, sum(materialize.EXPECTED_COUNTS.values()))
        self.assertEqual(24, materialize.EXPECTED_COUNTS[2015])
        self.assertEqual(18, materialize.EXPECTED_COUNTS[2025])

    def test_stable_ids_are_deterministic_and_scoped(self) -> None:
        first = materialize.stable_id("question-region", 2022, 1, 1)
        self.assertEqual(first, materialize.stable_id("question-region", 2022, 1, 1))
        self.assertNotEqual(first, materialize.stable_id("answer-document-page", 2022, 1, 1))

    def test_validate_candidate_coverage_fails_closed(self) -> None:
        candidates = {
            (year, number): {}
            for year in materialize.YEARS
            for number in range(1, materialize.EXPECTED_COUNTS[year] + 1)
        }
        materialize.validate_candidate_coverage(candidates)
        del candidates[(2022, 1)]
        with self.assertRaisesRegex(ValueError, "candidate_sequence_mismatch:2022"):
            materialize.validate_candidate_coverage(candidates)

    def test_validate_candidate_content_rejects_exam_instructions(self) -> None:
        candidates = {
            (year, number): {"stem": f"{number}. 真实物理题干"}
            for year in materialize.YEARS
            for number in range(1, materialize.EXPECTED_COUNTS[year] + 1)
        }
        materialize.validate_candidate_content(candidates)
        candidates[(2017, 2)]["stem"] = "2. 第一部分每小题选出答案后，用2B铅笔涂答题卡。"

        with self.assertRaisesRegex(ValueError, "candidate_exam_instruction_stem:2017:2"):
            materialize.validate_candidate_content(candidates)

    def test_answer_region_mode_marks_full_document_fallback(self) -> None:
        self.assertEqual(
            "whole_answer_document_pending_review",
            materialize.answer_region_mode((1, 2, 3), 3),
        )
        self.assertEqual(
            "question_anchor_page_candidate",
            materialize.answer_region_mode((2,), 3),
        )

    def test_candidate_detectors_keep_legacy_row_contract(self) -> None:
        row = {"question_type": "analysis_calculation", "stem_summary": "根据表1计算", "notes": ""}
        self.assertTrue(materialize.is_table_candidate(row))
        self.assertTrue(materialize.is_formula_candidate(row))

    def test_region_report_accepts_structured_takeover_entries(self) -> None:
        item = {
            "year": 2022,
            "sourceDocumentId": "c29bdd5f-a7b7-4cc1-bf59-e8ec297af1ea",
            "sourceFile": "2022广州中考.pdf",
            "manualTakeoverCandidates": [{"questionNumber": 1, "reason": "inferred"}],
            "questions": [],
        }
        plan = materialize._year_from_report(item)
        self.assertEqual(frozenset({1}), plan.manual_takeovers)

    def test_empty_pdf_has_no_eligible_answer_pages(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "empty.pdf"
            writer = PdfWriter()
            with path.open("wb") as stream:
                writer.write(stream)
            with self.assertRaisesRegex(ValueError, "answer_pdf_has_no_eligible_pages"):
                materialize.locate_answer_pages(path, 18)

    def test_extract_numbered_answer_sections_prefers_answer_marker(self) -> None:
        sections = materialize.extract_numbered_answer_sections(
            ["13. 题干\n【答案】甲；乙\n14. 题干\n答案：丙"],
            18,
        )
        self.assertEqual("甲；乙", sections[13])
        self.assertEqual("丙", sections[14])

    def test_extract_compact_choice_sequence_requires_exact_length(self) -> None:
        self.assertEqual(
            {index: value for index, value in enumerate("DCCDACBABDDD", start=1)},
            materialize.extract_compact_choice_sequence(["一、\nDCCDA CBABD DD"], 12),
        )
        self.assertEqual({}, materialize.extract_compact_choice_sequence(["ABCD"], 12))


if __name__ == "__main__":
    unittest.main()

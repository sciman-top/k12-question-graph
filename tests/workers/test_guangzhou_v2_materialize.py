from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

from pypdf import PdfWriter


TOOLS_ROOT = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS_ROOT))

import guangzhou_physics_v2_materialize as materialize  # noqa: E402


class GuangzhouV2MaterializeTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()

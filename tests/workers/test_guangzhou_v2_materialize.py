from __future__ import annotations

import sys
import tempfile
import unittest
import uuid
from pathlib import Path
from types import SimpleNamespace

from pypdf import PdfWriter


TOOLS_ROOT = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS_ROOT))

import guangzhou_physics_v2_materialize as materialize  # noqa: E402
import guangzhou_physics_v2_question_regions as question_regions  # noqa: E402
import real005b_reviewed_question_materialize as reviewed_materialize  # noqa: E402
import guangzhou_physics_v2_structured_extraction as structured_extraction  # noqa: E402
import guangzhou_physics_v2_region_text_extraction as region_text_extraction  # noqa: E402


class GuangzhouV2MaterializeTests(unittest.TestCase):
    def test_region_text_extraction_uses_question_anchor_and_ignores_diagram_labels(self) -> None:
        lines = [
            {"text": "A. 上一题选项", "pageNumber": 1, "bbox": [100, 500, 200, 512]},
            {"text": "2. 图1所示电路，开关闭合，灯均发光，则", "pageNumber": 1, "bbox": [100, 540, 400, 552]},
            {"text": "A. V示数等于V1示数", "pageNumber": 1, "bbox": [110, 560, 230, 572]},
            {"text": "B. V1示数大于V2示数", "pageNumber": 1, "bbox": [280, 560, 410, 572]},
            {"text": "C. A示数大于A1示数", "pageNumber": 1, "bbox": [110, 580, 230, 592]},
            {"text": "D. A2示数大于A1示数", "pageNumber": 1, "bbox": [280, 580, 410, 592]},
            {"text": "V1", "pageNumber": 1, "bbox": [220, 620, 240, 632]},
            {"text": "图1", "pageNumber": 1, "bbox": [260, 700, 285, 712]},
            {"text": "物理试卷 第 1 页 共 8 页", "pageNumber": 1, "bbox": [230, 740, 370, 752]},
        ]

        result = region_text_extraction.extract_choice_from_positioned_lines(lines, 2)

        self.assertEqual("图1所示电路，开关闭合，灯均发光，则", result.draft["stem"])
        self.assertEqual(
            ["V示数等于V1示数", "V1示数大于V2示数", "A示数大于A1示数", "A2示数大于A1示数"],
            [option["text"] for option in result.draft["options"]],
        )
        self.assertTrue(result.draft["structuredExtraction"]["visualAssetRequired"])

    def test_choice_extraction_requires_a_complete_ordered_four_option_sequence(self) -> None:
        pages = [
            {
                "pageNumber": 1,
                "layoutBlocks": [
                    {
                        "blockType": "question_stem",
                        "textPreview": "1. 关于声音，下列说法正确的是 A. 真空可以传声 B. 声音由振动产生",
                        "sourceRegion": {"source": "pdftotext_layout", "pageNumber": 1},
                    },
                    {
                        "blockType": "option",
                        "textPreview": "C. 声音在真空中传播最快 D. 响度只由频率决定",
                        "sourceRegion": {"source": "pdftotext_layout", "pageNumber": 1},
                    },
                    {
                        "blockType": "question_stem",
                        "textPreview": "2. 下列现象属于光的反射的是",
                        "sourceRegion": {"source": "pdftotext_layout", "pageNumber": 1},
                    },
                    {
                        "blockType": "option",
                        "textPreview": "A. 水中倒影 B. 日食现象 C. 彩虹 D. 小孔成像",
                        "sourceRegion": {"source": "pdftotext_layout", "pageNumber": 1},
                    },
                    {
                        "blockType": "question_stem",
                        "textPreview": "3. 如图所示，ABC 是三角形的顶点",
                        "sourceRegion": {"source": "pdftotext_layout", "pageNumber": 1},
                    },
                    {
                        "blockType": "question_stem",
                        "textPreview": "4. 如图所示的电路中",
                        "sourceRegion": {"source": "pdftotext_layout", "pageNumber": 1},
                    },
                    {
                        "blockType": "option",
                        "textPreview": "A. 灯泡发光 B. 电流表示数为零 C. 电压表示数为零 D. 电路图中的 R1 R2 图4",
                        "sourceRegion": {"source": "pdftotext_layout", "pageNumber": 1},
                    },
                    {
                        "blockType": "question_stem",
                        "textPreview": "5. 如图 5 所示，下列判断正确的是",
                        "sourceRegion": {"source": "pdftotext_layout", "pageNumber": 1},
                    },
                    {
                        "blockType": "option",
                        "textPreview": "A. 甲正确 B. 乙正确 C. 丙正确 D. 丁正确",
                        "sourceRegion": {"source": "pdftotext_layout", "pageNumber": 1},
                    },
                    {
                        "blockType": "question_stem",
                        "textPreview": "6. 根据下表中的实验数据判断正确的是",
                        "sourceRegion": {"source": "pdftotext_layout", "pageNumber": 1},
                    },
                    {
                        "blockType": "option",
                        "textPreview": "A. 甲正确 B. 乙正确 C. 丙正确 D. 丁正确",
                        "sourceRegion": {"source": "pdftotext_layout", "pageNumber": 1},
                    },
                ],
            }
        ]

        result = structured_extraction.extract_single_choice_drafts(
            pages,
            {1: "single_choice", 2: "single_choice", 3: "single_choice", 4: "single_choice", 5: "single_choice", 6: "single_choice"},
        )

        self.assertEqual("关于声音，下列说法正确的是", result.drafts[1]["stem"])
        self.assertEqual(
            ["真空可以传声", "声音由振动产生", "声音在真空中传播最快", "响度只由频率决定"],
            [option["text"] for option in result.drafts[1]["options"]],
        )
        self.assertEqual("choice_option_order_ambiguous", result.blockers[3])
        self.assertNotIn(3, result.drafts)
        self.assertEqual("visual_content_requires_layout_adapter", result.blockers[4])
        self.assertNotIn(4, result.drafts)
        self.assertEqual("visual_content_requires_layout_adapter", result.blockers[5])
        self.assertNotIn(5, result.drafts)
        self.assertEqual("table_requires_structure_adapter", result.blockers[6])
        self.assertNotIn(6, result.drafts)

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

    def test_2020_split_answer_starts_at_its_first_page(self) -> None:
        plan = SimpleNamespace(questions={24: [SimpleNamespace(page_number=8)]})
        paper = {"file_asset_id": "paper"}

        self.assertEqual(
            1,
            reviewed_materialize.answer_minimum_page(
                2020, plan, paper, {"file_asset_id": "answer"}
            ),
        )
        self.assertEqual(
            9,
            reviewed_materialize.answer_minimum_page(
                2020, plan, paper, {"file_asset_id": "paper"}
            ),
        )

    def test_page_number_only_detection_requires_no_visual_content(self) -> None:
        page_number_only = SimpleNamespace(
            extract_text=lambda: "第 9 页", images=[], rects=[], curves=[], lines=[]
        )
        page_with_image = SimpleNamespace(
            extract_text=lambda: "第 9 页", images=[{}], rects=[], curves=[], lines=[]
        )

        self.assertTrue(question_regions.is_trailing_page_number_only(page_number_only))
        self.assertFalse(question_regions.is_trailing_page_number_only(page_with_image))

    def test_source_page_report_batch_supports_legacy_and_generic_reports(self) -> None:
        batch_key = "guangzhou_physics_2015_2025_20260726_v2"

        self.assertTrue(question_regions.source_page_report_matches_batch(
            {"status": "pass", "materialBatchKey": batch_key}, batch_key
        ))
        self.assertTrue(question_regions.source_page_report_matches_batch(
            {
                "status": "pass",
                "documents": [
                    {"materialBatchKey": batch_key},
                    {"materialBatchKey": batch_key},
                ],
            },
            batch_key,
        ))
        self.assertFalse(question_regions.source_page_report_matches_batch(
            {
                "status": "pass",
                "documents": [
                    {"materialBatchKey": batch_key},
                    {"materialBatchKey": "other_batch"},
                ],
            },
            batch_key,
        ))

    def test_block_refresh_reuses_materialized_subquestion_id(self) -> None:
        question_id = "11111111-1111-1111-1111-111111111111"
        materialized_block_id = "22222222-2222-2222-2222-222222222222"
        blocks = materialize.build_blocks(
            {
                "legacyQuestionId": "QPHY-C003-2016-13",
                "stem": "题干",
                "subquestions": [
                    {
                        "subquestion_id": "QPHY-C003-2016-13-S01",
                        "subquestion_number": "1",
                        "stem_summary": "第一小问",
                    }
                ],
                "scoringRows": [],
            },
            uuid.UUID("33333333-3333-3333-3333-333333333333"),
            uuid.UUID("44444444-4444-4444-4444-444444444444"),
            question_id,
            materialized_blocks=[
                {
                    "id": materialized_block_id,
                    "block_type": "subquestion",
                    "sort_order": 1,
                    "content": {},
                }
            ],
        )

        subquestion = next(block for block in blocks if block["type"] == "subquestion")
        self.assertEqual(subquestion["content"]["questionBlockId"], materialized_block_id)

    def test_build_blocks_materializes_structured_choice_options_before_answer(self) -> None:
        blocks = materialize.build_blocks(
            {
                "legacyQuestionId": "QPHY-C003-2016-01",
                "stem": "下列说法正确的是",
                "options": [
                    {"label": "A", "text": "甲"},
                    {"label": "B", "text": "乙"},
                    {"label": "C", "text": "丙"},
                    {"label": "D", "text": "丁"},
                ],
                "answer": "B",
                "subquestions": [],
                "scoringRows": [],
            },
            uuid.UUID("33333333-3333-3333-3333-333333333333"),
            uuid.UUID("44444444-4444-4444-4444-444444444444"),
            "QPHY-C003-2016-01",
        )

        self.assertEqual(["stem", "option", "option", "option", "option", "answer"], [block["type"] for block in blocks])
        self.assertEqual(["A", "B", "C", "D"], [block["content"]["label"] for block in blocks[1:5]])

    def test_question_refresh_reuses_identity_when_source_file_is_renamed(self) -> None:
        existing_id = uuid.UUID("55555555-5555-5555-5555-555555555555")

        refreshed_id = reviewed_materialize.question_id(
            2020,
            1,
            "renamed-2020-paper.pdf",
            {(2020, 1): existing_id},
        )

        self.assertEqual(refreshed_id, existing_id)

    def test_queue_source_metadata_uses_current_document_not_stale_region_report_name(self) -> None:
        source = {
            "source_title": "2020广州中考",
            "original_file_name": "2020广州中考.pdf",
        }

        self.assertEqual("2020广州中考", reviewed_materialize.source_title_for_document(source))
        self.assertEqual("2020广州中考.pdf", reviewed_materialize.source_file_for_document(source))

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

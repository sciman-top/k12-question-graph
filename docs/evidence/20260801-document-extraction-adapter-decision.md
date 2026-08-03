# Guangzhou physics document extraction adapter decision

- status: adopted_for_incremental_evaluation
- production_eligible: false
- database_default_changed: false
- external_ai_calls: 0

## Root cause

The existing PDF worker produced page-level `question_stem` and `option` text, but the Guangzhou materializer continued to write legacy C003 stem summaries. Flattening a full page with `pdftotext -layout` also merged page furniture and diagram labels into question text. The failure was therefore at both boundaries: worker output was not consumed, and page text had no source-region coordinate model.

## Implemented path

1. `pdftotext_layout` remains the zero-new-dependency fallback. It now writes only complete, fail-closed pure-text A/B/C/D drafts.
2. `pymupdf_source_region_text` is the next digital-PDF adapter. It starts at the reviewed question-number anchor, preserves page/line bounding boxes, ignores preceding-question and page-furniture lines, and emits evaluation candidates only.
3. Full original question crops remain the visual source of truth. Figures, tables, formula-only options and ambiguous reading order remain blocked instead of being flattened into the stem.

Current measured results:

- 122 Guangzhou choice questions evaluated.
- 9 pure-text questions passed the strict `pdftotext_layout` write gate and were materialized as independent A/B/C/D blocks in `pending_review`.
- 85 coordinate-preserving drafts were produced by the PyMuPDF region adapter, but remain `review_required`; inspection found truncated or same-source OCR errors that prevent bulk database writes.
- 37 questions were blocked by missing anchors, incomplete/ambiguous options, or required table structure.

## Local reference decisions

| Local reference | Revision | Decision |
|---|---:|---|
| `document-ocr-ai/PaddleX` | `ffb6490`, `release/3.7` | Adopt PP-StructureV3 architecture for the next evaluation adapter: layout regions, reading order, OCR, tables, formulas and image assets. Apache-2.0; install/runtime admission still requires a golden-set comparison. |
| `document-ocr-ai/PaddleOCR` | `1e5aa0` manifest / `2661c7c` current checkout | Retain as official OCR/formula implementation reference. Do not call plain OCR a complete question parser. |
| `document-ocr-ai/RapidOCR` | `7b2d368` | Retain as lightweight offline OCR fallback for scanned pages. It does not supply reliable document layout or table structure by itself. |
| `document-ocr-ai/OCRmyPDF` | `5cb5d7a` | Adopt its preprocessing/text-layer workflow as the scanned-PDF front end before layout extraction. |
| `document-ocr-ai/docling` | `b108ca8` manifest / `873f990` current shared checkout | Keep as a structured-document comparison reference. Do not replace the exam-specific question-region and review contracts wholesale. |
| `document-ocr-ai/MinerU` | `79d6d8d`, `master` | Add as an optional, reference-only comparison for reading order, structured JSON, independent images/tables/formulas and layout visualization. Do not install its runtime, copy source, change the default route or bypass the PaddleX golden-set gate. Its custom license adds commercial thresholds and online-service attribution to Apache-2.0. |

Relevant official local source:

- `D:\CODE\external\k12-question-graph-references\document-ocr-ai\PaddleX\docs\pipeline_usage\tutorials\ocr_pipelines\PP-StructureV3.en.md`
- `D:\CODE\external\k12-question-graph-references\document-ocr-ai\PaddleX\paddlex\configs\pipelines\PP-StructureV3.yaml`
- `D:\CODE\external\k12-question-graph-references\document-ocr-ai\MinerU\README.md`
- `D:\CODE\external\k12-question-graph-references\document-ocr-ai\MinerU\LICENSE.md`
- `D:\CODE\external\k12-question-graph-references\document-ocr-ai\MinerU\docs\en\reference\output_files.md`

## Admission gate for PP-StructureV3

The adapter may become a default only after a fixed golden set proves complete question text, correct A/B/C/D order, independent figure assets, structured tables, formula fidelity, stable cross-page reading order, acceptable CPU/memory/runtime cost, and no regression against the full original crop. Until then, results stay `pending_review`, `productionEligible=false`, and `REAL005=not_closed`.

## Fixed Guangzhou layout baseline

The repository now has a minimal internal layout contract rather than another OCR route. Each block carries `paper/year/questionNumber/sourceRegionId/pageNumber/bbox/blockType/readingOrder/assetReference`; `sourceRegionId` and the full-question crop path reuse the current materializer identities. The fixed real-paper manifest covers complete stems, ordered A/B/C/D options, figure ownership, structured tables, formula text, cross-page order, header/footer isolation, original numbering, and subquestion relationships.

Fresh baseline evidence is `docs/evidence/20260801-guangzhou-physics-v2-layout-golden-eval.json`: 6 real questions, 13 assertions, 13 passed, 0 failed. This admits the narrow contract and evaluator only. It made 0 database writes, does not install or admit PaddleX/MinerU, and does not change the current `pending_review`, `productionEligible=false`, or `REAL005=not_closed` boundary. Full-corpus extraction accuracy, runtime/resource comparison, teacher review, and any provider-default decision remain open.

## Rollback

- Code rollback: revert only the structured/region extraction modules and their materializer integration.
- Data rollback for the 9-question write: restore `D:\KQG_Backups\20260801-001425\manifest.json` with `tools/restore.ps1`.

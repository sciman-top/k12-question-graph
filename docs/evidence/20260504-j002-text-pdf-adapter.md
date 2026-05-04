# J002 PDF 文本版解析 adapter 证据

## Goal
- 当前落点：`workers/document/worker.py`、`tools/j002_text_pdf_fixture.py`、`tools/run-j002-text-pdf-adapter-contract.ps1`、`tools/run-gates.ps1`。
- 目标归宿：文本 PDF 能稳定输出页码、文本区块顺序和来源定位。
- 本轮 slice：只覆盖 synthetic text PDF 的未压缩 text content stream；扫描版 PDF、图片 OCR 和复杂版式留给 J003/J004。

## Changes
- `worker.py` 增加 `.pdf` 分支，输出 `pdf_text_adapter`。
- 解析 PDF page object、content stream、`Tj` 文本操作，按 page object 顺序生成 `DocumentModel.pages`。
- 每个文本 block 带 `sourceRegion.source=pdf_text`、`pageObject`、`contentObject`、`textIndex`。
- 新增 text PDF golden fixture 和 J002 合同脚本。

## Verification
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-j002-text-pdf-adapter-contract.ps1`
- `python -m py_compile workers/document/worker.py tools/j001_openxml_docx_fixture.py tools/j002_text_pdf_fixture.py`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-gates.ps1`

## Risk And Rollback
- 风险等级：中。修改 document worker 分支行为，但限定 `.pdf` 文本流；`.docx` 和旧 `.txt` smoke 合同保留。
- 兼容性：保留 `document-model.v0.1`、`PageModel`、`LayoutBlock`、`AdapterDiagnostic`。
- 回滚：Git 回滚上述文件；无数据库、真实资料、真实 AI、权限、备份或 active switch 回滚需求。

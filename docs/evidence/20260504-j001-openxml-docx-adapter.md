# J001 OpenXML docx 真实解析 adapter 证据

## Goal
- 当前落点：`workers/document/worker.py`、`tools/j001_openxml_docx_fixture.py`、`tools/run-j001-openxml-docx-adapter-contract.ps1`、`tools/run-gates.ps1`。
- 目标归宿：`.docx` 不再走占位 raw_document；能从 OpenXML 输出稳定 `DocumentModel` 区块。
- 本轮 slice：只覆盖 synthetic golden `.docx` 的题干、选项、答案、解析、表格、公式；不处理 PDF/OCR/真实资料。

## Changes
- `worker.py` 增加 `.docx` 分支，使用 Python 标准库 `zipfile` 与 `xml.etree.ElementTree` 读取 `word/document.xml`。
- `.docx` 输出 `openxml_docx_adapter` 诊断；非 `.docx` 仍保留旧 placeholder smoke 行为。
- 新增 golden fixture 生成器和 J001 合同脚本。

## Verification
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-j001-openxml-docx-adapter-contract.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-gates.ps1`

## Risk And Rollback
- 风险等级：中。修改 worker adapter 行为，但限定 `.docx` 分支，旧 `.txt` smoke 保持。
- 兼容性：保留 `document-model.v0.1`、`PageModel`、`LayoutBlock`、`AdapterDiagnostic`。
- 回滚：Git 回滚上述文件；无数据库、真实资料、真实 AI、权限、备份或 active switch 回滚需求。

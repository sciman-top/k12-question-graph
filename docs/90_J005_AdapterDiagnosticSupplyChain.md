# 90 · J005 Adapter 版本诊断和工具供应链门禁

J005 锁定文档解析 adapter 的诊断字段和供应链边界。目标是每次解析都能追溯使用了哪个 adapter、哪个工具版本、什么输入参数、输入输出 hash、耗时、warnings 和 errors。

本合同只使用 synthetic fixture，不使用真实学生数据，不调用外部 AI，不调用云端 OCR/Docling，也不需要网络。扫描件 OCR 使用本地 `rapidocr_onnxruntime`。

## 合同

- Gate: `tools/run-j005-adapter-diagnostic-supply-chain-contract.ps1`
- Runner: `tools/j005_adapter_diagnostic_supply_chain.py`
- Evidence: `docs/evidence/j005-adapter-diagnostic-supply-chain-report.json`
- Fixtures: `tmp/j005-adapter-diagnostics/`

## 覆盖范围

- `openxml_docx_adapter`
- `pdf_text_adapter`
- `rapidocr_scanned_pdf_adapter`
- `rapidocr_image_adapter`
- `scanned_ocr_review_adapter`
- `placeholder_document_adapter`

每个 case 必须包含：

- `adapterName`
- `adapterVersion`
- `toolName`
- `toolVersion`
- `commandArgs`
- `durationMs`
- `inputSha256`
- `outputSha256`
- `warnings`
- `errors`

## 边界

当前 worker adapter 是本地 deterministic gate。扫描 PDF 先经 `pdftoppm` 渲染页图，再由 `rapidocr_onnxruntime` 识别；图片直接进入 `rapidocr_onnxruntime`。无效图片、OCR 引擎缺失或识别失败必须 fail-closed 到 `pending_review/takeoverRequired`，并记录 warning；不能把 OCR 缺失伪装成自动识别成功。

## 回滚

```powershell
git restore --source=HEAD -- README.md docs/20_TaskBreakdown.md tasks/backlog.csv tools/README.md tools/run-gates.ps1
git clean -fd -- tools/j005_adapter_diagnostic_supply_chain.py tools/run-j005-adapter-diagnostic-supply-chain-contract.ps1 docs/90_J005_AdapterDiagnosticSupplyChain.md docs/evidence/j005-adapter-diagnostic-supply-chain-report.json tmp/j005-adapter-diagnostics
```

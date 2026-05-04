# 2026-05-04 J003 扫描版 PDF 图片 OCR adapter

## 归宿与范围
- 当前落点：`J0 / J003`，在 `workers/document/worker.py` 增加扫描件 OCR 接管 adapter。
- 目标归宿：扫描版 PDF 或图片即使没有可抽取文本，也能输出可审阅候选、低置信度和人工接管证据。
- 本轮 slice：仅覆盖 synthetic scanned PDF 和 invalid image takeover；本机没有可用 OCR 引擎，不声明真实 OCR 识别准确率。
- 风险等级：低；不使用真实试卷、真实学生数据、真实 AI、数据库迁移或生产 active switch。

## 变更
- 新增 `scanned_ocr_review_adapter`。
- 扫描版 PDF 无 text stream 时输出 `ocr_candidate` block。
- 图片输入输出 `ocr_candidate` block；无效图片也进入 `pending_review` 接管。
- 每个候选写入 `confidence=0.0`、`reviewStatus=pending_review`、`takeoverRequired=true` 和 `sourceRegion`。
- 新增 synthetic fixture 与合同：`tools/run-j003-scanned-ocr-adapter-contract.ps1`。

## 证据
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-j003-scanned-ocr-adapter-contract.ps1`
- `python -m py_compile workers/document/worker.py tools/j003_scanned_ocr_fixture.py`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-gates.ps1`

## 回滚
- 代码回滚优先使用 Git。
- 删除 `tmp/j003-scanned-ocr/` synthetic fixture 输出即可清理本轮临时文件。
- J003 不写数据库、不写 active、不调用真实 OCR/AI。

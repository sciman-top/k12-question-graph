# 91 · J006 导入准确率基线与人工工作量报告

J006 形成导入准确率与人工工作量的代理基线。它用于后续 L003、M006、P002、P004 对比，不能被解读为真实教师现场验收，也不能被解读为真实 AI/OCR 自动切题准确率。

## 合同

- Gate: `tools/run-j006-import-accuracy-workload-contract.ps1`
- Runner: `tools/j006_import_accuracy_workload.py`
- Evidence: `docs/evidence/j006-import-accuracy-workload-report.json`
- Inputs:
  - `tests/golden-import/samples.json`
  - `docs/evidence/j001-openxml-docx-adapter-report.json`
  - `docs/evidence/j002-text-pdf-adapter-report.json`
  - `docs/evidence/j003-scanned-ocr-adapter-report.json`
  - `docs/evidence/j004-fidelity-regression-report.json`
  - `docs/evidence/j005-adapter-diagnostic-supply-chain-report.json`

## 当前基线

- Golden samples: 5
- Source region accuracy: 100%
- Block preservation accuracy: 100%
- Automated cut case count: 0
- Auto cut accuracy: N/A
- Real OCR text recognized: true
- Confirmation items: 6
- Failure takeover steps: 6
- Estimated teacher minutes: 7

`autoCutAccuracy` 保持 N/A 是有意设计：当前 J0 已启用本地 OCR 识别，但尚未建立扫描件自动切题 golden accuracy；因此不能宣称自动切题准确率。

## 教师效率边界

当前导入链路可证明来源、block、公式、表格和题图不会在 synthetic gate 中丢失，扫描文本可由本地 OCR 预填；但教师仍需处理合并、拆分、题图关联、公式密集项、扫描件校正和答案解析分离。

后续真实提升必须继续减少这些人工确认项，而不是把它们改名为 AI 自动完成。

## 回滚

```powershell
git restore --source=HEAD -- README.md docs/20_TaskBreakdown.md tasks/backlog.csv tools/README.md tools/run-gates.ps1
git clean -fd -- tools/j006_import_accuracy_workload.py tools/run-j006-import-accuracy-workload-contract.ps1 docs/91_J006_ImportAccuracyWorkload.md docs/evidence/j006-import-accuracy-workload-report.json
```

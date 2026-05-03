# 75 · E004 Word/PDF 导出 MVP

E004 建立 draft/test 试卷导出最小闭环。目标是先证明系统能生成可检查的 Word/PDF 工件，并保留公式、题图和表格的导出证据。

当前实现不依赖正式 C002 active，不声明生产试卷口径，也不实现完整排版引擎。

## 合同

- Gate: `tools/run-e004-paper-export-contract.ps1`
- Generator: `tools/e004_paper_export.py`
- UI marker: `data-flow="paper-export"`
- Mode: `draft_test`
- `productionEligible`: `false`
- 输出：
  - `tmp/e004-paper-export/kqg-e004-draft-test-paper.docx`
  - `tmp/e004-paper-export/kqg-e004-draft-test-paper.pdf`
  - `tmp/e004-paper-export/kqg-e004-draft-test-paper.manifest.json`
- Evidence: `docs/evidence/e004-paper-export-report.json`

## 验收

合同检查：

- DOCX 包含 `word/document.xml`。
- DOCX 包含公式文本 `F=ma`。
- DOCX 包含 `word/media/figure1.png` 题图媒体。
- DOCX 包含 Word 表格 XML。
- PDF 包含 `%PDF` header 和 `%%EOF`。
- 所有输出保持 `draft_test`、`productionEligible=false`。

## 后续归宿

E005 做导出前审校，E006 做导出黄金样本回归。正式生产导出仍要受 C002 source-derived activation guard 和来源授权约束控制。

## 回滚

```powershell
git restore --source=HEAD -- README.md apps/web/src/App.tsx apps/web/src/App.css docs/19_Roadmap.md docs/20_TaskBreakdown.md tasks/backlog.csv tools/README.md tools/run-gates.ps1
git clean -fd -- tools/e004_paper_export.py tools/run-e004-paper-export-contract.ps1 docs/75_E004_PaperExportMvp.md docs/evidence/e004-paper-export-report.json tmp/e004-paper-export
```

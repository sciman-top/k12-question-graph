# 89 · J004 公式/表格/题图保真回归

J004 补齐真实文档解析与导出之间的保真合同：从 synthetic OpenXML 导入样本解析出公式、表格和题图，组装成 `draft_test` question draft，再导出 Word/PDF 工件并验证关键元素未丢失。

本任务只验证结构链路，不使用真实学生数据，不调用外部 AI，不写数据库，也不声明生产导入口径。

## 合同

- Gate: `tools/run-j004-fidelity-regression-contract.ps1`
- Generator: `tools/j004_fidelity_regression.py`
- Input: `tmp/j004-fidelity/j004-import-golden.docx`
- Output:
  - `tmp/j004-fidelity/export/j004-export-regression.docx`
  - `tmp/j004-fidelity/export/j004-export-regression.pdf`
- Evidence: `docs/evidence/j004-fidelity-regression-report.json`

## 验收

- OpenXML adapter 输出 `formula`、`table`、`image` blocks。
- 题图 relationship target 保留到 `asset`。
- draft question 保持 `draft_test`、`productionEligible=false`。
- draft question 保留公式 block、表格 block、题图 asset 和 sourceRegion。
- 导出 DOCX 包含公式文本、`w:tbl` 表格和 `word/media/*` 题图媒体。
- 导出 PDF 至少通过 artifact header/EOF smoke，完整视觉保真继续归后续导出黄金样本。

## 教师效率边界

该回归避免教师在导入后重新补公式、重画表格或重新挂题图。失败时教师仍可回到人工确认队列修订，因为本合同不绕过 `pending_review/draft_test` 边界。

## 回滚

```powershell
git restore --source=HEAD -- workers/document/worker.py tools/run-gates.ps1 tasks/backlog.csv README.md docs/20_TaskBreakdown.md tools/README.md
git clean -fd -- tools/j004_fidelity_regression.py tools/run-j004-fidelity-regression-contract.ps1 docs/89_J004_FidelityRegression.md docs/evidence/j004-fidelity-regression-report.json tmp/j004-fidelity
```

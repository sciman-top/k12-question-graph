# 77 · F002 Excel 字段映射导入

F002 建立 synthetic Excel 成绩导入的最小闭环：生成可复用字段映射模板，解析小题分和总分，集中返回异常行，并把导入结果落到 draft/test 成绩表合同。

当前实现不使用真实学生姓名、学号、班级或成绩，不产生正式学情统计口径。

## 合同

- Gate: `tools/run-f002-score-import-contract.ps1`
- Fixture generator: `tools/f002_score_import_fixture.py`
- Tables:
  - `score_import_templates`
  - `score_import_batches`
  - `score_records`
  - `item_scores`
- Mode: `draft_test`
- `productionEligible`: `false`
- `realStudentDataUsed`: `false`
- 输出：
  - `tmp/f002-score-import/f002-synthetic-score-template.xlsx`
  - `tmp/f002-score-import/f002-score-field-mapping.json`
- Evidence: `docs/evidence/f002-score-import-report.json`

## 验收

合同检查：

- synthetic `.xlsx` 可生成并解析。
- 字段映射模板包含 `student_key`、`display_code`、`total_score`、`q1_score`、`q2_score`。
- 2 行 synthetic 成绩导入成功，1 行异常集中进入 `errors`。
- 字段映射作为动态资产保留 `version`、`reviewStatus`、迁移/回滚策略。
- DB 事务插入 template、batch、score record、item score 后回滚。
- `score_import_batches` 和 `score_records` 保持非生产、无 PII。

## 后续归宿

F003 在 `score_records` 和 `item_scores` 上计算得分率、区分度和 draft 知识点掌握摘要。正式知识点、标签和能力维度未 active 前，不改写正式历史学情。

## 回滚

```powershell
dotnet ef migrations remove --project apps/api/K12QuestionGraph.Api.csproj --startup-project apps/api/K12QuestionGraph.Api.csproj
git restore --source=HEAD -- apps/api/Domain/P0Entities.cs apps/api/Data/KqgDbContext.cs apps/api/Data/Migrations/KqgDbContextModelSnapshot.cs README.md docs/19_Roadmap.md docs/20_TaskBreakdown.md tasks/backlog.csv tools/README.md tools/run-gates.ps1
git clean -f -- tools/f002_score_import_fixture.py tools/run-f002-score-import-contract.ps1 docs/77_F002_ScoreImportMapping.md docs/evidence/f002-score-import-report.json
git clean -fd -- tmp/f002-score-import
```

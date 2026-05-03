# 76 · F001 学生班级考试模型

F001 建立 P5 成绩学情的最小数据骨架：学生、班级、考试和考试报名关系。当前只验证 draft/test 模式，不使用真实学生姓名、学号、班级或成绩。

## 合同

- Gate: `tools/run-f001-assessment-model-contract.ps1`
- Tables:
  - `students`
  - `class_groups`
  - `assessments`
  - `assessment_enrollments`
- Mode: `draft_test`
- `productionEligible`: `false`
- `realStudentDataUsed`: `false`
- `studentPortalExposed`: `false`
- Evidence: `docs/evidence/f001-assessment-model-report.json`

## 验收

合同检查：

- EF migration 已创建四张基础表。
- `students` 和 `class_groups` 支持 synthetic fixture 标记、匿名状态和 PII guard。
- `assessments` 保持 `draft_test`、`production_eligible=false`、`student_portal_enabled=false`。
- `assessment_enrollments` 能把 synthetic 学生、班级和考试关联起来。
- fixture 事务结束后回滚，不留下测试学生和成绩。
- API 不暴露 `/students` 或 `/student-portal` 学生端入口。

## 后续归宿

F002 在此模型上接入 synthetic Excel 字段映射导入；F003 再基于小题分和 draft 知识点输出基础学情分析。真实学生数据、正式统计口径和学生端能力都不属于当前 slice。

## 回滚

```powershell
dotnet ef migrations remove --project apps/api/K12QuestionGraph.Api.csproj --startup-project apps/api/K12QuestionGraph.Api.csproj
git restore --source=HEAD -- apps/api/Domain/P0Entities.cs apps/api/Data/KqgDbContext.cs apps/api/Data/Migrations/KqgDbContextModelSnapshot.cs README.md docs/19_Roadmap.md docs/20_TaskBreakdown.md tasks/backlog.csv tools/README.md tools/run-gates.ps1
git clean -f -- tools/run-f001-assessment-model-contract.ps1 docs/76_F001_AssessmentModel.md docs/evidence/f001-assessment-model-report.json
```

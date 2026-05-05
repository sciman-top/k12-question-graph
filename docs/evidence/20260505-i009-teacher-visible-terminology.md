# I009 教师可见术语语义漏检收口证据

## 依据

- `I009` 要求普通教师可见面不出现 `draft/test`、`draft 动态资产`、`medium/medium_hard`、`0.x` 难度区间、生产资格、状态枚举或后台审计语义。
- 本轮风险等级：低风险 UI 文案和合同收口；不新增功能、不改数据库、不调用真实 AI、不处理真实学生数据。

## 变更

- `apps/web/src/ui/teacherLabels.ts`
  - 集中教师可见标签映射。
  - 新增 `teacherDifficultyLabelFor()`，把内部难度值转为“难度偏基础 / 难度中等 / 难度略高”。
  - 新增 `teacherDifficultyRangeLabelFor()`，把内部数值区间转为“难度中等到略高”。
- `apps/web/src/App.tsx`
  - 移除本地重复 `displayText` 映射，统一使用 `teacherLabels.ts`。
  - 教师组卷理解文案不再显示 `draft 动态资产`。
  - 成绩分析摘要不再显示 `draft/test 报告`。
  - 细目表、筛选 chip、换题前后卡片不再显示 `0.x` 难度值或原始 `medium/medium_hard`。
- `tools/run-i008-teacher-simplification-contract.ps1`
  - 新增 `draft/test`、`draft 动态资产`、`medium_hard`、`生产资格`、`状态枚举` 等可见面阻断。
  - 新增 `medium` 和 `0.x` 数值难度正则阻断。
  - 要求 UI 使用集中教师难度标签 helper。

## 验证

```powershell
npm --prefix apps\web run build
npm --prefix apps\web run lint
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-i008-teacher-simplification-contract.ps1
dotnet build apps\api\K12QuestionGraph.Api.csproj
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-roadmap-guard.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-local-first-ai-guard.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-gates.ps1
```

结果：全部 pass。`tools/run-gates.ps1` 覆盖 backend build、frontend build/lint、I001-I008、roadmap dependency guard、local-first AI guard、C/D/E/F/G/O004 合同、P1 API smoke、P1 proxy scenario 和 backup verify。

## 回滚

- 默认 Git 回滚上述前端、合同和 evidence 文件。
- 本轮没有 DB migration、active switch、真实 AI 调用、真实学生数据写入或文件仓库清理。

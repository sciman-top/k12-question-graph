# I010 教师 shell 与后台治理面板拆分证据

## 目标

- 当前落点：`apps/web` 教师主界面与后台治理面板的前端边界。
- 目标归宿：普通教师 shell 只承载导入、组卷、成绩、分析等任务流；admin/source/activation/knowledge/storage/guardrail 能力进入独立后台组件。
- 本轮 slice：不新增功能、不改数据、不触发真实 AI，只拆 UI 代码路径并强化合同。

## 变更

- 新增 `apps/web/src/ui/AdminGovernancePanels.tsx`，集中承载后台治理、来源资料、学科激活、知识资产健康、存储和数据边界面板。
- `apps/web/src/App.tsx` 删除后台面板常量和内联 JSX，只保留 `<AdminGovernancePanels />` 挂载点；教师题卡难度继续通过 `teacherDifficultyLabelFor` 显示任务语言。
- `tools/run-i008-teacher-simplification-contract.ps1` 增加教师 shell 边界断言：`App.tsx` 不得重新内联 admin/source/activation/knowledge/storage/guardrail 面板。
- `K002/K003/K006/subject activation` UI 合同改为扫描 `App.tsx + AdminGovernancePanels.tsx` 的组合 UI 源，保持原后台能力合同覆盖。
- `tasks/backlog.csv` 新增并完成 `I010`；路线图、任务拆解和 handoff 同步把 I0 收口更新到 `I001-I010`。

## 验证

| 命令 | 结果 |
| --- | --- |
| `npm --prefix apps\web run build` | pass |
| `npm --prefix apps\web run lint` | pass |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-i008-teacher-simplification-contract.ps1` | pass |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-k002-c002r-teacher-revision-ux-contract.ps1` | pass |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-k003-mapping-review-workbench-ui-contract.ps1` | pass |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-k006-knowledge-asset-health-dashboard-contract.ps1` | pass |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-subject-activation-workbench-ui-contract.ps1` | pass |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-local-first-ai-guard.ps1` | pass |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-roadmap-guard.ps1` | pass |
| `dotnet build apps\api\K12QuestionGraph.Api.csproj` | pass, 0 warnings, 0 errors |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-gates.ps1` | pass |

## 风险与回滚

- 风险等级：低到中。仅前端结构拆分和合同扫描范围更新，不改数据库、API、备份、active 资产或真实 AI。
- 回滚：优先 `git revert` 本轮改动；无数据回滚动作。
- 后续守卫：继续保持 I008/I009/I010 合同通过；进入 P0-live 前仍需完成 `O004B` 角色权限与审计日志剩余闭环。

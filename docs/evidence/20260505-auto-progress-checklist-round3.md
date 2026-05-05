# 20260505 自动连续推进（清单任务）第 3 轮证据

## 目标
- 按 backlog 连续推进低风险、可验证的减法任务，不新增教师侧功能面。
- 优先收口已落盘 UI 代码中的重复结构，维持教师低学习成本和合同可验证性。

## 本轮改动
- `apps/web/src/ui/AdminGovernancePanels.tsx`
  - 新增 `sourceMetadataInputs`，将来源资料元数据输入项改为配置驱动渲染。
  - 新增 `storageStatusColor(cleanupAllowed)`，减少存储状态颜色内联判断。
- `apps/web/src/App.tsx`
  - 新增 `questionSearchFilterChips`，将题库检索筛选 chip 改为配置驱动渲染，减少重复按钮块。

## 验证命令
- `npm --prefix apps/web run build`
- `npm --prefix apps/web run lint`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-c002i-source-material-workbench-contract.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-g002-storage-cleanup-contract.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-i004-paper-workbench-ui-contract.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-i008-teacher-simplification-contract.ps1`

## 结果
- 上述命令通过。
- `run-c002i-source-material-workbench-contract.ps1` 首次执行出现 `dotnet ef database update` 瞬态失败；在 `dotnet build apps/api/K12QuestionGraph.Api.csproj` 通过后重跑即通过，判定为瞬态执行失败，非本轮前端减法引入。

## 回滚
- 代码回滚：`git revert <this-round-commit>`
- 证据回滚：删除本证据文件（如需保持证据连续性可保留）

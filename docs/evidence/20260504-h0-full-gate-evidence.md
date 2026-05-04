# 2026-05-04 H0 full gate 收口证据

## 规则 ID

- R1：当前落点为 `D:\CODE\k12-question-graph` H0 收口；目标归宿为 H0 后半段证据、I007 前端架构补强和后续 H-R 路线。
- R2：本轮只固化已执行 full gate 的证据和后续任务，不改运行代码。
- R4：数据库、备份、权限、active switch 和真实 AI 均按中高风险边界记录；本轮不执行新的生产切换或外部 AI 写入。
- R6：已按 `build -> test -> contract/invariant -> hotspot` 顺序执行；hotspot 无独立命令，改用受影响合同和教师效率复核记录。
- R8：依据、命令、证据和回滚如下。

## 已执行命令

```powershell
git status --short --branch
dotnet build apps/api/K12QuestionGraph.Api.csproj
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-gates.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-roadmap-guard.ps1
git diff --stat -- docs\evidence
```

## 关键结果

- `dotnet build apps/api/K12QuestionGraph.Api.csproj` 通过：0 warning，0 error。
- `tools\run-gates.ps1` 通过：最终 `status=pass`，覆盖 backend/frontend/worker/docs/roadmap/local-first AI/C002/C002R/domain activation/teacher template/backup 等合同。
- `tools\run-roadmap-guard.ps1` 通过：最终 `status=pass`。
- frontend build 存在非阻断警告：Vite 报告部分 chunk 超过 500 kB，主 JS 约 574.44 kB，gzip 约 185.29 kB。
- 处理决定：不把该警告当作 H0 阻断项，也不通过简单提高 `chunkSizeWarningLimit` 止血；已归入 `I007` 的 `bundle analysis` 和真实拆包验收。

## 数据、备份、AI、权限与 active switch

- 数据库：full gate 覆盖 DB smoke、EF migration 和 DB contracts；未记录新 migration 应用。
- 真实资料：C002 批次 `guangzhou_physics_2016_2025` 覆盖 33 份 source documents，hash 33/33；当前路径仍不把真实版权敏感材料提交进 Git。
- 备份包：生成并验证 `D:\KQG_Backups\20260504-104936\manifest.json`，同时存在 `database.dump`。
- 真实 AI：C002Q 仍为 local-first/draft/test 边界，`allowRealModelCalls=False`、`externalAiCalls=0`、`noActiveWrite=True`。
- active switch：C002T 为 dry-run/already active 状态，`alreadyActive=True`、`applied=False`、`activationGuardPassed=True`；本轮未执行新的生产 active 切换。
- 权限：G004 pgpass installer dry-run 通过；使用临时 APPDATA pgpass，`realUserPgpassModified=False`，并验证 `psql` 无密码提示路径。生产角色、审计和权限模型仍归后续 `O004`。

## 证据文件处理

- full gate 会刷新 `docs/evidence/*.json` 中的运行证据；若出现这些 JSON diff，应作为 H0 fresh gate evidence 保留，不按脏文件误判回滚。
- 本轮新增本 Markdown 证据，用于解释 full gate 结论、非阻断 Vite warning 和中高风险边界。

## 回滚

规划和证据层回滚优先 Git：

```powershell
git diff -- tasks/backlog.csv docs/88_EngineeringEndStateExternalReview_20260504.md docs/evidence/20260504-h0-full-gate-evidence.md docs/evidence
```

如需撤销本轮收口，只还原 `tasks/backlog.csv`、`docs/88_EngineeringEndStateExternalReview_20260504.md`、删除本证据文件，并按需还原 full gate 刷新的 `docs/evidence/*.json`。不要删除 `D:\KQG_Backups\20260504-104936\`，除非明确决定丢弃该次备份包。

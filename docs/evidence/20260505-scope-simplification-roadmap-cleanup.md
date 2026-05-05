# 2026-05-05 功能范围减法与任务清单收口证据

## 依据

- 用户要求：功能不是越多越好，普通教师默认低学习成本、低培训依赖。
- 审查发现：教师可见面仍有内部术语语义变体，`docs/20_TaskBreakdown.md` 存在过期独立任务，`O004` 待办范围与已落代码事实混杂。
- 风险等级：低风险规划层变更；不修改业务代码、不执行 DB migration、不触发真实 AI、不处理真实学生数据。

## 变更

- `docs/01_PRD.md`：补充减法目标和易上手成功指标，弱化“全自动”表述。
- `docs/02_MVP_Scope_and_ScopeControl.md`：明确 v0.1 功能清单不是教师首页清单，普通教师默认仍只有四入口。
- `docs/25_FeatureAdmissionCriteria.md`：增加培训依赖、入口/标签/确认步骤、内部状态外露等准入问题和自动后置条件。
- `docs/28_FunctionScopeReview.md`：追加 2026-05-05 低学习成本裁决，要求删除/合并计划噪声并拆分 O004 完成态。
- `docs/19_Roadmap.md`、`docs/87_PhaseCloseoutAndFullRoadmap.md`、`README.md`、`prompts/CODEX_CLI_HANDOFF.md`：同步 `I009` 和 `O004B` 阻断关系。
- `docs/20_TaskBreakdown.md`：把旧 `C003-C007`、`D004-D010`、`E005-E006`、`F004-F008` 标为已吸收/不再独立推进。
- `tasks/backlog.csv`：新增 `I009` 教师可见术语语义漏检收口；把 `O004` 改为已完成的 admin/internal fail-closed guard；新增 `O004B` 角色权限与审计日志剩余闭环；`P001` 改为依赖 `O004B;O006;O007`。

## 验证

```powershell
$rows=Import-Csv -LiteralPath tasks\backlog.csv -Encoding UTF8
```

结果：当时 `status=pass`，`total=134`，`done=89`，`todo=45`，`hasI009=true`，`hasO004B=true`，`P001.depends_on=O004B;O006;O007`，无重复 ID。随后 `I009` 代码层已完成，最新完成数见 `docs/evidence/20260505-i009-teacher-visible-terminology.md`。

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-roadmap-guard.ps1
```

结果：`status=pass`。

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-o004-admin-internal-auth-boundary-contract.ps1
```

结果：`status=pass`，`pilotLiveNakedEndpointsBlocked=true`。

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-i008-teacher-simplification-contract.ps1
```

结果：`status=pass`。注意：本轮新增 `I009` 正是为了修补 I008 仍未覆盖 `draft/test`、`draft 动态资产`、`medium_hard` 和数值难度区间等语义漏检。

## 回滚

- 默认 Git 回滚上述文档和 `tasks/backlog.csv`。
- 本轮没有 DB migration、active switch、真实 AI 调用、真实学生数据写入或文件仓库清理。

# 2026-05-04 H002 full gate 与 quick gate 基线刷新

## 规则 ID

- R1：当前落点为 H0 阶段收口的 `H002`；目标归宿是形成 full gate 与 quick gate 的 fresh baseline。
- R2：本轮只固化门禁基线和 backlog 状态，不改运行功能。
- R4：门禁执行会访问数据库、备份和临时凭据路径；本轮不执行新的生产 active switch，不调用真实外部 AI，不处理真实学生数据。
- R6：已按项目门禁顺序保留 full gate 证据，并补跑 quick dry-run suite 与 roadmap guard。
- R8：依据、命令、证据和回滚如下。

## baseline 结论

- full gate：`tools\run-gates.ps1` 已在 2026-05-04 当前 H0 收口窗口执行并通过，最终 `status=pass`。
- quick gate：`tools\run-c002-dry-run-suite.ps1` 本轮执行并通过，最终 `status=pass`。
- contract/invariant：`tools\run-roadmap-guard.ps1` 在 H001 后复跑通过，最终 `status=pass`。
- gate_na：无。当前机器具备数据库和 quick dry-run 所需环境，因此 H002 不需要降级为 `gate_na`。
- 已知非阻断警告：frontend build 中 Vite chunk warning 已归入 `I007 bundle analysis`，不作为 H002 阻断项。

## full gate 证据

- 证据说明：`docs/evidence/20260504-h0-full-gate-evidence.md`
- 备份 manifest：`D:\KQG_Backups\20260504-104936\manifest.json`
- 数据库 dump：`D:\KQG_Backups\20260504-104936\database.dump`
- 关键结论：backend/frontend/worker/docs/roadmap/local-first AI/C002/C002R/domain activation/teacher template/backup 等合同均通过。
- 数据边界：真实外部 AI 调用为 0；真实学生数据未使用；C002T 为 already active/dry-run 复核边界，本轮未执行新的生产切换。

## quick gate 关键输出

`tools\run-c002-dry-run-suite.ps1` 输出：

```json
{
  "status": "pass",
  "suite": "c002-dynamic-assets-dry-run",
  "databaseRequired": false,
  "productionActivationAllowed": false
}
```

覆盖步骤：

- `c002 source material admission guard`
- `c002b replacement mapping contract`
- `c002c migration impact contract`
- `c002d source-derived admission contract`
- `c002e activation guard contract`
- `c002h mapping review workbench contract`

## 已执行命令

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-c002-dry-run-suite.ps1
Get-Item -Path D:\KQG_Backups\20260504-104936\manifest.json, D:\KQG_Backups\20260504-104936\database.dump
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-roadmap-guard.ps1
```

## 回滚

```powershell
git diff -- tasks/backlog.csv docs/evidence/20260504-h002-gate-baseline-refresh.md
```

如需撤销 H002 收口，只把 `tasks/backlog.csv` 中 `H002` 状态改回 `待办`，并删除本证据文件。本轮未修改运行代码、数据库、备份包、真实资料、权限或 active 状态。

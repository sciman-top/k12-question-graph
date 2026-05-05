# O004B 角色权限与审计日志闭环证据（2026-05-05）

- 规则 ID: `O004B`
- 风险等级: 高
- 当前落点: `角色权限与审计日志`
- 目标归宿: 试点/live 前，后台高风险操作必须具备角色分离与结构化审计留痕。

## 执行命令

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-o004b-role-audit-closure-contract.ps1
```

## 关键输出摘要

- `status=pass`
- 角色分离结果：
  - `teacher` 访问 `/api/admin/*` 被阻断（403）
  - `group_lead` 可读 `/api/admin/storage/summary`（200）
  - `group_lead` 写 `/api/admin/cache/cleanup` 被阻断（403）
  - `admin` 可执行高风险写操作（200）
  - `/internal/ai/*` 限 `admin`（group_lead 403，admin 200）
- 审计日志：`tmp/o004b/logs/admin-internal-audit.jsonl`
  - `entryCount=6`
  - 每条包含 `timestampUtc/path/method/operatorRole/operatorId/objectRef/decision/statusCode`
  - 覆盖高风险写操作与 `rollbackRef` 字段

## 配置与代码落点

- `apps/api/appsettings.json`
- `apps/api/appsettings.Development.json`
- `apps/api/Program.cs`

新增 `AdminInternalRoleAudit` 配置与守卫逻辑，默认开启 fail-closed 角色头与操作人头校验，并记录结构化审计日志。

## 回滚动作

```powershell
git restore -- apps/api/Program.cs apps/api/appsettings.json apps/api/appsettings.Development.json tools/run-o004b-role-audit-closure-contract.ps1 tools/run-gates.ps1 tools/README.md tasks/backlog.csv docs/evidence/20260505-o004b-role-audit-closure.md
Remove-Item -LiteralPath 'D:\CODE\k12-question-graph\tmp\o004b' -Recurse -Force
```

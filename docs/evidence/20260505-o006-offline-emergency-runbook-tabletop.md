# O006 离线应急手册和演练证据（2026-05-05）

- 规则 ID: `O006`
- 风险等级: 中
- 当前落点: `离线应急手册和演练`
- 目标归宿: 管理员可按 runbook 在离线场景执行 WinPE 拷贝、备份校验与恢复 dry-run，并具备失败回退路径。

## 执行命令

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-o006-offline-emergency-runbook-tabletop-contract.ps1
```

## 关键输出摘要

- `status=pass`
- 依赖链：`G003 pass`、`O003 already_completed`
- runbook 检查：`runbooks/WinPE_EmergencyRecovery.md` 必需指令齐全
- tabletop 场景：3 个（Windows 无法启动 / manifest hash 不匹配 / restore apply 失败）
- 证据链：
  - G003 介质 manifest
  - backup manifest
  - `verify-backup=ok`
  - `restore.ps1 mode=dry_run`

## 新增恢复入口

- `tools/restore.ps1`
  - 默认 `dry_run`
  - 支持 `-ApplyDatabase -ApplyFileStore -ApplyConfigs`
  - 仅显式 `-DryRun:$false` 时才执行 apply

## 回滚动作

```powershell
git restore -- tools/restore.ps1 tools/run-o006-offline-emergency-runbook-tabletop-contract.ps1 runbooks/WinPE_EmergencyRecovery.md tools/run-gates.ps1 tools/README.md tasks/backlog.csv docs/evidence/20260505-o006-offline-emergency-runbook-tabletop.md
Remove-Item -LiteralPath 'D:\KQG_Backups\20260505-183035' -Recurse -Force
```

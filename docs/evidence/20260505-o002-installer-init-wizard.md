# O002 安装初始化向导合同证据（2026-05-05）

- 规则 ID: `O002`
- 风险等级: 中
- 当前落点: `安装初始化向导`
- 目标归宿: 在新机器初始化时可完成 PostgreSQL 连接参数、数据目录、备份目录、pgpass 与管理员引导 key 的可验证初始化。

## 执行命令

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-o002-installer-init-wizard-contract.ps1
```

## 关键输出摘要

- `status=pass`
- 配置入口: `configs/installer_init.defaults.yaml`
- 目录可写验证通过:
  - `D:\KQG_Data`
  - `D:\KQG_Backups`
  - `D:\KQG_Data\file_store`
  - `D:\KQG_Data\logs`
  - `D:\KQG_Data\cache`
- 嵌套 `G004` pgpass dry-run 通过，证据: `docs/evidence/o002-installer-pgpass-dry-run-report.json`
- 管理员引导 key 仅输出 `SHA256`，不落地明文。

## 兼容性与边界

- 仅 `draft_test` 合同验证，不等同于试点部署完成。
- `O004B`（RBAC 与审计日志）仍为阻断项，`O002` 仅完成安装初始化层。

## 回滚动作

```powershell
Remove-Item -LiteralPath 'D:\KQG_Data' -Recurse -Force
Remove-Item -LiteralPath 'D:\KQG_Backups' -Recurse -Force
```

`pgpass` 回滚与清理由 `docs/evidence/o002-installer-pgpass-dry-run-report.json` 提供。

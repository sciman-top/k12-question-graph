# O007 EF migration bundle 与升级演练证据（2026-05-05）

- 规则 ID: `O007`
- 风险等级: 高
- 当前落点: `EF migration bundle 与升级演练`
- 目标归宿: 发布包可在无源码目录依赖场景执行迁移，并具备备份/校验/恢复演练链路。

## 执行命令

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-o007-ef-migration-bundle-upgrade-contract.ps1
```

## 关键输出摘要

- `status=pass`
- `efbundle` 产物：`tmp/o007/bundle/efbundle.exe`
- 发布目录：`tmp/o007/release-package/migrations`
  - `efbundle.exe`
  - `appsettings.json`
- bundle 执行日志：`tmp/o007/efbundle-run.log`
  - 关键结果：`No migrations were applied. The database is already up to date.`
- 备份与校验：
  - `tmp/o007/backup-root/20260505-165247/manifest.json`
  - `backup verify: pass`
- 恢复演练联动：`docs/evidence/o007-o003-recovery-drill-report.json`（嵌套 O003）

## 兼容性与边界

- 本轮为 `draft_test` 升级演练，未执行生产不可逆变更。
- 已证明可通过 bundle 运行迁移链路，并补齐 backup + restore drill 证据。

## 回滚动作

```powershell
Remove-Item -LiteralPath 'D:\CODE\k12-question-graph\tmp\o007' -Recurse -Force
```

如真实升级失败，按 backup manifest 恢复数据库和文件仓库后再重跑 bundle。

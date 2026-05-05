# O003 恢复演练升级证据（2026-05-05）

- 规则 ID: `O003`
- 风险等级: 中
- 当前落点: `恢复演练升级`
- 目标归宿: 从 backup manifest 在隔离目录完成数据库、文件仓库、配置、模板和教师偏好的恢复演练。

## 执行命令

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-o003-recovery-drill-contract.ps1
```

## 关键输出摘要

- `status=pass`
- 备份产物：
  - `tmp/o003/backup-root/20260505-161901/manifest.json`
  - `tmp/o003/backup-root/20260505-161901/database.dump`
- 恢复演练隔离目录：`tmp/o003/restore-drill`
- 数据库恢复可执行性：
  - `tmp/o003/restore-drill/database/database.restore-plan.txt`（`pg_restore -l`）
  - `tmp/o003/restore-drill/database/database.schema-only.sql`（`pg_restore --schema-only`）
- 文件仓库恢复：`restoredFileCount=627`
- 配置恢复：`restoredConfigCount=3`
- 模板恢复：`docs/templates -> tmp/o003/restore-drill/templates`
- 教师偏好恢复：
  - `configs/teacher_preference.defaults.yaml`
  - `tmp/o003/restore-drill/teacher-preference/teacher_preference.defaults.yaml`

## 兼容性判断

- 本轮只在 `tmp/o003/*` 做恢复演练，不覆盖生产目录，不执行 active switch。
- 满足 O003 的“隔离恢复演练 + hash verify”要求，为 O006/O007 提供前置证据。

## 回滚动作

```powershell
Remove-Item -LiteralPath 'D:\CODE\k12-question-graph\tmp\o003\backup-root' -Recurse -Force
Remove-Item -LiteralPath 'D:\CODE\k12-question-graph\tmp\o003\restore-drill' -Recurse -Force
```

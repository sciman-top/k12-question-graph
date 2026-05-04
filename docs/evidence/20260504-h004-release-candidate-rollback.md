# 2026-05-04 H004 发布候选和回滚包收口

## 规则 ID

- R1：当前落点为 H0 阶段收口的 `H004`；目标归宿是形成 release candidate notes、可校验 backup manifest 和回滚命令。
- R2：本轮只生成新的备份包和证据，不改运行功能。
- R4：备份和恢复证据属于中风险运维面；本轮只执行 backup/verify，不执行 restore apply、不做 active switch、不调用真实 AI。
- R6：H004 复用 H002 full/quick gate baseline，并新增 release candidate backup verify。
- R8：依据、命令、证据和回滚如下。

## release candidate 结论

- release candidate：`H0-RC-20260504-110313`
- 对应分支：`codex/c002-quality-review-overlay`
- 门禁基线：H002 已记录 full gate `status=pass`、quick gate `status=pass`、roadmap guard `status=pass`。
- 教师效率基线：H003 已记录代理 baseline，不是现场教师实测。
- gate_na：无。
- 已知非阻断项：Vite chunk warning 已归入 `I007 bundle analysis`；生产角色/审计权限归 `O004`；EF migration bundle/升级演练归 `O007`；真实 AI 安全红队归 `L007`。

## 备份包

旧 H002 full gate 备份：

- `D:\KQG_Backups\20260504-104936\manifest.json`
- `D:\KQG_Backups\20260504-104936\database.dump`

H004 初次校验旧 manifest 失败：

```text
hash mismatch: D:\CODE\k12-question-graph\tasks\backlog.csv
```

原因：H001-H003 已更新 `tasks/backlog.csv`，旧 manifest 中的配置 hash 已过期。处理方式是生成新的 release-candidate backup，而不是忽略 hash mismatch。

新 H004 release-candidate backup：

- manifest：`D:\KQG_Backups\20260504-110313\manifest.json`
- database dump：`D:\KQG_Backups\20260504-110313\database.dump`
- file store count：413
- config count：3

新 manifest 校验结果：

```json
{
  "status": "ok",
  "manifest": "D:\\KQG_Backups\\20260504-110313\\manifest.json",
  "fileCount": 413,
  "configCount": 3
}
```

## 已执行命令

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\verify-backup.ps1 -ManifestPath D:\KQG_Backups\20260504-104936\manifest.json
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\backup.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\verify-backup.ps1 -ManifestPath D:\KQG_Backups\20260504-110313\manifest.json
```

## 回滚入口

代码/文档层：

```powershell
git diff -- tasks/backlog.csv docs/evidence/20260504-h004-release-candidate-rollback.md
```

数据层：

- 当前 release-candidate restore point 为 `D:\KQG_Backups\20260504-110313\manifest.json`。
- 执行任何数据库 restore 前必须先新建当前状态备份，再在隔离数据库或明确维护窗口中演练。
- 本轮没有执行 restore apply；真实恢复演练仍归 O0/O007。

如需撤销 H004 收口，只把 `tasks/backlog.csv` 中 `H004` 状态改回 `待办`，并删除本证据文件。不要删除 `D:\KQG_Backups\20260504-110313\`，除非明确决定丢弃该 release-candidate backup。

# 37 · A009 备份脚本与 Manifest 证据

执行日期：2026-05-02。

## 1. 完成范围

- 新增 `tools/backup.ps1`。
- 新增 `tools/verify-backup.ps1`。
- 备份内容覆盖 PostgreSQL dump、FileStore 文件清单、配置文件 sha256。
- 校验失败会返回失败，不报告成功。

## 2. Backup Smoke

```powershell
$env:PGPASSWORD='postgres'
.\tools\backup.ps1
```

关键输出：

```json
{
  "backupDir": "D:\\KQG_Backups\\20260502-234648",
  "manifest": "D:\\KQG_Backups\\20260502-234648\\manifest.json",
  "databaseDump": "D:\\KQG_Backups\\20260502-234648\\database.dump",
  "fileCount": 9,
  "configCount": 3
}
```

## 3. Verify Smoke

```powershell
.\tools\verify-backup.ps1 -ManifestPath 'D:\KQG_Backups\20260502-234648\manifest.json'
```

关键输出：

```json
{"status":"ok","fileCount":9,"configCount":3}
```

失败路径：

```text
missing manifest: verify failed as expected
```

## 4. 回滚

代码回滚：

```powershell
git restore --source=HEAD -- tools/README.md tasks/backlog.csv docs/31_A000_to_A003_Execution_Log.md
```

删除本轮备份：

```powershell
Remove-Item -LiteralPath 'D:\KQG_Backups\20260502-234648' -Recurse -Force
```

## 5. 剩余注意事项

- 当前 verify 校验的是现行配置文件 hash；如果配置在备份后发生合法变更，应把恢复校验模式和当前环境校验模式拆开。
- A010 应把 backup/verify 纳入统一 gate。

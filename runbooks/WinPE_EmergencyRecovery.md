# WinPE 应急恢复手册

## 场景

Windows 无法启动，主程序无法打开。

## 处理步骤

1. 使用 WinPE U 盘启动。
2. 找到数据目录：`D:\KQG_Data\`。
3. 从最近备份目录或数据盘手动拷贝以下目录到恢复盘：
   - database_backups
   - file_store
   - config
   - templates
   - prompts
   - ai_rules
   - teacher_profiles
   - recovery
4. 拷贝到外置硬盘或局域网共享目录。
5. 重装/修复 Windows。
6. 安装校本题谱。
7. 先运行 `verify-backup.ps1` 校验最近 `manifest.json`。
8. 校验通过后运行 `restore.ps1` 恢复。

推荐先执行 dry-run（默认）：

```powershell
.\tools\restore.ps1 -ManifestPath D:\KQG_Backups\<timestamp>\manifest.json -ApplyDatabase -ApplyFileStore -ApplyConfigs
```

仅在维护窗口确认后再显式去掉 dry-run：

```powershell
.\tools\restore.ps1 -ManifestPath D:\KQG_Backups\<timestamp>\manifest.json -ApplyDatabase -ApplyFileStore -ApplyConfigs -DryRun:$false
```

## 注意

如果没有 pg_dump 备份，只能尝试抢救 PostgreSQL 数据目录，但优先恢复 pg_dump 备份。

恢复现场只使用 copy-only 拷贝，不做镜像删除；不要追加会删除目标介质既有内容的参数。

# WinPE 应急恢复手册

## 场景

Windows 无法启动，主程序无法打开。

## 处理步骤

1. 使用 WinPE U 盘启动。
2. 找到数据目录：`D:\KQG_Data\`。
3. 先在正常 Windows 环境中生成恢复介质材料：

   ```powershell
   .\tools\run-g003-winpe-emergency-copy-contract.ps1
   ```

   将 `tmp\g003-winpe-recovery-media\KQG_RecoveryMedia` 放到恢复 U 盘或管理员工具盘。
4. 在 WinPE 中运行 `KQG_EmergencyCopy.cmd E:\KQG_EmergencyCopy`，或手动拷贝以下目录：
   - database_backups
   - file_store
   - config
   - templates
   - prompts
   - ai_rules
   - teacher_profiles
   - recovery
5. 拷贝到外置硬盘或局域网共享目录。
6. 重装/修复 Windows。
7. 安装校本题谱。
8. 先运行 `verify-backup.ps1` 校验最近 `manifest.json`。
9. 校验通过后运行 `restore.ps1` 恢复。

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

G003 生成的脚本只使用 copy-only 拷贝策略，不做镜像删除；不要在恢复现场追加会删除目标介质既有内容的参数。

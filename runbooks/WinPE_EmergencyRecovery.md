# WinPE 应急恢复手册

## 场景

Windows 无法启动，主程序无法打开。

## 处理步骤

1. 使用 WinPE U 盘启动。
2. 找到数据目录：`D:\KQG_Data\`。
3. 运行 `KQG_EmergencyCopy.cmd` 或手动拷贝以下目录：
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
7. 运行 restore.ps1 恢复。
8. 运行 verify-backup.ps1 校验。

## 注意

如果没有 pg_dump 备份，只能尝试抢救 PostgreSQL 数据目录，但优先恢复 pg_dump 备份。

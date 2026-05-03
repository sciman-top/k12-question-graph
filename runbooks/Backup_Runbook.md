# 备份运行手册

## 日常自动备份

1. 每天凌晨执行数据库 pg_dump。
2. 复制文件仓库到本机备份目录。
3. 复制配置、模板、教师偏好、prompt、规则。
4. 生成 manifest.json 和 checksums.sha256。
5. 校验备份包。
6. 同步到局域网共享目录。
7. 清理过期备份。

## 网络共享失败

1. 保留本机备份。
2. 写入失败日志。
3. 通知管理员。
4. 下次自动重试。

## G001 当前合同

```powershell
.\tools\run-g001-backup-share-contract.ps1
```

该合同会：

1. 使用 `tools/backup.ps1` 生成本机备份。
2. 使用 `tools/verify-backup.ps1` 校验本机 manifest/hash。
3. 复制备份包到可配置共享目录，当前默认用 `tmp/g001-backups/shared` 模拟。
4. 再次校验共享目录副本 manifest/hash。
5. 明确不启动 Web/API 主程序，不删除共享目录既有内容。

证据写入 `docs/evidence/g001-backup-share-report.json`。

## 禁止

- 不要用镜像覆盖作为唯一备份。
- 不要在脚本中明文保存共享目录密码。
- 不要只备数据库而不备文件仓库。

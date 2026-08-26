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

## 当前入口

```powershell
.\tools\backup.ps1
.\tools\verify-backup.ps1 -ManifestPath D:\KQG_Backups\<timestamp>\manifest.json
```

`backup.ps1` 生成数据库、FileStore、配置和必要模板快照；`verify-backup.ps1` 校验 manifest/hash。局域网共享复制属于部署环境操作，不再用仓库内模拟合同重复验证。

## 运行时密文配置的受控排除（策略 b）

- 备份与恢复**不包含** `DataRoot\config`（含 `ai-provider-settings.local.json` 密文与 Data Protection key ring）。manifest 的 `runtimeConfig` 节按策略 b 声明该排除；`verify-backup.ps1` 会校验声明存在且形状正确，缺失即失败。
- 恢复后 AI 一律处于 `disabled/pending_review`（无密钥即阻断真实模型调用）。管理员必须重新录入 AI 路由设置与 provider secret，或从受控 secret source 注入，再由管理界面重新试跑确认；在此之前不得开启 `allowRealModelCalls`。
- 非敏感 AI 路由设置与 provider secret 的恢复状态在 `runtimeConfig` 中分开记录（`aiRoutingSettings` / `providerSecrets`），不得合并为单一"配置已恢复"结论。
- 数据库恢复 apply 需 `-PreRestoreSnapshotTaken`（先跑 `backup.ps1` 做恢复前快照），`pg_restore` 以 `--single-transaction` 执行，中途失败不落半恢复状态。
- 仅当部署方明确提出"AI 无人工恢复"的 RTO 要求后，才立项切换到策略 (a)：密文与 key material 纳入 ACL 保护的备份组、恢复到真实读取路径，并以新进程实际解密成功为验收。

## 禁止

- 不要用镜像覆盖作为唯一备份。
- 不要在脚本中明文保存共享目录密码。
- 不要只备数据库而不备文件仓库。

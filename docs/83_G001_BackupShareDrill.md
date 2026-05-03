# 83 · G001 自动备份到本机与共享目录

G001 建立 P6 运维的最小备份演练：主程序不可用时，管理员仍可用脚本生成本机备份、复制到可配置共享目录，并分别通过 manifest/hash 校验。

当前实现只做 draft/test 备份演练，默认共享目录使用 `tmp/g001-backups/shared` 模拟，不删除共享目录既有内容。

## 合同

- Gate: `tools/run-g001-backup-share-contract.ps1`
- Reused scripts:
  - `tools/backup.ps1`
  - `tools/verify-backup.ps1`
- Config: `configs/backup_policy.defaults.yaml`
- Mode: `draft_test`
- `apiStarted`: `false`
- `productionEligible`: `false`
- Evidence: `docs/evidence/g001-backup-share-report.json`
- Temp output:
  - `tmp/g001-backups/local/<run-id>/.../manifest.json`
  - `tmp/g001-backups/shared/<run-id>/.../manifest.json`

## 验收

合同检查：

- `backup_policy.defaults.yaml` 暴露 `network_share` 配置位。
- `no_mirror_delete_to_network_share=true`。
- 本机备份 manifest 通过 `tools/verify-backup.ps1`。
- 共享目录副本 manifest 通过 `tools/verify-backup.ps1`。
- 本机与共享副本的 database dump sha256 一致。
- 备份包含数据库 dump、FileStore 清单和配置 hash。
- 演练不启动 Web/API 主程序。

## 回滚

```powershell
git restore --source=HEAD -- README.md docs/14_BackupRecoveryMigration.md docs/19_Roadmap.md docs/20_TaskBreakdown.md runbooks/Backup_Runbook.md tasks/backlog.csv tools/run-gates.ps1
git clean -f -- tools/run-g001-backup-share-contract.ps1 docs/83_G001_BackupShareDrill.md docs/evidence/g001-backup-share-report.json
git clean -fd -- tmp/g001-backups
```

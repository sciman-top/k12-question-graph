# G003 · WinPE 应急拷贝脚本生成

G003 建立 WinPE 场景下的离线恢复材料生成合同。目标不是执行真实恢复，而是让管理员能提前生成 U 盘可携带的拷贝脚本和说明。

## 合同入口

- Config: `configs/recovery_media.defaults.yaml`
- Gate: `tools/run-g003-winpe-emergency-copy-contract.ps1`
- Evidence: `docs/evidence/g003-winpe-emergency-copy-report.json`
- Runbook: `runbooks/WinPE_EmergencyRecovery.md`

## 生成内容

合同脚本会生成 draft/test 恢复介质目录：

```text
tmp/g003-winpe-recovery-media/KQG_RecoveryMedia/
  KQG_EmergencyCopy.cmd
  KQG_EmergencyCopy.ps1
  README-WinPE.txt
  recovery-media-manifest.json
```

该目录是可再生成的临时产物，不提交 Git。正式打包恢复介质前，管理员应重新运行合同脚本并保存当次 evidence。

## 安全边界

- 只生成脚本，不执行真实拷贝。
- 拷贝源和目标来自配置或命令参数，不写死到教师 UI。
- 脚本使用 copy-only 策略，不删除目标介质既有内容。
- 恢复前必须先用 `verify-backup.ps1` 校验最近 `manifest.json`。

## 回滚

代码回滚使用 `git revert` 对应 G003 提交。临时产物可删除 `tmp/g003-winpe-recovery-media`，不得把该删除动作扩展到真实备份目录或恢复介质。

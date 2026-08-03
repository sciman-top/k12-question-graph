# Implementation Plan: P001 External/Onsite Handoff

## Objective

在不重复扩建治理脚本的前提下，把已完成的 VGOV-001..010 repo-side 验证治理成果交给 P001 隔离机部署与现场链路。AI 可以准备、校验和导入证据，但不能合成现场事实或代签。

## Current truth

- VGOV-001..010 均为 `已完成`；没有剩余 repo-side VGOV task。
- 日常 AI 编码只使用 `Quick` 或 task/changed-path `Slice`。
- legacy inventory 当前 208 steps 已完整映射：Quick=7、Release=201、unmapped=0；历史基线 235 中的未来治理节点已退役，该数字不描述默认 Release coverage。
- 历史授权 legacy Release 用时 1456402 ms，并写入 FileStore 159 个文件、9024094 bytes；默认 Release 已因此改为 3 阶段 focused core，legacy 仅显式审计。
- 默认 Release 报告和 isolated backup/restore 工件只进 `tmp/verification/`，要求 migration/database shape/shared FileStore/process reconciliation 通过；数据库 row-level 等值仍不作无证据声明。
- 稳定证据为 `docs/evidence/verification-governance-release-reconciliation.json`；隔离工作区日期化 evidence 不回拷主仓。
- `REAL005=not_closed`、`fullClosureAllowed=false`、P001-P006 待办、release No-Go。

## Now: P001

- user outcome：在隔离机器完成可回滚安装、服务启动、数据库/FileStore/backup/restore、权限、网络/打印和四个教师入口 smoke。
- preconditions：隔离机、明确操作者、授权输入、回滚路径、证据目录和时间窗口可用。
- AI scope：生成或刷新执行包、确定性 precheck、命令清单、脱敏报告和失败分流；不得自动完成真实网络、打印、权限域、教师操作或签字字段。
- protected boundaries：production active、真实学生数据、版权原页、凭据、restore apply 和 release decision 均需对应授权。
- stateful verification：只有现场操作者明确授权后执行 P001 checklist 中的安装、备份恢复和 smoke。
- completion：真实环境、操作者、输入、时间戳、结果和签收字段齐备，且失败项有 rollback/owner；repo-side Release pass 不能替代。

## Verification routing

```powershell
# 普通编码反馈
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-verification.ps1 -Profile Quick

# 当前 task/changed paths
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-verification.ps1 -Profile Slice -TaskId <TASK_ID>

# 仅发布前、明确授权、隔离执行
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-verification.ps1 -Profile Release -AuthorizeStateful
```

不得把 `tools/run-gates.ps1` 作为日常或默认 Release 入口。只有显式 `-IncludeLegacyCompatibility` 才运行 legacy audit；单项能力脚本、日期化 evidence 或历史状态页均不决定当前任务。

## Evidence policy

- Quick/Slice：仅 `tmp/verification/`，不 tracked。
- 默认 Release/migration/restore rehearsal：只写 `tmp/verification/`；只有稳定 reconciliation 或真实 acceptance 才进入 `docs/evidence/index.json`。
- Onsite/live：导入真实 evidence，必须带环境、操作者、输入、时间和签字；AI 不生成验收事实。

## Rollback

只回滚当前 P001 执行切片。安装、migration、FileStore、backup/restore 或 active 变化必须使用现场 snapshot/restore 和 checklist 中的回滚入口；不撤销用户已有工作树修改。

## Next

P001 真实关闭后进入 P002；随后严格按 P002 -> P003 -> P004 -> P005 -> P006 推进。Q/R 在 P006 与真实触发条件满足前保持 Later。

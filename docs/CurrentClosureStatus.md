# 当前闭环状态

**状态真源边界**: 本文件投影当前 closure；任务状态来自 `tasks/backlog.csv`，发布裁决来自 `docs/109_ReleaseGoNoGoCard.md`。

## Repo-side complete

- API、Web、Worker、PostgreSQL、FileStore、备份与版本化领域资产已存在。
- C002 是当前生产默认；后续修订必须走 C002R。
- CEK-01..35 已完成 repo-side 候选链和相关验证收口；自动提炼仍为 `candidate/pending_review/productionEligible=false`。
- VGOV-001..010 已完成：inventory、canonical truth、Quick/Slice、UI 行为迁移、evidence lifecycle、授权 Release reconciliation、endpoint seam 和 hotspot budget。
- 历史 235-step Release 已在隔离工作区 exit 0，但产生 159 个 FileStore 文件、9024094 bytes 写入；该事实证明旧默认 Release 过重，不能作为当前默认语义。
- 当前默认 Release 已收缩为 Quick + 3 个风险聚焦阶段 + 状态对账，不运行 legacy monolith，不刷新日期化 tracked evidence，且要求共享 FileStore 无写入；235-step 仅保留显式 compatibility audit。

## Not closed

- `REAL005=not_closed`，`fullClosureAllowed=false`。
- P001-P006 均为待办；P001/P003/P005/P006 仍有不可替代的 onsite/manual 外部事实。
- 隔离机真实安装、学校网络、打印、权限域、真实教师使用和签字未由本轮关闭。
- release 仍为 No-Go。

## Verification boundary

- Quick/Slice 是日常 AI 编码入口，只写 `tmp/verification/`，不得连接 PostgreSQL、写 FileStore、停止常驻进程或生成 tracked evidence。
- legacy `tools/run-gates.ps1` 只能由 `-IncludeLegacyCompatibility` 显式触发，既不是普通任务入口，也不是默认 Release 永久主门禁节点。
- current evidence 由 `docs/evidence/index.json` 策展；未索引的历史/日期化 evidence 不决定当前状态。
- Onsite 只接受真实环境、操作者、输入、时间和签字证据，不能由 repo-side automation 自动通过。

## Next

当前进入 P001；后续按 P002 -> P003 -> P004 -> P005 -> P006 推进。没有剩余 repo-side VGOV task。

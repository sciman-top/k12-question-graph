# Current execution queue

本文件是 `tasks/backlog.csv` 的人工可读短投影，不保存历史 evidence 流水账。

## Now

- [ ] P001：隔离机部署与真实环境 preflight。
  - 需要：隔离机、操作者、授权输入、网络/打印/权限域、backup/restore 和签收事实。
  - AI 可做：执行包、确定性 precheck、脱敏报告、失败分流和 evidence 导入。
  - AI 不可做：代签、合成现场通过、自动 production active 或用 repo-side Release 代替现场验收。

## Next

- [ ] P002 -> P003 -> P004 -> P005 -> P006：教师代理、准入、首轮使用、反馈分流和发布裁决。

## Completed: verification governance

- [x] VGOV001-VGOV003：spec、真源和单一执行入口。
- [x] VGOV004：235-step AST inventory/profile 分类。
- [x] VGOV005-VGOV006：无副作用 Quick 与 task/changed-path Slice selector。
- [x] VGOV007：UI behavior parity migration。
- [x] VGOV008：current evidence index 与日常 artifact 分流。
- [x] VGOV009：legacy inventory/授权隔离审计、覆盖对账和 DB/FileStore 指纹，确认旧 Release 过重。
- [x] VGOV010：endpoint seam、热点预算、API/Web regression；默认 Release 收缩为 focused core，legacy 改为显式可选审计。

## Truth boundary

- [ ] `REAL005=not_closed`；`fullClosureAllowed=false`。
- [ ] P001-P006 均为待办；其中 P001/P003/P005/P006 含不可替代的外部/人工事实。
- [ ] release No-Go。

## Parked

- Q001-Q005、R001-R007：P006 和真实触发条件满足前不进入当前编码队列或默认 Quick/Slice。

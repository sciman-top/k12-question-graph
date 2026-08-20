# 103 · 执行总控板

本文件是 `tasks/backlog.csv` 的短投影，不是第二任务真源。

## Now

**P001：隔离机部署与真实环境 preflight**

- repo-side 前置：默认 Release 已收缩为 migration/privacy/no-active-write、隔离备份恢复和 current truth 聚焦检查；历史门禁不再参与当前执行。
- 执行模式：`remote_automated -> remote_target_host -> onsite_exception_only`。先用 `tools/run-remote-first-evidence-pack.ps1 -Mode Collect` 汇总并哈希 Release、roadmap、closeout、视觉和工件 evidence；再远程操作目标机；只有远程不可达或学校网络、打印、权限域/文件共享异常无法复现时到场。
- 目标环境目标：验证安装、服务、PostgreSQL、FileStore、backup/restore、权限、学校网络、按发布承诺执行的真实打印或等价打印预检，以及四个教师入口。
- AI 允许：准备执行包、运行确定性 precheck、汇总脱敏日志、导入真实 evidence、标记阻断和 rollback。
- AI 禁止：代替操作者、教师或负责人签字；把 readiness/repo-side pass 写成 onsite/live accepted；自动切 production active。
- 完成：目标环境、操作者、授权输入、时间戳、执行结果、回滚验证和可验证电子签收字段齐备；远程执行不等于自动验收。

## Next

P002 -> P003 -> P004 -> P005 -> P006，严格按 `tasks/backlog.csv` 和 `tasks/live-pilot-closeout-plan.csv` 的依赖推进。

- P002/P004 默认远程异步体验，系统预填耗时、异常、接管和工件；人工只提供无法替代的理解、困惑、偏好与真实耗时解释。
- P003 默认远程 admission card 和电子数据授权；责任边界不清才转现场。
- P005 自动去重、聚类、统计和提出候选分流，产品负责人只裁决范围/成本/风险影响项，不自动改 backlog。
- P006 缺硬证据自动保持 `No-Go`；只有转 `Go`、批准 named exception 时要求四责任角色异步电子确认，不要求纸质或同场签字。
- P001-P006 的异步电子确认统一使用 `docs/templates/accountable-acceptance-bundle-template.json`，并由 `tools/run-accountable-acceptance-bundle.ps1` 校验角色、时间、commit、证据哈希和身份系统引用；责任人仍需在对应身份系统中完成真实确认。

## Repo-side governance closeout

- VGOV-001..010：全部 repo-side complete，没有剩余 VGOV 编码任务。
- 日常入口：`tools/run-verification.ps1 -Profile Quick|Slice`。
- 默认 Release：`tools/run-verification.ps1 -Profile Release -AuthorizeStateful`，只运行聚焦 core，报告/恢复工件进入 `tmp/verification/`，共享 FileStore 必须无写入。
- legacy monolith、inventory、兼容审计和历史 roadmap 复算已退役；Git 历史只用于取证，不参与当前任务选择。
- current evidence：只由 `docs/evidence/index.json` 指向；隔离 Release 的日期化 evidence 不回拷主仓。
- 代码体量不设静态预算守卫；只有真实调用、故障或维护成本证据才触发拆分。

## Blocked / external

- `REAL005=not_closed`，`fullClosureAllowed=false`。
- P001-P006 均为待办；远程优先减少地点和重复审核，但目标机、学校网络、按承诺的打印/权限域、真实教师、数据授权、反馈裁决和责任签字仍需真实证据。
- production active 未因 repo-side 候选链或治理工作切换。
- release No-Go。

## Truth owners

| 问题 | Owner |
|---|---|
| 产品目标 | `docs/01_PRD.md` |
| 范围 | `docs/02_MVP_Scope_and_ScopeControl.md` |
| 任务顺序/状态 | `tasks/backlog.csv` |
| 当前 closure | `docs/CurrentClosureStatus.md` |
| 发布裁决 | `docs/109_ReleaseGoNoGoCard.md` |
| current evidence | `docs/evidence/index.json` |
| 历史事实 | `docs/evidence/` 与 Git |

## Update protocol

完成 task 后先更新 backlog，再刷新本投影、todo 和 closure status。Quick/Slice 结果不得进入 tracked evidence，也不得由 repo-side pass 自动改变现场/发布状态。

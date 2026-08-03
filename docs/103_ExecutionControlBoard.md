# 103 · 执行总控板

本文件是 `tasks/backlog.csv` 的短投影，不是第二任务真源。

## Now

**P001：隔离机部署与真实环境 preflight**

- repo-side 前置：VGOV-001..010 已完成；默认 Release 已收缩为聚焦 core；235-step inventory 保持 unmapped=0，但仅作显式 legacy audit。
- 现场目标：验证安装、服务、PostgreSQL、FileStore、backup/restore、权限、学校网络、打印和四个教师入口。
- AI 允许：准备执行包、运行确定性 precheck、汇总脱敏日志、导入真实 evidence、标记阻断和 rollback。
- AI 禁止：代替操作者、教师或负责人签字；把 readiness/repo-side pass 写成 onsite/live accepted；自动切 production active。
- 完成：真实环境、操作者、授权输入、时间戳、执行结果、回滚验证和签收字段齐备。

## Next

P002 -> P003 -> P004 -> P005 -> P006，严格按 `tasks/backlog.csv` 和 `tasks/live-pilot-closeout-plan.csv` 的依赖推进。

## Repo-side governance closeout

- VGOV-001..010：全部 repo-side complete，没有剩余 VGOV 编码任务。
- 日常入口：`tools/run-verification.ps1 -Profile Quick|Slice`。
- 默认 Release：`tools/run-verification.ps1 -Profile Release -AuthorizeStateful`，只运行聚焦 core，报告/恢复工件进入 `tmp/verification/`，共享 FileStore 必须无写入。
- legacy audit：仅 `-IncludeLegacyCompatibility` 显式进入 235-step monolith；它不属于默认发布阻断链。
- current evidence：只由 `docs/evidence/index.json` 指向；隔离 Release 的日期化 evidence 不回拷主仓。
- hotspot：Score/Admin AI endpoint seam 已抽取，其余稳定模块由单一预算守卫阻止重新膨胀；无真实增长不继续拆分。

## Blocked / external

- `REAL005=not_closed`，`fullClosureAllowed=false`。
- P001-P006 均为待办；P001/P003/P005/P006 仍依赖隔离机、学校网络、打印/权限域、真实教师、反馈责任和签字。
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

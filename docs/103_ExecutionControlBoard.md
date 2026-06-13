# 103 · 执行总控板

日期：2026-06-13。状态证据核对到 2026-06-13。

## 1. 判断

AI 推荐：当前唯一主目标不是继续扩能力面，而是把 `P001 -> P005/P006` 收成一个可裁决、可发布、可回滚的单主线。

当前不承诺新的日历发布日期。发布目标先按能力里程碑管理，直到现场数据授权、支持负责人、回滚窗口和发布裁决链都补齐。

## 2. 单一真相入口

若问题不是“当前主线是什么”，而是“我先看哪份文档”，先回到 `docs/111_ProjectNavigationOverview.md`。

| 用途 | 单一入口 | 说明 |
|---|---|---|
| 当前对外完成态 | `tasks/completion-state-dashboard.csv` | 对外只引用这里，不只引用 backlog 的 `已完成` |
| 当前 repo-side 口径有没有被旧状态覆盖 | `docs/evidence/20260613-ns905-status-sync.md` | 看 backlog、dashboard、non-site plan 和 live closeout 是否仍保持 truthful No-Go |
| 本地联调运行模型 | `docs/113_LocalRuntimeOperations_20260609.md` | 决定 Web/API 怎么启动、重启、判断 ready 和排查 |
| 主线顺序与依赖 | `tasks/backlog.csv` | 决定先做什么、后做什么 |
| 高风险任务参考依据 | `tasks/reference-basis-requirements.csv` | 决定哪些架构/运维/OCR/AI/搜索/互操作/发布任务必须先补官方与本地参考锚点 |
| 当前 reference-basis 守卫是否收口 | `docs/evidence/20260613-reference-basis-guard.md` | 看受管任务、模块覆盖和 external/snapshot parity 是否仍成立 |
| 非现场产品化与运行形态 | `tasks/non-site-implementation-plan.csv` | 决定 NS0-NS13 的实现顺序和证据 |
| 产品化闭环拆解 | `tasks/productization-roadmap.csv` / `tasks/productization-s0-execution-plan.csv` | 决定 S0 子任务归宿 |
| 现场 closeout 拆解 | `tasks/live-pilot-closeout-plan.csv` | 决定 `REAL005` 与 `P001/P003/P005/P006` 的最小关闭步骤 |
| 发布裁决 | `docs/109_ReleaseGoNoGoCard.md` | 决定 go / no-go，不由聊天结论代替 |
| 未决事项 | `docs/104_OpenQuestionsAndAssumptions.md` | 决定哪些边界还没拍板 |

## 3. Now / Next / Later

### Now

| 主线 | 目标 | 退出条件 | 负责人角色 |
|---|---|---|---|
| `REAL005` truthful boundary | 保持真卷闭环口径诚实，不让非现场或局部 smoke 提前改成“已闭环” | 只有逐年逐题 criteria 全部满足后才允许从 `not_closed` 改口径 | 题库/导入负责人 |
| `P001` readiness | 把非现场闭环变成现场前置包，而不是聊天判断 | 只剩隔离机、现场教师、打印、权限域、真实网络阻断项 | 发布负责人 + 试点支持负责人 |
| `P005/P006` 发布裁决 | 形成可签字的 go / no-go 卡，而不是只有 preflight | `P005` 反馈分流完成，`P006` 发布卡留痕，回滚和 tag candidate 策略明确 | 产品负责人 + 发布负责人 + 数据责任方代表 |

2026-06-13 最新 repo-side 刷新结果：`reference-basis guard`、`live pilot closeout plan guard` 和 `NS905 status sync audit` 全部 `pass`。它们共同证明高风险任务参考基线、closeout 计划、completion dashboard 和 release No-Go 口径没有继续漂移；同时也明确 `release_ready_count = 0`，`REAL005/P001/P003/P005/P006` 仍都没有被现场证据关闭。`live-pilot closeout plan guard` 最新证据为 `docs/evidence/20260613-live-pilot-closeout-plan-guard.json` / `.md`，它只能证明 closeout 计划、backlog 和入口文档同步，不替代任何现场事实。

### Next

| 主线 | 启动前提 | 默认边界 |
|---|---|---|
| `NS10` 现场链路 | `NS13` 和 `P001` 收口 | 只验证现场事实，不回头替代仓内应做能力 |
| `NS11` 第二学科 | `P006` 发布裁决关闭 | 只允许 candidate/review/dry-run，不提前扩成多学科产品面 |

### Later

| 主线 | 触发条件 | 默认边界 |
|---|---|---|
| `NS12 / R0` 长期平台 | 真实瓶颈、真实对接、真实样本、真实维护压力 | 无触发不做搜索引擎、复杂队列、完整标准互操作、高级分析、多校部署 |

## 4. 当前硬阻断

| 阻断项 | 当前状态 | 关闭条件 |
|---|---|---|
| `REAL005` 真卷全流程闭环口径 | `not_closed` | 逐年逐题来源、结构化、审核、检索、导出、学情引用和回滚隐私证据全部满足 closure criteria |
| `P003` 现场数据授权、支持负责人、回滚计划 | 未关闭 | 形成现场数据授权记录、支持负责人记录和回滚记录 |
| `P005` 试点反馈分流 | 未关闭 | 反馈被明确分流为保留 / 修改 / 后置 / 不做 |
| `P006` 发布裁决 | 未关闭 | `docs/109_ReleaseGoNoGoCard.md` 完整填写并留痕 |
| `NS13` 现场外主线已闭合 | 已完成 | 后续只保留 `P001/P003/P005/P006` 的现场事实与发布裁决阻断 |

## 5. 明确不并行推进

- 不在 `P006` 前并行推进完整标准互操作。
- 不在 `P006` 前并行推进第二学科真实 active。
- 不在 `P006` 前把本地小模型或新云 provider 切成默认生产路由。
- 不在 `P006` 前扩大普通教师可见入口、状态词和治理面。

## 6. 更新协议

1. 每次状态变更先更新证据，再更新机器表。
2. 对外汇报先看 `tasks/completion-state-dashboard.csv`，再引用证据。
3. 若 `backlog / dashboard / non-site plan / release card` 结论冲突，以最新证据和发布卡为准，并回写其余入口。
4. 日历发布日期只有在 `P006` 关闭后才能写入。

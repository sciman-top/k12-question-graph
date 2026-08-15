# 19 · 路线图

本文件只定义阶段顺序、退出条件和触发边界，不保存逐日运行日志。任务顺序和状态以 `tasks/backlog.csv` 为唯一机器真源；当前执行看 `docs/103_ExecutionControlBoard.md`；当前 closure 看 `docs/CurrentClosureStatus.md`。

## 1. 当前产品边界

- v0.1 聚焦初中物理 teacher-first 闭环。
- CEK-01..35 已完成 repo-side 候选链，但自动结果仍为 candidate/pending_review，未生产激活。
- `REAL005=not_closed`，P001/P003/P005/P006 仍有现场/人工事实。
- release No-Go；repo-side verifier 不能关闭现场边界。

## 2. Horizon 0：验证治理减负

目标：让 AI 和开发者从唯一执行真源获得快速、可归因、按风险选择的验证，同时保留高风险 Release/Onsite 覆盖。

| Wave | 任务 | 退出条件 |
|---|---|---|
| H0.1 | VGOV-001 基线 inventory | gate、脚本、证据、状态真源可枚举 |
| H0.2 | VGOV-002 canonical/generated/historical 边界 | 每个状态字段只有一个 owner |
| H0.3 | VGOV-003 PRD/roadmap/执行入口刷新 | AI 不再读到旧 P0-only 执行指令 |
| H0.4 | VGOV-004 全 gate 分类 | 旧 step 全部归属 Quick/Slice/Release/Onsite |
| H0.5 | VGOV-005 无副作用 Quick | 无 DB、无进程停止、无 tracked diff |
| H0.6 | VGOV-006 Slice selector | task/changed paths 可解释地选择验证 |
| H0.7 | VGOV-007 UI 合同迁移 | 高价值边界保留，低信号检查行为化 |
| H0.8 | VGOV-008 evidence 生命周期 | 日常结果进 tmp，current evidence 有索引 |
| H0.9 | VGOV-009 Release 覆盖对账 | stateful gate 无丢失，可退役重复默认执行 |
| H0.10 | VGOV-010 产品热点收口 | 真实 endpoint seam 抽取，稳定模块受单一 hotspot budget 保护 |

H0 已完成 repo-side 收口：日常入口为 changed-path Slice，跨栈基线为 Quick；Release 为 3 个风险聚焦阶段与状态对账。legacy monolith、inventory、兼容 wrapper 与未来治理节点已删除，只从 Git 历史取证。H0 不改变教师功能、数据库 schema、active 数据或 release 状态。

## 3. Horizon 1：v0.1 现场与发布闭环

当前继续 P001-P006：

1. P001 隔离机部署、备份恢复、权限、网络、打印和四入口 smoke。
2. P002 授权/脱敏材料教师代理试点。
3. P003 真实教师和数据授权准入。
4. P004 真实教师首轮使用、耗时、卡点、失败和回滚记录。
5. P005 反馈按效率、频率、风险、成本进入 backlog。
6. P006 由真实签字和 release evidence 做 v0.1 Go/No-Go。

`REAL005` 只有在逐题审核、来源回看、检索组卷导出、分析引用、回滚隐私和现场事实全部满足时才能关闭。

## 4. Horizon 2：发布后触发式扩展

Q/R 不是当前执行队列：

- Q001-Q005：P006 后，且有第二学科真实资料、教师 owner 和激活需求。
- R001：PostgreSQL FTS 真实不足后才评估向量/外部搜索。
- R002：BackgroundService 出现真实吞吐/可靠性瓶颈后才评估队列平台。
- R003/R007：出现真实校内互操作需求后才做标准 import/export。
- R004：样本量、解释责任和实际需求满足后才评估复杂分析。
- R005：数据责任、采购、网络和运维边界明确后才评估多校/SaaS。

这些任务的 ADR 和 admission 约束可以保留，但不进入默认 Quick。

## 5. 产品代码结构演进

VGOV-010 已抽取 Score/Admin AI endpoint seam，并保留既有 KnowledgeEvidence/Paper/Score workflow 与 Web panel；一个 canonical budget 防止热点重新增长。后续仅在真实职责漂移或预算触发时继续拆分，每次保持 API、payload、schema、数据和教师行为兼容，不引入新的通用平台。

## 6. 路线图维护规则

- 不在本文件追加日期化 full-gate 日志。
- 完成态只改 `tasks/backlog.csv`，再刷新投影。
- 新阶段必须有用户结果、触发条件、退出门禁和明确 non-goals。
- 未来能力不得仅因“以后可能需要”进入当前实施或默认门禁。
- repo-side、release-side、onsite 和 live accepted 必须分开陈述。

所有待办继续遵守 automation-first：确定性检查优先由产品代码、schema、最低充分测试和专用 UI/API 承接；AI 只做语义候选、风险复核或外层编排，不另设横向自证守卫。

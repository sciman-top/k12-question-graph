# 111 · 项目导航总览

日期：2026-06-06。

## 1. 用途

本文件回答一个最实际的问题：

> 现在这个项目文档很多，遇到某类问题时，第一份该看哪份？

原则：先看**最接近当前问题、最接近真实执行边界**的文档；如果有冲突，仍以代码、任务清单、证据和更具体的文档为准。

## 2. 最常用入口

| 你现在想知道什么 | 先看哪里 | 说明 |
|---|---|---|
| 这个项目到底要做什么 | `docs/00_ProjectConstitution.md` + `docs/01_PRD.md` | 先看最高原则，再看产品故事和成功指标 |
| v0.1 明确做什么、不做什么 | `docs/02_MVP_Scope_and_ScopeControl.md` | 先看范围冻结和后置边界 |
| 当前推荐的长期工程终态是什么 | `docs/decisions/ADR-014-recommended-engineering-endstate-and-stack-boundary.md` | 长期技术/架构裁决入口 |
| 我只想快速判断“这条技术路线是不是默认推荐” | `docs/110_EngineeringEndStateChecklist.md` | ADR-014 的短入口 |
| 当前真正唯一主线是什么 | `docs/103_ExecutionControlBoard.md` | 看 Now / Next / Later 和硬阻断 |
| 还有哪些关键边界没拍板 | `docs/104_OpenQuestionsAndAssumptions.md` | 看 OQ 和是否需要回写任务 CSV |
| 现在能不能发布 / 试点 | `docs/109_ReleaseGoNoGoCard.md` | 当前正式 `Go / No-Go` 裁决入口 |
| 任务链和机器顺序到底以什么为准 | `tasks/backlog.csv` | 主线顺序权威入口 |
| 当前对外完成态该怎么说 | `tasks/completion-state-dashboard.csv` | 不只看 backlog 的 `已完成` |
| 非现场能力落到了哪一步 | `docs/101_NonSiteCapabilityImplementationRoadmap.md` + `tasks/non-site-implementation-plan.csv` | 看 `planned -> runtime_verified -> blocked_by_onsite` |
| 产品化闭环当前推进到哪 | `docs/99_ProductizationFullRoadmapAndTaskPlan.md` + `tasks/productization-roadmap.csv` | 看 S0 与 NS13 的产品化推进 |
| 教师端 UI/术语/字段该怎么收口 | `docs/11_UX_Workflows.md` + `docs/106_TeacherVisibleMetadataBudget.md` | 一个看流程，一个看预算 |
| AI 在本项目里到底能做什么、不能做什么 | `docs/107_AITrustAndReviewContract.md` + `docs/09_AI_ModelRouting_CostControl.md` | 一个看边界，一个看路由与成本 |
| 标准互操作到底承诺到哪里 | `docs/108_InteroperabilityProfileBoundary.md` | 只做 profile map，不做完整实现 |
| 角色审批和高风险动作归谁 | `docs/105_RoleApprovalAndExceptionMatrix.md` | 角色、复核、例外、回滚 |
| 外部参考资料去哪里看 | `docs/26_References.md` + `D:\CODE\external\k12-question-graph-references\references.manifest.json` | 一个看人工摘要，一个看机器清单 |
| 当前技术栈和工具链默认选型 | `docs/04_TechnologyStack.md` | 具体到栈、工具、后置条件 |
| 为什么当初这样选 | `docs/27_ExternalReview_DecisionLog.md` + `docs/88_EngineeringEndStateExternalReview_20260504.md` | 历史外部复核与决策原因 |
| 真卷闭环到底到哪了 | `docs/19_Roadmap.md` + `tasks/real-guangzhou-closure-criteria.csv` + `docs/evidence/` | 判定入口与证据都在这条线上 |

## 3. 按角色导航

### 产品 / 项目负责人

先看：

1. `docs/103_ExecutionControlBoard.md`
2. `docs/104_OpenQuestionsAndAssumptions.md`
3. `docs/109_ReleaseGoNoGoCard.md`
4. `tasks/completion-state-dashboard.csv`

### 架构 / 工程负责人

先看：

1. `docs/decisions/ADR-014-recommended-engineering-endstate-and-stack-boundary.md`
2. `docs/04_TechnologyStack.md`
3. `docs/03_Architecture.md`
4. `docs/101_NonSiteCapabilityImplementationRoadmap.md`

### 前端 / UX

先看：

1. `docs/11_UX_Workflows.md`
2. `docs/106_TeacherVisibleMetadataBudget.md`
3. `docs/105_RoleApprovalAndExceptionMatrix.md`
4. `docs/107_AITrustAndReviewContract.md`

### AI / Worker / 导入链

先看：

1. `docs/09_AI_ModelRouting_CostControl.md`
2. `docs/107_AITrustAndReviewContract.md`
3. `docs/07_Document_AI_ImportPipeline.md`
4. `docs/04_TechnologyStack.md`

### 试点 / 发布 / 现场支持

先看：

1. `docs/109_ReleaseGoNoGoCard.md`
2. `docs/103_ExecutionControlBoard.md`
3. `docs/104_OpenQuestionsAndAssumptions.md`
4. `docs/templates/p001-live-pilot-release-checklist.md`
5. `docs/templates/p003-onsite-pilot-admission-checklist.md`
6. `docs/templates/p006-release-decision-checklist.md`

## 4. 读取顺序建议

### 新人或新 agent 进入项目

1. `README.md`
2. 本文件
3. `docs/103_ExecutionControlBoard.md`
4. `docs/109_ReleaseGoNoGoCard.md`
5. `docs/decisions/ADR-014-recommended-engineering-endstate-and-stack-boundary.md`

### 开始具体工作前

1. 先确认当前问题属于哪一类
2. 从本文件找到第一入口
3. 再看对应任务 CSV 和最新 evidence
4. 最后才看更长的历史背景文档

## 5. 不该怎么找文档

- 不要一上来先通读所有 docs。
- 不要只看 `backlog.csv` 就判断“已经完成”。
- 不要只看历史外部复核结论，不看当前 `Go / No-Go`。
- 不要把长期终态判断和当前发布状态混成一件事。
- 不要把未决事项误当成“缺少任务”；先看 `docs/104` 是否已映射到现有任务链。

## 6. 维护规则

1. 新增重要入口文档时，必须回写本文件。
2. 若某类问题的第一入口变了，优先更新本文件，再更新 README/Executive Spec。
3. 本文件只做导航，不重复长篇规则正文。

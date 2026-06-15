# 111 · 项目导航总览

日期：2026-06-14。状态证据核对到 2026-06-14。

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
| 我只想知道“当前到底闭环到哪了” | `docs/112_CurrentClosureStatus_20260609.md` | 当前仓库级 / 非现场 / 现场阻断的短总览 |
| 当前 repo-side 状态口径有没有漂移 | `docs/evidence/20260614-ns905-status-sync.md` | 看 backlog、dashboard、non-site plan 和 live closeout 是否仍保持 truthful No-Go |
| 本地 Web/API 怎么启动、重启、判断是否真的活着 | `docs/113_LocalRuntimeOperations_20260609.md` | 本地联调运行模型、状态语义和排查入口 |
| 本地管理员 AI 设置在哪里、怎么做 save/test smoke | `docs/113_LocalRuntimeOperations_20260609.md` | 看 `?admin=1`、`打开设置`、`管理员 AI 设置` 和本地 save/test 边界 |
| 任务链和机器顺序到底以什么为准 | `tasks/backlog.csv` | 主线顺序权威入口 |
| 高风险编码任务必须先查哪些参考 | `tasks/reference-basis-requirements.csv` + `tasks/reference-basis-policy.json` + `tools/run-reference-basis-guard.ps1` | 架构、Windows Service、PowerShell 运维、OCR/toolchain、导出、成绩分析、AI routing、搜索、互操作和 live pilot 预演等强制参考入口；policy 负责受管 task/module 集 |
| 当前 reference-basis 守卫是否真的过了 | `docs/evidence/20260614-reference-basis-guard.md` | 看 20 个受管任务、13 个模块和 external/snapshot parity |
| 按代码板块看“该参考/复刻/复用哪个仓” | `tasks/reference-basis-module-map.csv` | API、Web、export、score-analysis、AI routing、OCR、Windows Service、release pack、搜索、队列、互操作的 machine-readable 参考映射 |
| 当前外置参考仓是否要增删、哪些值得常驻本地镜像 | `docs/26_References.md` | 看本地参考仓分组、optional/mandatory-on-use 边界，以及哪些来源只保留在线锚点 |
| 想知道本轮改动命中了哪些受管板块/任务 | `tools/run-reference-basis-diff-aware-contract.ps1` + `tools/run-reference-basis-guard.ps1 -ChangedPaths ...` | 当前 v2 最小入口；先把 changed paths 投影到 guarded modules/tasks，再决定要补哪些 adoption 证据 |
| 想知道 `P005/P006` 是否已补参考采纳记录结构 | `tools/run-reference-basis-adoption-record-contract.ps1` | 当前只覆盖反馈分流与发布裁决两类 closeout 文档，检查 `referenceContext / impactedSurfaceIds / referencesReviewed / adoptionDecision` |
| 想知道 `P001/P003` 现场前置包与现场准入卡是否已补参考采纳记录 | `tools/run-reference-basis-onsite-adoption-contract.ps1` | 当前覆盖隔离机前置包与现场准入卡，防止 onsite-ready 口径只改模板不声明参考依据 |
| 想把本次 reference/preflight 主线和并行脏改动正式分开 | `tools/run-reference-basis-closeout-report.ps1` | 输出 dedicated/shared/evidence/temp/unrelated 五类清单，便于收口、挑选提交或交接 |
| `P001 / P003 / P005 / P006 / REAL005` 还差哪几步 | `tasks/live-pilot-closeout-plan.csv` | 现场 closeout 最小执行顺序入口 |
| `REAL005` 为什么还没闭环、现在最细该做到哪一层 | `tasks/live-pilot-closeout-plan.csv` + `tasks/real-guangzhou-closure-criteria.csv` + `docs/115_REAL005_DetailedSliceTree.md` | 先看顶层 closeout，再看 RG 级 criteria 和更细的人类执行树 |
| 当前对外完成态该怎么说 | `tasks/completion-state-dashboard.csv` | 不只看 backlog 的 `已完成` |
| 非现场能力落到了哪一步 | `docs/101_NonSiteCapabilityImplementationRoadmap.md` + `tasks/non-site-implementation-plan.csv` | 看 `planned -> runtime_verified -> blocked_by_onsite` |
| 产品化闭环当前推进到哪 | `docs/99_ProductizationFullRoadmapAndTaskPlan.md` + `tasks/productization-roadmap.csv` | 看 S0 与 NS13 的产品化推进 |
| 教师端 UI/术语/字段该怎么收口 | `docs/11_UX_Workflows.md` + `docs/106_TeacherVisibleMetadataBudget.md` | 一个看流程，一个看预算 |
| AI 在本项目里到底能做什么、不能做什么 | `docs/107_AITrustAndReviewContract.md` + `docs/09_AI_ModelRouting_CostControl.md` | 一个看边界，一个看路由与成本 |
| 标准互操作到底承诺到哪里 | `docs/108_InteroperabilityProfileBoundary.md` | 只做 profile map，不做完整实现 |
| 知识点/教材/课标/考点变化到底如何治理 | `docs/05_DomainModel.md` + `docs/116_KnowledgeAssetGovernanceExecutionTree.md` | 一个看稳定模型，一个看版本迁移/影响分析/审核激活的执行树 |
| 角色审批和高风险动作归谁 | `docs/105_RoleApprovalAndExceptionMatrix.md` | 角色、复核、例外、回滚 |
| 外部参考资料去哪里看 | `docs/26_References.md` + `D:\CODE\external\k12-question-graph-references\references.manifest.json` + `sources/reference-shelf.manifest.snapshot.json` + `tools/sync-reference-shelf-snapshot.ps1` | 一个看人工摘要，一个看外部机器清单，一个看仓内快照，一个做 snapshot 同步 |
| 本地 / CI 的正式预检入口是什么 | `tools/run-repo-preflight.ps1` + `.github/workflows/repo-preflight.yml` | 本地 release preflight 与 CI preflight 双入口 |
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
3. `tasks/live-pilot-closeout-plan.csv`
4. `docs/104_OpenQuestionsAndAssumptions.md`
5. `docs/templates/p001-live-pilot-release-checklist.md`
6. `docs/templates/p003-onsite-pilot-admission-checklist.md`
7. `docs/templates/p006-release-decision-checklist.md`

## 4. 读取顺序建议

### 新人或新 agent 进入项目

1. `README.md`
2. 本文件
3. `docs/103_ExecutionControlBoard.md`
4. `docs/109_ReleaseGoNoGoCard.md`
5. `docs/evidence/20260614-ns905-status-sync.md`
6. `docs/113_LocalRuntimeOperations_20260609.md`
7. `docs/decisions/ADR-014-recommended-engineering-endstate-and-stack-boundary.md`

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
- 不要只记住“要查参考”，不看 `reference-basis` 两张清单和 guard；高风险改动现在已经有机器守卫，不再是口头约定。

## 6. 维护规则

1. 新增重要入口文档时，必须回写本文件。
2. 若某类问题的第一入口变了，优先更新本文件，再更新 README/Executive Spec。
3. 本文件只做导航，不重复长篇规则正文。

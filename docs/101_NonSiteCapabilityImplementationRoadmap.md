# 101 · 非现场能力落地路线图、实施计划与任务清单

日期：2026-05-28。

## 1. 结论

AI 推荐：应当先把除人工现场以外的能力全部落盘，并把它们作为进入 P0-live 前的主线。

理由：人工现场只能验证真实教师、真实网络、打印、权限域和学校环境，不能替代仓库内可实现、可复跑、可回滚的产品能力。导入、解析、切题、审核、AI 候选、检索、组卷、导出、成绩导入、学情分析、备份恢复、安装预检、权限审计和非现场端到端演练，都应先在本仓形成代码、脚本、UI、合同、证据和任务状态。现场试点只负责最终真实环境验收，不应成为非现场模块暂缓落地的理由。

当前落点：`D:\CODE\k12-question-graph`。

目标归宿：以本文件作为非现场能力落地总控入口，以 `tasks/non-site-implementation-plan.csv` 作为机器可读任务清单；后续完成态再回写 `tasks/completion-state-dashboard.csv`、`tasks/backlog.csv` 和对应 evidence。

本轮 slice：先落路线图和任务清单，不直接修改业务代码、不改数据库、不改 existing evidence。

## A. 事实边界

本仓已有 `docs/87_PhaseCloseoutAndFullRoadmap.md`、`docs/99_ProductizationFullRoadmapAndTaskPlan.md`、`tasks/backlog.csv`、`tasks/productization-roadmap.csv` 和 `tasks/completion-state-dashboard.csv`。这些文件保留历史证据和当时的完成态判断。

本文件处理的新问题是：当用户最新判断指出“大量非人工、非现场功能模块仍未实现落地”时，不能继续只引用旧的 `已完成` 或 `teacher_validated` 口径。后续每个非现场模块必须重新按下面状态确认：

| 状态 | 含义 | 是否可对外宣称 |
|---|---|---|
| `planned` | 已进入路线图和任务清单，尚未证明代码落地 | 否 |
| `contract_only` | 有 schema、脚本、preflight、fixture 或 guard，但还不能证明真实模块可用 | 否 |
| `repo_landed` | API/UI/worker/tool 已落代码，可构建或可运行局部 smoke | 只能说已落代码 |
| `runtime_verified` | 本机真实运行通过，含 API/UI/文件/DB/worker 或 artifact 证据 | 可说非现场可用 |
| `non_site_validated` | 授权或脱敏材料完成非现场端到端演练，记录耗时、失败和回滚 | 可进入 P001 准备 |
| `blocked_by_onsite` | 只剩现场教师、隔离机、打印、权限域、真实网络或发布裁决 | 不能由本机会话代替 |

旧证据不是无效，但必须被重新映射到上述状态；没有 live/runtime 证据的能力不得只因 backlog 历史状态而宣称已经产品化。

## B. 范围

先落盘范围：

- 运行底座：API、Web、worker、PostgreSQL、FileStore、typed API、application service、feature flag。
- 数据与安全：RBAC、审计、PII/版权边界、no-active-write、来源 hash、备份 manifest。
- 试题导入：文件上传、来源资料、Docx/PDF/扫描件 adapter、SourceRegion、截图、质量报告。
- 题目结构：切题候选、ReviewQueue、题图、表格、公式、编辑、重裁、合并、拆分、audit。
- AI 候选：schema、ModelRouter、成本缓存、候选标注、人工审核、eval、feedback loop。
- 教师工作流：题库检索、题卡、题篮、自然语言组卷、换题撤销、导出审校、Word/PDF artifact。
- 学情闭环：Excel 模板、字段映射、小题分、得分率、知识点掌握、讲评报告、隐私审计。
- 运维发布前置：安装初始化、worker profile、host capability、Windows Service、备份恢复、升级演练、健康面板。
- 非现场验收：授权或脱敏材料端到端演练、完成态看板、P001 readiness evidence pack。
- 长期扩展：第二学科、搜索/语义检索、队列扩展、标准互操作、高级分析、多校部署和技术债节奏。

暂不由本计划直接完成：

- 真实教师现场操作和访谈。
- 学校隔离机安装后的现场网络、打印机、权限域和文件共享验证。
- 含真实学生个人信息的数据处理。
- 未经预算、合规和人工审核的真实外部 AI 生产写入。
- 多校 SaaS、在线考试、学生端、家长端、自动主观题阅卷和完整 IRT。

## C. 全程路线图

| 波次 | 名称 | 目标 | 退出条件 |
|---|---|---|---|
| NS0 | 状态重基线 | 把旧完成态和真实落地状态分开 | 每个模块有 `planned/contract_only/repo_landed/runtime_verified/non_site_validated/blocked_by_onsite` 状态 |
| NS1 | 运行与架构底座 | API/Web/worker/DB/FileStore 能支撑后续纵切 | build 通过，核心 service 边界清楚，typed API 或 OpenAPI snapshot 可复核 |
| NS2 | 数据、安全与审计 | 防止非现场实现绕过权限、隐私、来源和 active 守卫 | RBAC、audit、PII、license、no-active-write guard 通过 |
| NS3 | 来源与解析 | 授权或脱敏材料可进入来源证据层并被 adapter 解析 | 文件 hash、SourceDocument、SourceRegion、worker diagnostic、质量报告可复跑 |
| NS4 | 切题与审核 | 候选题目能进入教师可接管的审核链 | 切题候选、题图/表格/公式、编辑重裁和 audit 形成闭环 |
| NS5 | 知识与 AI 候选 | AI 只产候选，系统记录版本、成本、来源和审核 | schema/eval/cost/cache/no-active-write/human review 全部有证据 |
| NS6 | 检索组卷导出 | 教师能从题库到可打印工件完成非现场闭环 | 检索、题篮、组卷、换题、审校、Word/PDF artifact runtime 通过 |
| NS7 | 成绩与学情 | Excel 成绩到讲评报告完成非现场闭环 | 模板复用、异常行、小题分、分析指标、报告导出和隐私审计通过 |
| NS8 | 运维与安装 | 没有现场也能完成发布前置预演 | host/worker diagnostic、安装初始化、备份恢复、升级、健康面板可复跑 |
| NS9 | 非现场端到端 | 用授权或脱敏材料跑完整教师代理链 | `non_site_validated` evidence pack 形成，P001 只剩现场阻断 |
| NS10 | 现场与发布 | 进入 P001-P006，但只处理现场事实 | 隔离机、教师代理、现场试点、反馈回流和 release decision 完成 |
| NS11 | 多学科扩展 | 第二学科复用动态资产激活链 | candidate、review、active dry-run、rollback 和 UI 简化不破坏 v0.1 |
| NS12 | 长期平台 | 只根据真实瓶颈引入高级能力 | 搜索、队列、互操作、分析、多校和技术债均有 ADR 与 evidence |

## D. 实施计划

执行顺序固定为纵切优先，不按“先把全部底层做完再做页面”的横向路线推进。

1. NS0 先做状态重基线：盘点现有代码、脚本、UI、evidence 和 CSV，把旧完成态映射到新状态。
2. NS1-NS2 形成不容易返工的运行和安全底座：只允许薄 endpoint，核心编排进 application service；所有生产写入和高风险动作默认 fail closed。
3. NS3-NS4 先打通试题导入和审核，这是教师题库系统的入口命脉。
4. NS5 只让 AI 做候选和复核材料，不让 AI 直接写 active。
5. NS6-NS7 把题库真正变成教师可用的组卷、导出和讲评链路。
6. NS8 在非现场阶段补齐安装、备份、恢复、升级和健康诊断，避免现场才暴露基础设施问题。
7. NS9 用授权或脱敏材料做完整演练，所有失败都回流任务清单。
8. NS10 以后才进入现场链路；现场任务不得反向阻塞 NS0-NS9 的仓库内落地。
9. NS11-NS12 只有 v0.1 主链稳定后进入，不提前扩大范围。

机器可读细化任务见 `tasks/non-site-implementation-plan.csv`。每个任务必须有验收、验证、可能触达文件、证据和回滚口径。

## E. 任务拆分原则

- 每个任务最多服务一个明确纵切，避免“实现所有导入能力”这类 XL 任务。
- 每个任务必须能回答：减少哪一步教师工作、失败后教师如何继续、是否增加配置负担、是否影响隐私/成本/备份/恢复。
- 涉及 DB、文件仓库、active switch、真实 AI、真实学生数据和安装发布的任务按中高风险处理，必须有回滚。
- 任何任务若只能证明 preflight，不得标成 `runtime_verified`。
- 任何任务若没有真实 UI/API/worker/tool 证据，不得标成 `repo_landed`。
- 任何任务若没有授权或脱敏材料端到端证据，不得标成 `non_site_validated`。

## F. 门禁与证据

默认顺序仍是 `build -> test -> contract/invariant -> hotspot`。

最小验证组合：

```powershell
dotnet build apps/api/K12QuestionGraph.Api.csproj
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-gates.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-automation-first-feature-contract-guard.ps1
```

纯规划或任务清单变更时，允许 `gate_na`，但必须执行替代验证：

```powershell
Import-Csv tasks/non-site-implementation-plan.csv | Measure-Object
rg -n "101_NonSiteCapabilityImplementationRoadmap|non-site-implementation-plan" README.md docs tasks
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1
```

每个完成任务的 evidence 至少包含：

- 任务 ID、状态、风险等级。
- 执行命令和关键输出。
- 代码/脚本/UI/API/DB/worker/artifact 证据。
- 教师效率判断。
- 回滚动作。
- 若为 N/A：`reason / alternative_verification / evidence_link / expires_at`。

## G. 与现有路线图的关系

- `tasks/backlog.csv` 仍是主线任务来源。
- `tasks/completion-state-dashboard.csv` 仍是对外完成态看板。
- `docs/87_PhaseCloseoutAndFullRoadmap.md` 和 `docs/99_ProductizationFullRoadmapAndTaskPlan.md` 仍保留历史规划和产品化路线。
- 本文件新增的是“非现场落地重基线”：后续不得只看旧 `已完成`，必须看是否达到 `repo_landed/runtime_verified/non_site_validated`。
- 当某个 NS 任务被真实完成后，再按证据更新旧看板和 backlog，不能反向用旧看板证明新任务已完成。

## H. 回滚

本轮为规划层变更，默认回滚：

```powershell
git restore -- README.md docs/19_Roadmap.md docs/20_TaskBreakdown.md docs/101_NonSiteCapabilityImplementationRoadmap.md tasks/non-site-implementation-plan.csv
```

后续实现层回滚按任务拆分执行：

- 代码任务：独立提交，Git 回滚。
- DB/migration：备份 manifest + migration rollback。
- 文件仓库：hash manifest + snapshot restore。
- active/candidate/reviewed：状态切换报告 + rollback snapshot。
- AI/外部工具：禁用 route/profile + 删除候选输出，保留审计证据。


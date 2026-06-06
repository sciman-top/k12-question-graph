# ADR-014 · 推荐工程终态与默认技术栈边界

## Status

Accepted

## Date

2026-06-06

## Context

本项目不是通用 LMS、在线考试平台或公网 SaaS，而是面向学校和教师的 `Windows/LAN-first` 校本题库、组卷、导入、分析与恢复系统。项目的最高约束不是“技术最先进”，而是：

- 教师工作流效率优先，尤其是 Word / WPS / PDF / 图片 / Excel 既有路径。
- 学校电脑、校内局域网、离线或弱网环境可运行。
- 大文件、真实题库来源和学生数据都属于高风险资产。
- AI 只能先做候选、建议和审查，不能直接改生产事实。
- 安装、升级、备份、恢复和回滚必须成为产品能力，而不是部署后手工补丁。

2026-06-06 外部复核参考了以下官方文档、成熟项目和最佳实践：

- Microsoft：.NET 支持周期、ASP.NET Core hosted services / Windows Service / health checks、EF Core migration bundles
- PostgreSQL 官方文档：`jsonb`、全文检索、`pg_trgm`、`pg_dump`、PITR/WAL
- React / Vite / Ant Design / TanStack Query 官方文档
- OpenAI 官方文档：Structured Outputs、Prompt Caching、Batch、Evals
- 1EdTech：QTI、CASE、OneRoster
- OWASP / NIST：LLM 风险与 AI 风险治理
- Moodle / Open edX / OpenOLAT / TAO：题库、测评、权限、导入导出和治理经验

这些来源共同支持一个结论：对本项目来说，最佳终态不是“平台能力越多越好”，而是“教师主链路最短、治理边界最清楚、回滚能力最强、扩展点预留但不提前实现”。

## Decision

### 1. 推荐工程终态

本项目的推荐工程终态固定为：

```text
Windows/LAN-first teacher workbench
-> installer / init wizard / service control panel
-> Windows Service as primary runtime
-> ASP.NET Core modular monolith + hosted/background services
-> PostgreSQL fact store + local file store
-> Python document/OCR/AI adapters through explicit profiles
-> React/TypeScript/Vite/Ant Design teacher workbench
-> versioned domain assets + review / rollback workflow
-> role-routed structured AI candidate pipeline
-> backup / restore / upgrade / release evidence before live
```

### 2. 默认后端与部署边界

- 后端默认采用 `ASP.NET Core + .NET 10 LTS`。
- 服务端默认采用 `模块化单体`，而不是微服务。
- 后台任务默认采用 `PostgreSQL job store + IHostedService/BackgroundService`。
- 主运行形态默认采用 `Windows Service`；浏览器端是教师主工作台，窗口 UI 只做服务控制面板。
- 生产数据库迁移默认采用 `migration bundle / 可审查脚本`，不以应用启动自动迁移为默认路径。

### 3. 默认数据与搜索边界

- PostgreSQL 是结构化事实源。
- 文件、题图、来源 PDF、导出工件、截图和备份工件默认进入本地文件仓库，不进数据库正文。
- 默认搜索路线是 `PostgreSQL FTS + pg_trgm`。
- `pgvector`、独立搜索引擎、图数据库都属于后置能力，只有真实 benchmark 证明不足时才准入。

### 4. 默认前端边界

- 前端默认采用 `React + TypeScript + Vite SPA + Ant Design + TanStack Query + React Router`。
- `TanStack Query` 只管理 server state；教师草稿、撤销快照、高风险确认状态和发布裁决状态不得只存在 query cache 中。
- 普通教师默认只看到导入、组卷、成绩、分析四入口；管理员和治理面独立下沉。

### 5. 默认文档/OCR/导出边界

- 文档、OCR、公式和版面能力默认走 Python Adapter 进程隔离。
- 工具链默认优先：`OpenXML/OMML -> PDF text/layout -> Docling -> PaddleOCR/PP-Structure -> 必要时云端兜底`。
- 所有工具都必须通过稳定内部模型与 diagnostics 接入，不允许第三方输出直接污染领域主模型。

### 6. 默认 AI 边界

- 默认策略是 `L0 deterministic first`，再进入 AI。
- AI 只允许生成 `draft / candidate / pending_review` 结果。
- 真实 AI 调用默认采用 `Structured Outputs + Prompt Caching + Batch + Evals + cost/cache logging + human review + no-active-write guard`。
- 业务代码按 `role-routed provider profiles` 路由，不按具体模型名写死。
- 普通教师界面不暴露 provider、model、token 或路由细节。

### 7. 默认标准互操作边界

- 内部先维护 canonical model，再做 QTI / CASE / OneRoster / Caliper profile map。
- 没有真实对接需求前，不做完整标准 import/export。
- 外部标准字段只进 adapter / profile map / review artifact，不反向污染核心主模型。

### 8. 明确不建议提前做的方向

以下方向在 `v0.1` 或 `P006` 关闭前默认不推进为主线：

- 纯云 SaaS / 多租户公网部署
- 微服务、RabbitMQ/Kafka、Kubernetes
- Neo4j 或图数据库主数据层
- Elasticsearch / Meilisearch 作为默认搜索路线
- Next.js / SSR 作为默认前端路线
- 完整 QTI / CASE / OneRoster 双向实现
- 本地小模型或新云 provider 切成默认生产路由
- 外部 AI 直接写 `active` 或正式历史学情

## Consequences

- 长期技术评审、架构争议、栈升级、外部对接或“要不要换路线”的讨论，默认以本 ADR 为先。
- 若某项提议偏离本 ADR，必须提供新的 benchmark、现场约束变化或发布后证据，并通过新 ADR 或 superseding ADR 处理。
- `docs/04_TechnologyStack.md`、`docs/26_References.md` 和短清单入口都应指向本 ADR。

## Alternatives Considered

### 纯云 SaaS / 多租户优先

Rejected. 与学校数据、网络、运维、采购和离线场景约束不匹配。

### 微服务 + 独立搜索 + 图数据库起步

Rejected. 当前主要瓶颈不是横向扩展，而是教师闭环、文档解析、恢复与发布前置。

### Next.js / SSR 作为默认前端路线

Rejected. 当前最优先是局域网内稳定教师工作台，而不是 SEO、多端门户或公网分发。

### 完整标准互操作先行

Rejected. 当前没有真实对接样本、授权包和 adapter owner，完整实现会扩大范围并污染主模型。

### AI 主导自动入库和生产写入

Rejected. 与本项目对来源证据、人工复核、回滚能力和真实数据边界的要求冲突。

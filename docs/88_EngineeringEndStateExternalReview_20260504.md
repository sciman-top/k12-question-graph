# 88 · 工程终态外部复核

日期：2026-05-04。

## 1. 结论

AI 推荐：当前工程终态和技术路线总体正确，不应推翻；需要把若干隐含边界补成明确任务、门禁和证据。

本项目的最优工程终态不是“最先进技术堆叠”，而是：

```text
Windows/LAN first teacher workstation
-> ASP.NET Core modular monolith
-> PostgreSQL fact store + local file store
-> Python document/OCR/AI adapters through stable ports
-> React/Vite/Ant Design teacher workbench
-> versioned domain assets and review workflow
-> structured AI candidate outputs with cost/cache/eval/security gates
-> backup/restore/upgrade/install evidence before release
```

这条终态匹配本仓的核心约束：教师效率优先、学校低运维、本机/局域网部署、Word/Excel/PDF/扫描件兼容、真实学生数据高风险、AI 只能先生成候选且可审核回滚。

## 2. 当前工程终态定义

| 面 | 终态要求 |
|---|---|
| 产品 | 普通教师只面对导入、找题组卷、成绩导入、讲评分析四类入口；后台证据、回滚、版本、权限和迁移下沉给管理员/代理 |
| 架构 | 模块化单体优先，领域和用例层不依赖 EF、HTTP、OpenAI、文件系统、Python 工具或前端形状 |
| 数据 | PostgreSQL 是结构化事实源；大文件在 file store；数据库只存 metadata/path/hash/status/version |
| 动态资产 | 知识点、教材、课标、题型、标签、rubric、prompt/schema/model routing、分析指标和导出模板都带 version/status/source/mapping/migration/rollback |
| AI | 外部模型只产生 `candidate/pending_review/productionEligible=false`；真实 active 切换必须有 schema/eval/cost/cache/security/human review/no active write 证据 |
| 发布 | Windows Service/安装初始化/EF migration bundle/备份恢复/权限审计/健康面板必须在 v0.1 release 前闭环 |
| 长期扩展 | 多学科、标准互操作、复杂队列、外部搜索、图数据库、多校部署都以后置 ADR 和真实瓶颈为准 |

## 3. 外部复核摘要

| 领域 | 外部来源 | 对本项目的裁决 |
|---|---|---|
| .NET 支持周期 | Microsoft .NET support policy 显示 .NET 10 为 LTS，支持到 2028-11-14 | 保留 .NET 10 LTS 默认；记录 SDK/runtime 主版本和 self-contained 回退 |
| BackgroundService | Microsoft hosted services 文档把 hosted service/Worker Service 作为后台任务入口 | P0/P1 用 PostgreSQL job store + `BackgroundService` 合理；任务事实源必须仍在 DB |
| Windows Service | Microsoft Windows Service 文档强调 `UseWindowsService` 和 service content root | 必须把程序目录、数据目录、日志目录、file store 明确配置，不能依赖 cwd |
| Health checks | Microsoft health check 文档支持 DB/EF probe，并提醒查询要轻量 | `/health` 应拆 liveness/readiness/management，并限制重查询 |
| EF Core migration | Microsoft EF 文档推荐 migration bundle 可在无 SDK/源码场景运行 | O0 必须补 `efbundle`、备份、dry-run、apply、rollback、restore drill |
| PostgreSQL | PostgreSQL 文档支持 `pg_dump` 逻辑备份、`pg_trgm` fuzzy search；pgvector 支持向量搜索 | PostgreSQL first 正确；pgvector 和外部搜索后置到真实 benchmark |
| React/Vite | React 官方推荐框架；约束不适合时可从 Vite 等 build tool 起步；Vite 支持 `react-ts` 模板 | 保留 React + Vite SPA，但要明确 Node/browser target、typed API 和 server-state 边界 |
| Ant Design | AntD 官方定位 enterprise web app，高质量 React 组件、TypeScript、i18n | 教师工作台默认 AntD 合理；shadcn/ui 仍只作高定制备选 |
| TanStack Query | 官方定义为 server state fetching/caching/sync 工具 | 只用于 API server state；教师草稿、撤销、导出确认、高风险操作状态另有事实源 |
| 文档/OCR | Docling、PaddleOCR/PP-Structure、OCRmyPDF 均覆盖结构化文档、版面、公式、表格或 searchable PDF | Python Adapter 方向正确；必须用黄金样本和 diagnostics 隔离工具漂移 |
| OpenAI API | Structured Outputs 保证 schema adherence；Batch 降低离线任务成本；Prompt Caching 可降延迟/成本；Evals 可管理和运行评测 | 保留 structured output/eval/cache/batch 路线；真实调用前补 LLM security gate 和成本证据 |
| AI 风险 | OWASP LLM Top 10、NIST GenAI Profile 均要求专门管理 GenAI 风险 | L0-L4 模型路由之外必须补 prompt injection、敏感信息泄露、insecure output、supply chain、excessive agency gate |
| 测评互操作 | 1EdTech QTI 面向 item/test/result exchange；Moodle/OpenOLAT/TAO 均有 question bank/item bank 经验 | 不做完整 QTI/CASE/OneRoster/Caliper；先做 profile map，真实对接时再 spike |

## 4. 保留不改的方向

- 不改成纯云 SaaS、Supabase/Firebase-first 或公网多租户；学校数据、网络、采购和运维约束不匹配。
- 不提前拆微服务、RabbitMQ/Kafka、Kubernetes、独立搜索引擎、Neo4j；当前瓶颈是教师工作流、真实文档解析、备份恢复和发布闭环。
- 不把 Moodle/Open edX/TAO/OpenOLAT 当作产品路线；它们提供 question bank、item exchange 和治理经验，但本项目目标是校本教师工作流，不是通用 LMS/考试平台。
- 不把 Next.js 作为默认；本机/LAN SPA + API 更贴近当前部署与运维边界。若未来需要 SSR、多端门户或公网部署，再用 ADR 评估。
- 不让真实外部 AI 直接写生产 active；AI 只能先生成候选、证据和建议。

## 5. 必补强项

| ID | 补强项 | 归宿 |
|---|---|---|
| H007 | external benchmark drift guard | 每个重要发布周期复核官方文档、成熟项目和最佳实践，避免工程路线过期 |
| I007 | server-state 与 typed API boundary | 前端明确 TanStack Query、教师草稿、撤销和高风险状态的边界，并生成或快照 API contract；同步用 bundle analysis 处理 Vite chunk warning |
| L007 | LLM security red-team gate | 真实 AI 调用前覆盖 OWASP LLM Top 10 与 NIST GenAI Profile 关键风险 |
| O007 | EF migration bundle 与升级演练 | v0.1 release 前证明目标机可无源码/SDK执行迁移、备份、回滚和恢复 |
| R007 | interoperability profile map | 先把本仓实体映射到 QTI/CASE/OneRoster/Caliper profile，再决定是否做真实 import/export |

## 6. 工程任务优先级

近期仍按 `H0 -> I0 -> J0` 推进。新增补强不改变主线，只改变验收质量：

1. `H007` 放在 H0 收口后半段，作为路线漂移防护。
2. `I007` 与 I0 教师工作台同时做，避免前端状态变成隐形事实源；当前 Vite chunk warning 不直接调高阈值，归入 I007 的真实拆包和 bundle analysis。
3. `J0` 继续优先真实文档解析黄金样本；Docling/PaddleOCR/OpenXML/OCRmyPDF 都必须经 Adapter 输出内部模型。
4. `L007` 在真实 AI 调用前执行，不阻断当前 stub/draft/test。
5. `O007` 在发布包前执行，是 v0.1 release hard gate。
6. `R007` 只做 profile map，不做完整标准实现。

## 7. 参考来源

- Microsoft .NET support policy: https://dotnet.microsoft.com/en-us/platform/support/policy
- ASP.NET Core hosted services: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/host/hosted-services
- ASP.NET Core Windows Service: https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/windows-service
- ASP.NET Core health checks: https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/health-checks
- EF Core applying migrations / migration bundles: https://learn.microsoft.com/en-us/ef/core/managing-schemas/migrations/applying
- PostgreSQL `pg_dump`: https://www.postgresql.org/docs/17/backup-dump.html
- PostgreSQL `pg_trgm`: https://www.postgresql.org/docs/current/pgtrgm.html
- pgvector: https://github.com/pgvector/pgvector
- Npgsql EF Core provider: https://www.npgsql.org/efcore/
- React creating a React app: https://react.dev/learn/creating-a-react-app
- Vite guide: https://vite.dev/guide/
- Ant Design React: https://ant.design/docs/react/introduce
- TanStack Query overview: https://tanstack.com/query/latest/docs/framework/react/overview
- OpenAI Structured Outputs: https://developers.openai.com/api/docs/guides/structured-outputs
- OpenAI Batch API: https://developers.openai.com/api/docs/guides/batch
- OpenAI Prompt Caching: https://developers.openai.com/api/docs/guides/prompt-caching
- OpenAI Evals API: https://developers.openai.com/api/reference/resources/evals
- Docling: https://www.docling.ai/
- PaddleOCR PP-StructureV3: https://www.paddleocr.ai/v3.0.3/en/version3.x/pipeline_usage/PP-StructureV3.html
- OCRmyPDF: https://ocrmypdf.readthedocs.io/en/stable/
- OWASP Top 10 for LLM Applications: https://owasp.org/www-project-top-10-for-large-language-model-applications/
- NIST AI Risk Management Framework: https://www.nist.gov/itl/ai-risk-management-framework
- 1EdTech QTI: https://www.1edtech.org/standards/qti/index
- Moodle Questions: https://docs.moodle.org/en/Questions
- TAO user documentation: https://userguide.taotesting.com/user-documentation/latest/public/what-is-tao
- OpenOLAT question bank: https://docs.openolat.org/manual_user/question_bank/Item_Detailed_View/

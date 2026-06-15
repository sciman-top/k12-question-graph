# 26 · 官方文档、社区项目与最佳实践参考

本文件只记录会影响本项目架构、路线图和实现顺序的资料。可复制的 URL 清单见 `sources/references.md`。最近一次外部参考库整理：2026-06-09；最新 repo-side `reference-basis` / parity 核对：2026-06-14。

复核口径：优先使用官方文档或项目一手资料。社区文章只作为发现候选，不作为本仓规则依据。

长期工程终态和技术栈裁决已沉淀到 `docs/decisions/ADR-014-recommended-engineering-endstate-and-stack-boundary.md`；后续只要出现“要不要换栈、换架构、提前做平台化能力”的讨论，先回看该 ADR。

## 0. 本地浅克隆参考库

2026-06-06 已把高信号官方文档、同栈样例、教育测评平台、文档/OCR/AI 和 PostgreSQL 检索项目浅克隆到仓库外目录：

```text
D:\CODE\external\k12-question-graph-references
```

本地索引：`D:\CODE\external\k12-question-graph-references\README.md`。
机器可读清单：`D:\CODE\external\k12-question-graph-references\references.manifest.json`。
仓内只读快照：`sources/reference-shelf.manifest.snapshot.json`。

2026-06-09 已将本地参考库同步到最新 HEAD，并按当前项目主线做了一轮增删：补入 `PowerShell-Docs`、`playwright`、`react-router`、`paperless-ngx`，移除本地 `openedx-platform` 镜像；各仓当前验证提交号以 `references.manifest.json` 为准。仓内快照则通过 `tools/sync-reference-shelf-snapshot.ps1` 从外部 manifest 同步，避免 CI 因 snapshot 漂移误判。后续增补策略保持克制：优先补当前高风险主线所缺的本地官方语义锚点，例如 `postgresql-docs`；像 1EdTech、OWASP AISVS、NIST AI RMF、教育隐私/合规这类低频但权威的来源，继续保留在线锚点和仓内摘要，不为“覆盖完整”强行本地镜像。

更新入口：

```powershell
cd D:\CODE\external\k12-question-graph-references
.\update-references.ps1 -Mode core
```

按需可选：

```powershell
.\update-references.ps1 -Mode optional
.\update-references.ps1 -Mode all
```

仓内 snapshot 同步入口：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/sync-reference-shelf-snapshot.ps1
```

2026-06-14 最新核对结果：`tools/run-reference-basis-guard.ps1` 已通过，覆盖 20 个高风险任务和 13 个模块面，且 `sources/reference-shelf.manifest.snapshot.json` 与外部 `references.manifest.json` 保持 `snapshot_parity = match`。这说明当前仓内 snapshot、外部参考库和 guard 规则在 repo-side 口径上是一致的。同期新增了 `tasks/reference-basis-policy.json` 与 `tools/run-reference-basis-diff-aware-contract.ps1`，开始把 v2 参考治理从“静态登记完整”升级到“changed paths 能投影到受管模块/任务”的最小可验证形态。

已落地仓库：

| 分类 | 本地目录 | 上游 |
| --- | --- | --- |
| 官方文档 | `official-docs/AspNetCore.Docs` | https://github.com/dotnet/AspNetCore.Docs |
| 官方文档 | `official-docs/PowerShell-Docs` | https://github.com/MicrosoftDocs/PowerShell-Docs |
| 官方文档 | `official-docs/EntityFramework.Docs` | https://github.com/dotnet/EntityFramework.Docs |
| 官方文档 | `official-docs/npgsql-doc` | https://github.com/npgsql/doc |
| 官方文档 | `official-docs/Open-XML-SDK` | https://github.com/dotnet/Open-XML-SDK |
| 官方文档 | `official-docs/postgresql-docs` | https://github.com/postgres/postgres |
| 官方文档 | `official-docs/openai-dotnet` | https://github.com/openai/openai-dotnet |
| 官方文档 | `official-docs/openai-python` | https://github.com/openai/openai-python |
| 官方文档 | `official-docs/react.dev` | https://github.com/reactjs/react.dev |
| 官方文档 | `official-docs/playwright` | https://github.com/microsoft/playwright |
| 官方文档 | `official-docs/vite` | https://github.com/vitejs/vite |
| 官方文档 | `official-docs/ant-design` | https://github.com/ant-design/ant-design |
| 官方文档 | `official-docs/tanstack-query` | https://github.com/TanStack/query |
| 架构样例 | `architecture-samples/dotnet-eShop` | https://github.com/dotnet/eShop |
| 架构样例 | `architecture-samples/CleanArchitecture` | https://github.com/jasontaylordev/CleanArchitecture |
| 教育测评 | `education-assessment/moodle` | https://github.com/moodle/moodle |
| 教育测评 | `education-assessment/OpenOLAT` | https://github.com/OpenOLAT/OpenOLAT |
| 教育测评 | `education-assessment/TAO` | https://github.com/oat-sa/tao-core |
| 官方文档 | `official-docs/react-router` | https://github.com/remix-run/react-router |
| 文档/OCR/AI | `document-ocr-ai/docling` | https://github.com/docling-project/docling |
| 文档/OCR/AI | `document-ocr-ai/PaddleOCR` | https://github.com/PaddlePaddle/PaddleOCR |
| 文档/OCR/AI | `document-ocr-ai/OCRmyPDF` | https://github.com/ocrmypdf/OCRmyPDF |
| 文档/OCR/AI | `document-ocr-ai/RapidOCR` | https://github.com/RapidAI/RapidOCR |
| 文档工作流 | `document-workflows/paperless-ngx` | https://github.com/paperless-ngx/paperless-ngx |
| 数据/检索 | `data-search/pgvector` | https://github.com/pgvector/pgvector |

OpenAI Cookbook 作为在线参考保留：`https://github.com/openai/openai-cookbook`。该仓库当前包含 Windows 无法 checkout 的尾随空格路径，本机不强行克隆，避免留下异常工作树；AI routing / structured output / eval 的代码级本地官方锚点由 `official-docs/openai-dotnet` 和 `official-docs/openai-python` 补足。

使用边界：本地浅克隆用于 `rg` 检索、结构阅读和技术决策复核；官方语义仍以官网/当前版本文档为准。默认只更新 `core` 参考集；`dotnet-eShop`、`OpenOLAT`、`moodle`、`TAO`、`react-router`、`paperless-ngx`、`pgvector` 和 `postgresql-docs` 作为 `optional`，只在明确研究对应方向时更新。仓库分组、上游 URL、用途说明、最近一次验证提交号和补充说明都以外部 `references.manifest.json` 为单一真相入口。`dotnet-eShop` 只保留为低频官方样例，不作为当前 Windows/LAN-first 主线的默认架构裁决依据。`paperless-ngx` 继续保留为本地服务/归档/OCR 运维的社区辅助锚点，但不承担教师工作流或 Windows-first 主语义。Moodle、OpenOLAT、TAO 等教育平台只提炼题库、测评、课程资产、权限、审计、QTI/assessment 治理边界和迁移做法，不复制其完整 LMS 或评测平台路线。

自 2026-06-09 起，部分高风险任务不再只“建议”查参考，而是受 `tasks/reference-basis-requirements.csv` + `tasks/reference-basis-module-map.csv` + `tasks/reference-basis-policy.json` + `tools/run-reference-basis-guard.ps1` 约束：缺少官方来源或本地参考库锚点时，主 gate 直接失败。当前首批强制覆盖 `S004`、`S010`、`S011`、`REAL010`、`NS1301-NS1308`、`O008`、`P001`、`P003`、`P005`、`P006`、`R001`、`R002`、`R007`，并把 API/Web/export/score-analysis/AI routing/OCR/Windows Service/release pack/search/queue/interop 这些板块映射成机器可读 module map；守卫在本机有外部参考库时还会额外核对 `sources/reference-shelf.manifest.snapshot.json` 与外部 `references.manifest.json` 是否同构，避免“本地能过、CI 假挂”。

`tasks/reference-basis-module-map.csv` 用来回答“哪些代码板块需要参考/复刻/复用哪个官方或社区仓”，其 `adoption_mode` 当前分为 `official_semantics_first`、`official_semantics_plus_selective_pattern_reuse`、`official_semantics_plus_eval_first`、`reference_only_no_copy`。`tasks/reference-basis-policy.json` 则把当前受管 task/module 集与 adoption mode 白名单从 PowerShell 脚本里下沉成单独 policy。`sources/reference-shelf.manifest.snapshot.json` 把外部参考架的最近一次可信快照带回仓内，供 CI 和离线审查读取，而不要求 CI runner 真有 `D:\CODE\external\...`。v2 最小切片新增了 `ChangedPaths` 投影能力：`tools/run-reference-basis-guard.ps1 -ChangedPaths ...` 会报告本轮命中的 `impactedTaskIds`、`impactedModuleIds` 和 `changedPathsOutsideGuardedModules`。在此基础上，`tools/run-reference-basis-adoption-record-contract.ps1` 先把 `P005/P006` 两类 closeout 文档接入 adoption 记录结构；随后 `tools/run-reference-basis-onsite-adoption-contract.ps1` 又把同样的结构前推到 `P001/P003` 的隔离机前置包与现场准入卡。当前新增的补强点有两类：一是为 `R001` 与默认 `PostgreSQL FTS + pg_trgm` 路线补上本地 `postgresql-docs` 官方锚点，避免只靠 `npgsql-doc` 和在线网页；二是为 `R007` 补入 `TAO` 作为更贴近 assessment/QTI 的社区治理参考，而 Moodle/OpenOLAT 继续承担更偏平台治理的边界样例。这仍不是“全仓每个 feature 都强制 adoption 证据”，但已经把现场前后最敏感的几类口径从“纯文案模板”推进成了“必须带参考采纳记录”的受管面。

## 1. AI 与 API

- OpenAI Structured Outputs：AI 输出必须用 JSON Schema 或等价 schema 约束，不只靠 prompt 描述字段。
- OpenAI Prompt Caching：稳定系统上下文、题型说明、schema 和 rubric 应放在请求前缀，动态题目内容放后面。
- OpenAI Batch/Flex/Evals：离线批量导入、回归样本和成本优化应进入 P3，而不是 P0/P1。
- OpenAI .NET SDK / Python SDK：更适合作为代码级本地官方锚点，补足仅靠网页指南时对 SDK 行为、typed response surface 和未来 provider 适配的理解盲区。
- 决策影响：P0/P1 只做 schema/adapter/stub，真实 AI 调用推迟到 P3；普通教师界面不暴露 provider/model 选择。

## 2. 后端与数据库

- .NET 10 LTS 与 EF Core 10：适合作为 v0.1 的默认主线；Microsoft 当前支持矩阵显示 .NET 10 为 LTS，支持到 2028 年 11 月，但本仓仍必须在 A000 锁定本机 SDK/runtime 与目标学校运行环境。
- ASP.NET Core BackgroundService / Windows Service：支持先用单体后台服务跑 P0/P1 job，后续再按证据引入 Hangfire/RabbitMQ。
- PostgreSQL JSONB/Full Text Search/pg_trgm/pgvector：用一个数据库覆盖半结构化字段、全文、模糊和向量检索。PostgreSQL 当前文档主线已经到 18；本仓不直接追最新主版本，A000 必须锁定一个受支持主版本并验证扩展、备份和迁移。后续若触发 `R001`，默认同时复核在线 PostgreSQL 官方文档与本地 `official-docs/postgresql-docs` 锚点，而不是只看 provider 侧文档。
- PostgreSQL pg_dump/WAL/PITR：备份恢复必须同时覆盖数据库、文件仓库和配置；P0 先做 manifest 与逻辑备份占位，P6 再做完整演练。
- 决策影响：PostgreSQL 是事实源；独立搜索引擎、图数据库、对象存储均后置。

## 3. 前端与教师工作流

- React + TypeScript + Vite：适合快速建立浏览器 Web app 与类型化前端边界。
- Ant Design：适合教师后台的数据表、表单、上传、步骤条、抽屉和批量操作；默认比从零拼 UI 更省工。
- TanStack Query / React Router：适合 API 状态、缓存、重试和页面路由；其中 React Router 更适合作为按需查阅的前端路由细节参考，不需要每天默认更新。
- 决策影响：v0.1 不做营销式首页，不做学生端；首页默认普通教师高频入口，高级设置隐藏。

## 4. 文档、OCR、公式与导出

- Docling：适合 PDF/DOCX 等文档转换、版面、表格、OCR 相关实验。
- PaddleOCR / PP-Structure：适合 OCR、版面分析、表格和公式识别能力评估。
- Open XML SDK / OfficeMath：Word 导入导出、OMML 公式处理的主要 .NET 路径。
- Pandoc、KaTeX、MathJax、OCRmyPDF 等作为工具候选，不直接成为领域模型。
- 决策影响：所有外部工具必须经 Adapter 转为内部稳定 JSON，记录工具版本、输入 hash、输出 hash 和 diagnostics。

## 5. 教育技术标准

- 1EdTech QTI：题目和测试互操作。
- 1EdTech CASE：课程标准、能力框架和知识映射。
- 1EdTech OneRoster：学生、课程、成绩交换。
- 1EdTech Caliper：学习活动数据。
- 决策影响：v0.1 只预留映射字段和导入导出扩展点，不追求完整标准认证。

## 6. 安全、隐私、恢复

- OWASP ASVS：Web 应用安全验证要求。
- OWASP AISVS：AI 系统安全验证要求。
- NIST AI RMF：AI 风险管理。
- WCAG 2.2：可访问性与可理解、可操作界面。
- FERPA/COPPA/PIPL 等教育与个人信息规则：不是本仓直接给法律结论，而是要求 A000A 锁定实际部署辖区、学生数据责任方、告知/授权、外部模型传输边界和 fixture 脱敏策略。
- Windows PE、Robocopy、Task Scheduler：学校 Windows 运维与应急恢复路径。
- 决策影响：任何 AI 结果必须可审计、可人工接管；任何备份恢复不得只依赖主程序 UI。

## 7. 社区/开源项目参考原则

Moodle、OpenOLAT、TAO 等成熟教育平台可参考权限、题库、测试和标准边界；其中 TAO 更适合作为 assessment/QTI 治理边界参考，Moodle/OpenOLAT 更适合作为平台治理与审计参考。Paperless-ngx 可参考本地文档归档、OCR、搜索、备份和“本地服务 + 数据目录”思路，但只应作为社区辅助锚点，不替代 Windows-first 宿主与教师工作流语义。题库生成类 GitHub 项目可参考“按知识点、题型、难度选题”的基本思路。但这些项目通常不以中国学校教师的 Word/Excel 流程效率为最高约束，也往往缺少 Word/PDF 入库、公式题图处理、成绩分析、低成本 AI 流水线和离线备份恢复闭环。

AI 推荐：吸收社区项目的局部模型和交互思路，不复刻完整平台路线；AI routing / eval 优先参考 OpenAI 官方文档与 SDK，本地 Windows Service / 运维 / 发布预演优先参考 Microsoft 官方文档，教育平台只作治理和边界样例。

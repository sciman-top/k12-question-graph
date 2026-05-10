# 04 · 最佳技术栈与选型

## 1. AI 推荐结论

当前推荐技术栈整体正确，应保留“Windows-first + ASP.NET Core + React/TypeScript + PostgreSQL + Python Worker + 本地文件仓库”。需要优化的是把部分“二选一”收敛成默认决策，并明确后置条件。

AI 推荐默认栈：

```text
Frontend: React + TypeScript + Vite + Ant Design + TanStack Query + React Router
Backend: ASP.NET Core / .NET 10 LTS
ORM: EF Core 10 + Npgsql.EntityFrameworkCore.PostgreSQL 10.x
Database: PostgreSQL
Search: PostgreSQL FTS first, pg_trgm for fuzzy search, pgvector for semantic search
Jobs: PostgreSQL job store + ASP.NET Core BackgroundService first
Worker: Python Adapter process for Docling/PaddleOCR/OCR/AI tasks, launched through explicit environment profiles
File store: local directory first, MinIO/S3-compatible later
AI: Provider abstraction + Structured Outputs + Evals + prompt caching + batch/flex for offline tasks + optional local small-model draft profile
Ops: Windows Service + Task Scheduler + Robocopy + independent backup/restore scripts
```

## 2. 推荐技术栈

| 层 | 选型 | 理由 |
|---|---|---|
| 前端 | React + TypeScript + Vite | 生态成熟，Vite 模板和开发反馈快，适合本机/LAN Web UI |
| UI | Ant Design 默认，shadcn/ui 备选 | AntD 更适合表格、表单、上传、后台工作台；shadcn 仅在需要高定制 UI 时引入 |
| 前端数据 | TanStack Query | API 数据缓存、同步和刷新语义清晰，减少手写 loading/error/cache 状态 |
| 路由 | React Router | 教师任务入口、详情页、管理页足够使用 |
| 后端 | ASP.NET Core / .NET 10 LTS | Windows-first、服务化部署、长期支持、性能和生态稳 |
| ORM | EF Core 10 + Npgsql 10.x | PostgreSQL 一体化支持，版本与 .NET 10/EF Core 10 对齐 |
| 数据库 | PostgreSQL | JSONB、全文检索、pgvector、可靠备份 |
| 文件存储 | 本地文件仓库，后期 MinIO/S3 兼容 | 学校局域网简单可靠 |
| 队列 | PostgreSQL job store + BackgroundService；Hangfire 后置；RabbitMQ 后置 | P0/P1 降低依赖，先保证任务可审计、可恢复、可复跑 |
| Worker | Python + isolated worker profile | Docling/PaddleOCR/OCR/AI 生态强；OCR/公式依赖复杂，必须与 API 进程隔离 |
| 文档解析 | Docling + Open XML SDK + Pandoc | 多格式解析、OpenXML 操作、格式转换 |
| OCR/版面 | PaddleOCR / PP-Structure | 本地 OCR，降低 API 成本 |
| 公式显示 | KaTeX 优先，MathJax 兜底 | 浏览器渲染 LaTeX |
| docx 公式 | LaTeX → MathML/OMML + 图片兜底 | Word/WPS 兼容路径 |
| PDF/图片优化 | OCRmyPDF、Ghostscript、qpdf、ImageMagick/OpenCV/libvips | 压缩、优化、纠偏、裁边 |
| AI 接口 | Provider 抽象层 | 不绑定单一模型供应商 |
| 结构化输出 | JSON Schema / Structured Outputs | 降低格式错误 |
| 备份 | pg_dump + 文件仓库复制 + manifest + hash | 数据库与文件同时恢复 |
| Windows 运维 | Windows Service、Task Scheduler、Robocopy、WinPE | 符合学校环境 |

文档、OCR 和公式识别属于专用 Adapter，不属于 AI agent。默认选择顺序如下：

1. `.docx` 文本、表格、图片和 Office 公式优先走 OpenXML/OMML，不先转图片 OCR。
2. 文本型 PDF 优先走 PDF text/layout extraction 和 Docling 版面结构化，不先 OCR。
3. 扫描版 PDF、图片和低质量页面才进入本地 PaddleOCR PP-OCRv5 / PP-StructureV3。
4. 图片公式和扫描公式进入 PaddleOCR FormulaRecognition，默认先评估 `PP-FormulaNet_plus-M`，准确率或吞吐不够且有 GPU/离线批处理条件时再评估 `PP-FormulaNet_plus-L`。
5. Mathpix、Azure Document Intelligence 等云端 OCR/公式识别只作为可选对照或人工确认后的兜底，必须先过隐私、成本、授权、缓存和回滚准入，不作为默认生产依赖。

Worker 环境按官方文档和当前主机约束分档，不把大型 OCR/公式依赖直接内置到 .NET API 进程，也不把模型权重提交进 Git：

| 档位 | 默认用途 | 接入方式 | 准入条件 |
|---|---|---|---|
| `direct_venv_lite` | 当前默认；RapidOCR/ONNX CPU、PDF text、OpenXML | `PythonWorker.PythonExecutable` 指向独立 `.venv\Scripts\python.exe` 或 `venv\Scripts\python.exe` | `J003/J005/J006` 通过，缺引擎 fail-closed 到人工接管 |
| `uv_venv_lite` | 可复现的本地轻量 OCR 环境 | 用 `uv` 管理依赖，但 API 仍调用 `.venv\Scripts\python.exe` | lock/requirements、诊断脚本、模型缓存目录和 gate 证据齐全 |
| `conda_paddle_cpu` | PaddleOCR/PP-Structure CPU 质量基线 | 指向 conda env 内的 `python.exe`，不依赖交互式 `conda activate` | 独立环境、版本诊断、golden set 对比、卸载/回滚记录 |
| `wsl_or_docker_heavy` | PP-Structure、公式识别、批处理或 Linux 依赖重的实验档 | 通过 launcher/profile 做路径映射、volume mount、退出码、UTF-8 和模型缓存契约 | 先有 `DocumentWorkerLaunchProfile`、path mapping、timeout、日志和回滚；不得裸接 `wsl.exe` 或 `docker.exe` |

`uv run`、`conda run`、WSL 和 Docker 都只能作为受控 launcher/profile；生产配置优先调用确定的解释器路径，避免运行时临时解析依赖、改变 PATH 或隐式下载模型。Docker/WSL 档必须显式声明 host file store 到容器/WSL 路径的映射，模型缓存放在 `D:\KQG_Data\cache` 或管理员配置的等价目录。

安装策略：进入对应实现 slice 后，由代理优先自动安装和配置低风险本地环境，例如 `.venv`、`uv .venv`、RapidOCR/ONNX、Poppler 检测和 worker diagnostic；涉及 conda、PaddleOCR、Docker、WSL、GPU runtime 或系统级 PATH/driver 变更时，先生成隔离 profile、回滚说明和 golden set 准入证据，再执行或请求人工确认。

迁移到新电脑时，不继承旧机器的 OCR profile 作为事实。必须先运行 `tools/run-worker-profile-diagnostic-contract.ps1`，再按新机器 CPU、内存、GPU、Python 环境、Docker/WSL 可用性和已安装 OCR 引擎重新推荐 profile；允许安装器更新 `PythonWorker.PythonExecutable`、模型缓存目录和 worker profile，但生产默认切换必须经过 golden set 和回滚证据。

本地系统也需要独立的最佳配置画像，不能只诊断 OCR。新电脑安装、隔离机试点、学校电脑迁移或重装系统后，必须先运行 `tools/run-host-capability-diagnostic-contract.ps1`，再决定下列 profile：

| Profile | 默认推荐 | 诊断依据 | 配置动作 |
|---|---|---|---|
| `runtimeProfile` | Windows Service + explicit content root；目标机缺 runtime 时 self-contained publish | .NET、Node、npm、PowerShell、发布目录 | 写入发布方式、content root、日志目录和健康检查策略 |
| `databaseProfile` | local PostgreSQL + `pg_dump`/`pg_restore` | `psql`、`pg_dump`、`pg_restore`、版本和 extension 条件 | 未具备 CLI 前不得进入 live pilot |
| `storageBackupProfile` | local NTFS file store + manifest backup | 数据盘/备份盘容量、路径、可写性和 hash/manifest | 允许安装器生成目录和 dry-run probe；真实材料前必须有备份恢复证据 |
| `workerOcrProfile` | `direct_venv_lite` 优先，按诊断升级到 `uv_venv_lite`、`conda_paddle_cpu` 或 `wsl_or_docker_heavy` | CPU、内存、GPU、Python、OCR 模块、Poppler、Docker/WSL | 只写 profile 和模型缓存，不把引擎源码或模型权重提交进 Git |
| `exportPrintProfile` | docx/PDF artifact chain with preflight manifest | Pandoc、qpdf、Ghostscript、ImageMagick、LibreOffice/WPS/Word 可用性 | PDF 工具链不完整时保留 docx/html 导出，不宣称完整 PDF 产品化 |
| `aiNetworkProfile` | offline-first；云端 token 默认关闭 | token 环境变量是否存在、代理变量、隐私/成本策略 | 不打印 secret；云端只在授权、缓存、成本和回滚准入后启用 |
| `aiLocalModelProfile` | 高配置机器可选本地小参数模型，只做 draft/pending_review 候选 | CPU、内存、GPU/显存、Ollama、llama.cpp、vLLM、LM Studio 或自定义本地 HTTP endpoint | 不自动下载模型、不改默认 AI 路由、不替代 OCR/公式识别、不直接写 active 数据 |
| `searchProfile` | PostgreSQL FTS + `pg_trgm` first；pgvector 后置 | PostgreSQL extension、查询延迟、miss case benchmark | 无 benchmark 不引入外部搜索引擎 |
| `queueProfile` | PostgreSQL job store + `BackgroundService` first | CPU、内存、任务吞吐和失败恢复证据 | 无吞吐瓶颈不引入 Hangfire/RabbitMQ |
| `securityProfile` | bootstrap admin key -> RBAC/audit before live | O004/O004B、权限审计、密钥轮换和日志 | draft/test 可继续；live release 必须 fail-closed |

`host capability diagnostic` 是只读门禁：不安装依赖、不联网、不打印密钥、不下载模型权重、不改变生产默认配置。它只输出推荐 profile、缺口和低风险可自动执行动作；系统服务安装、驱动/GPU runtime、Docker Desktop/WSL 安装、防火墙/杀软、云 token、本地模型权重下载、本地模型默认路由切换、真实未脱敏材料和生产默认切换仍属于人工确认边界。

## 3. 版本与兼容策略

2026-05-02 外部复核结论：.NET 10/EF Core 10 主线成立，但必须把“当前推荐”落成可检查版本锁和回退条件。

| 项 | 默认 | 必须检查 | 回退/后置 |
|---|---|---|---|
| .NET | .NET 10 LTS | `dotnet --info`、SDK/runtime 主版本、目标框架 | 学校机器无法安装 runtime 时用 self-contained publish；不因部署方便降级架构 |
| EF Core/Npgsql | EF Core 10 + Npgsql 10.x | 包主版本一致、migration smoke test | 大版本升级必须 ADR + migration/gate |
| PostgreSQL | 固定一个受支持主版本 | server version、extension 可用性、backup/restore 命令 | pgvector 未安装时 P0 可 `gate_na`，但 migration 位置和启用条件必须写清 |
| Frontend | Vite React TypeScript | `npm run build`、类型检查、UI smoke | 不使用 Create React App；React Router 足够前不切 TanStack Router |
| External tools | Docling/PaddleOCR/OpenXML/Pandoc 等 | AdapterDiagnostic 记录版本、参数、hash、耗时 | 工具升级只改 Adapter，不改领域模型 |
| Worker profiles | venv/uv/conda/WSL/Docker | 启动命令、环境变量、path mapping、模型缓存和版本进入 AdapterDiagnostic | 无 profile/golden evidence 不得切换默认 OCR 引擎 |

2026-05-04 外部复核补强项：

- .NET 10 LTS 仍为默认；发布前必须记录 SDK/runtime 主版本、patch 版本和目标机 runtime/self-contained 选择。
- Windows Service 必须验证 `UseWindowsService`、content root、数据目录、日志目录和 file store 目录均来自显式配置。
- Health checks 拆成 liveness、readiness 和 management/diagnostics；数据库检查默认轻量连接或轻量 probe，避免健康检查本身拖垮数据库。
- EF Core migration 必须补 migration bundle、备份、dry-run、apply、rollback 和隔离 restore drill；发布目标机不得依赖源码目录或已安装 .NET SDK。
- TanStack Query 只管理 API server state；教师草稿、撤销快照、导出确认、高风险操作状态不得只存在前端 query cache。
- Vite/React 保留 SPA 方向，但必须记录 Node major、browser target、静态资源发布方式和 typed API contract 边界。
- OpenAI Structured Outputs、Batch、Prompt Caching 和 Evals 可保留，但真实调用前必须验证 schema subset、cache key/cached_tokens、cost ledger、human review、no active write 和 LLM security gate。

## 4. 为什么不是纯云 SaaS

学校题库和学生成绩敏感，且很多学校网络、权限、采购和数据安全要求复杂。v0.1 采用本机/局域网部署更现实。

## 5. 为什么不是一开始用复杂图数据库

v0.1 的知识图谱查询可以用 PostgreSQL 表结构 + JSONB + 全文检索 + pgvector 支撑。Neo4j 等图数据库后置，避免工程复杂度过早上升。

## 6. 为什么模型路由必须内置

AI 成本、可靠性、延迟直接影响可用性。模型路由不是建议，而是后端模块：规则/本地工具优先，小模型处理分类和标签，中/强模型处理复杂校验和疑难图文关系。

## 7. 为什么 P0 不直接上 RabbitMQ

P0/P1 的核心风险不是吞吐，而是文件、任务、数据库、备份和人工接管能否闭环。数据库持久化 job + `BackgroundService` 已足够支撑本机/LAN 初版，并能减少部署组件。若后续出现多机 Worker、严格队列隔离或大量并发导入，再评估 Hangfire/RabbitMQ。

P0 的最低实现要求是“可恢复的任务事实源”，不是“有队列”。因此必须先完成 PostgreSQL job table、lease/retry/idempotency、错误诊断和重跑入口。

## 8. 关键开源工具使用原则

- 使用 Adapter 层隔离 Docling、PaddleOCR、Pandoc、OpenXML、OCRmyPDF 等工具。
- 使用独立 worker 环境隔离 OCR/公式依赖；默认只把环境路径和 profile 纳入配置，不把 OCR 引擎源码、模型权重或 Docker 镜像内置进仓库。
- 工具输出必须转换为内部模型：DocumentModel、QuestionBlock、FormulaObject、TableObject、ImageAsset、SourceRegion。
- 不把系统核心数据模型绑定到任何第三方工具。
- 所有工具调用记录版本、参数、输入 hash、输出 hash、耗时和错误。
- 每次升级文档/OCR/导出工具前，必须用黄金样本比较输出差异、教师人工接管量和 AdapterDiagnostic，不以工具版本更高作为直接升级理由。

## 9. 参考标准预留

| 标准 | v0.1 策略 |
|---|---|
| QTI | 数据模型预留 Item/Test/Result 映射，不完整实现 |
| CASE | 知识点/课程标准映射预留，不完整实现 |
| OneRoster | 学生/班级/成绩映射预留，不完整实现 |
| Caliper | 学习活动事件预留，不完整实现 |

标准互操作采用 profile map 优先：先把本仓 `QuestionItem`、`Paper`、`KnowledgeNode`、`ScoreRecord`、`AnalysisEvent` 映射到 QTI/CASE/OneRoster/Caliper 的最小 profile，再按真实系统对接需求做 import/export spike。没有真实对接需求前，不做完整标准实现。

## 10. UI 技术裁决

AI 推荐：v0.1 默认 Ant Design，不默认 shadcn/ui。

理由：

- 本项目是教师工作台，不是营销站点或高度品牌化 C 端应用。
- v0.1 需要大量表格、筛选、上传、步骤条、抽屉、表单、权限和后台管理态，AntD 开箱更快。
- AntD 的密度、国际化、表单和数据展示能力更贴近教师高频操作。
- shadcn/ui 的优势是代码所有权和视觉定制，但会把更多组件工程负担前移，不符合 P0/P1 快速闭环。

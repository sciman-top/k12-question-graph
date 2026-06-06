# 99 · 产品化全程路线图、实施计划与任务清单

日期：2026-05-05。更新：2026-05-06，纳入 S001 完成态看板和 S0 子任务执行计划。更新：2026-05-10，纳入本地 OCR/公式识别 worker 环境档位、WSL/Docker 接入边界、新系统本地最佳配置画像、本地小参数模型诊断档和技术情报刷新准入链。更新：2026-06-04，纳入 Windows Service 主形态、服务端控制面板、安装/profile 自动配置、多 API/模型角色路由和 NS13 结构瘦身波次。

## 1. 结论

当前技术栈和工程终态不推翻。正确终态仍是：

```text
Windows/LAN first teacher workstation
-> installer/init wizard + Service Control Panel for administrators
-> Windows Service / background process as primary server runtime
-> ASP.NET Core modular monolith
-> PostgreSQL fact store + local file store
-> Python document/OCR/AI adapters through stable ports and explicit worker environment profiles
-> React/Vite/Ant Design teacher workbench
-> versioned domain assets and review workflow
-> role-routed multi API/model structured AI candidate outputs with cost/cache/eval/security gates
-> optional local small-model draft profile for capable hosts
-> trusted technology refresh catalog for changing hardware/model/OCR ecosystems
-> backup/restore/upgrade/install evidence before release
```

需要修正的是完成态口径和任务顺序。旧 A-R 路线已经建立了大量 schema、API、UI 合同、dry-run、synthetic fixture 和 preflight，但教师关心的真实闭环仍要通过新的 `S0 产品化闭环` 承接：

```text
真实导入 -> 解析/切题 -> 人工确认 -> AI 标注建议 -> 题目入库
-> 题库检索 -> 组卷 -> 导出 -> 成绩导入 -> 讲评分析 -> 备份恢复 -> 试点发布
```

同时新增横向 automation-first 约束：S0、P0-live、Q0、R0 的所有待办任务都必须先落到规则、脚本、专用 API/UI、Adapter、schema、SQL、hash/cache、typed client、模板或可复跑 contract；AI/agent 只做语义候选、复杂映射、异常复核或外层编排。机器可读合同是 `tasks/automation-first-contract.csv`，门禁是 `tools/run-automation-first-feature-contract-guard.ps1`。

## 2. 完成态分级

后续路线图和任务清单必须区分以下状态，不能再把 contract 完成直接写成生产可用：

| 状态 | 含义 | 可否支撑发布 |
|---|---|---|
| `contract_done` | schema、脚本、样例或 guard 通过 | 否 |
| `synthetic_done` | synthetic fixture 或 draft/test 数据可跑 | 否 |
| `db_backed_done` | 能真实读写 PostgreSQL/FileStore | 部分 |
| `ui_productized` | 教师 UI 接真实 API 并覆盖加载、空、错误、回退状态 | 部分 |
| `teacher_validated` | 教师或代理按真实材料完成验收并记录耗时、误差和接管点 | 是 |
| `release_ready` | 门禁、备份、恢复、隐私、权限、教师效率均通过 | 是 |

## 3. 全程路线图

| 阶段 | 目标 | 退出条件 |
|---|---|---|
| A-G 基础能力 | 工程骨架、上传、题目模型、动态资产、AI/组卷/成绩/备份合同 | 已完成，保留为底座 |
| H-O 强化能力 | 教师 shell、真实 adapter、C002 active、AI/组卷/成绩/部署合同 | 已完成大部分，但按 S001 只能视为底座，不能视为教师闭环 |
| S0 产品化闭环 | 把现有合同能力接成真实教师工作流 | S001-S012 全部完成，`P001` 才可进入 |
| NS13 产品化运行形态 | 把 Windows Service、控制面板、安装/profile、AI 路由和自动化边界收束成发布前置 | NS1301-NS1308 完成，`P001` 才可进入 |
| P0-live 试点发布 | 真实隔离机、教师代理、现场试点、反馈回流、v0.1 裁决 | P001-P006 完成 |
| Q0 多学科扩展 | 第二学科资料、复核、active、差异和 UI 简化 | Q001-Q005 完成且不破坏四入口 |
| R0 长期平台演进 | 搜索、队列、互操作、高级分析、多校部署和技术债 | 以真实瓶颈和 ADR 触发 |

## 4. S0 实施计划

S0 是当前最重要的工程阶段。它不新增花哨功能，只把已经存在的合同、静态样例和 API 变成教师可连续使用的产品链路。

| ID | 任务 | 验收重点 |
|---|---|---|
| S001 | 完成态分级与看板 | backlog 和证据能区分 contract、synthetic、DB、UI、教师验证和 release |
| S002 | 教师工作流应用服务层 | 导入、切题、审核、标注、组卷、导出、成绩、分析有稳定 application service 或 workflow aggregate |
| S003 | 真实导入工作台 API/UI 接通 | 教师上传真实授权或脱敏材料后可看到任务、页、区块、异常和来源 |
| S004 | 文档解析质量基线 | 按 OpenXML/OMML、PDF text/layout、Docling、PaddleOCR PP-OCRv5/PP-StructureV3、PP-FormulaNet、云端可选兜底的顺序覆盖 docx、文本 PDF、扫描件、公式、表格、题图；同时建立 `direct_venv_lite`、`uv_venv_lite`、`conda_paddle_cpu`、`wsl_or_docker_heavy` worker profile 准入边界，并按 golden set 输出准确率、耗时、失败原因和人工接管点 |
| S005 | 自动/半自动切题候选管线 | 生成切题候选、置信度、失败原因和 SourceRegion，不宣称全自动 |
| S006 | 人工确认与接管工作台产品化 | 合并、拆分、跳过、重跑、题图关联、撤销和保存题目形成闭环 |
| S007 | AI 标注建议审核队列 | AI 只生成候选知识点、题型、难度、答案校验建议，教师确认后才写入题目 |
| S008 | 题库生产检索与题卡 | 题库检索默认使用 C002 active，展示来源、版本、题图/公式/表格状态和授权边界 |
| S009 | 组卷持久化与题篮 | 自然语言理解、细目表、题篮、换题、撤销和版本引用可保存和复现 |
| S010 | 导出前审校与 Word/PDF 产品化 | 学生版、教师版、答案版导出前可审校，公式/题图/表格和来源授权不丢 |
| S011 | 成绩导入到讲评报告闭环 | Excel 模板复用、小题分映射、异常行、讲评报告和分层练习建议接真实 UI/API |
| S012 | 非现场端到端发布演练 | 使用授权或脱敏材料完成完整链路，记录耗时、失败、回滚和教师效率证据 |

## 5. 任务清单归宿

机器可读主清单仍是 `tasks/backlog.csv`。本轮新增 `S001-S012`，并让 `P001` 依赖 `S012`，避免在真实产品化闭环未完成时进入现场试点。

补充清单分三层：

- `tasks/productization-roadmap.csv`：S001-S012 主线产品化任务，记录目标完成态、依赖和触达模块。
- `tasks/productization-s0-execution-plan.csv`：S002-S012 的小步执行子任务，避免单个 S 任务过大而再次停留在合同层。
- `tasks/completion-state-dashboard.csv`：当前板块真实完成态，以它作为对外状态汇报和下一步排序依据。

`tasks/backlog.csv` 决定主线顺序；`tasks/productization-s0-execution-plan.csv` 决定每个 S 任务内部的实现顺序；`tasks/completion-state-dashboard.csv` 决定是否允许宣称某个板块可用。

## 6. 路线图持续优化机制

路线图不是一次性文件，后续每轮必须按以下机制更新：

1. 先运行或刷新完成态看板，确认哪些板块仍停留在 `contract_done`、`synthetic_done` 或 `db_backed_done`。
2. 每完成一个子任务，更新对应证据和必要的 `tasks/productization-s0-execution-plan.csv` 状态；只有父任务验收全部满足，才更新 `tasks/productization-roadmap.csv` 和 `tasks/backlog.csv`。
3. 如果发现某个任务仍过大，先拆分到 `tasks/productization-s0-execution-plan.csv`，不要直接扩大实现范围。
4. 如果真实实现发现路线顺序错误，先更新依赖和 guard，再编码；不要让聊天里的临时判断覆盖机器可读计划。
5. 对外汇报默认引用 `tasks/completion-state-dashboard.csv`，禁止只引用 backlog 的 `已完成`。
6. 外部硬件、OCR、推理 runtime 和模型生态发生变化时，先进入 `O008` 技术情报刷新与候选准入目录；AI API 只能做 `report_only` 摘要和候选 catalog 草案，不安装、不下载、不切默认。

日常裁决入口统一为：

- `docs/103_ExecutionControlBoard.md`：当前 Now / Next / Later
- `docs/104_OpenQuestionsAndAssumptions.md`：未决事项
- `docs/109_ReleaseGoNoGoCard.md`：发布裁决

## 7. 当前执行波次

S0 当前采用 11 个执行波次：

| 波次 | 范围 | 目标 |
|---|---|---|
| W1 | S002A-S002F | 收束教师工作流 application service 边界 |
| W2 | S003A-S003D | 真实导入工作台 API/UI 接通 |
| W3 | S004A-S004C | 文档解析质量基线和代理验收 |
| W4 | S005A-S005C | 切题候选模型、服务和 UI |
| W5 | S006A-S006C | 审核队列、人工接管、题目保存闭环 |
| W6 | S007A-S007C | AI 标注建议从 schema 到教师确认写入 |
| W7 | S008A-S008B | 题库生产检索和题卡 UI |
| W8 | S009A-S009C | 题篮、细目表和组卷 UI 产品化 |
| W9 | S010A-S010B | 导出前审校和真实 artifact chain |
| W10 | S011A-S011C | 成绩导入、小题映射和讲评报告闭环 |
| W11 | S012A-S012C | 非现场 E2E、S0 release gate、P001 前置锁 |

## 8. 技术与架构优化边界

保留：

- ASP.NET Core modular monolith。
- PostgreSQL + EF Core migrations + local file store。
- Python adapter 通过稳定 JSON contract 隔离 OpenXML/OMML、PDF text/layout、Docling、PaddleOCR、OCRmyPDF、PP-FormulaNet 和后续模型工具；云端 OCR/公式识别只能作为准入后的可选兜底。
- Worker 环境不内置到 API 进程。默认调用独立虚拟环境解释器；`uv`、`conda`、WSL、Docker 都必须通过 `DocumentWorkerLaunchProfile` 或等价 launcher/profile 声明解释器、base args、环境变量、path mapping、模型缓存、timeout、diagnostics 和回滚。
- React + Vite + Ant Design 教师工作台。
- OpenAI structured outputs、evals、prompt caching、cost/cache logs、human-in-the-loop 和 no active write guard。

优化：

- 从 `Program.cs` 中逐步抽出 application services，endpoint 只做协议转换。
- 前端静态样例逐步替换为 typed API + TanStack Query server state。
- Adapter 从“能输出结构”升级为“质量可度量、失败可接管”。
- OCR/公式识别从“单一 Python 环境”升级为“按电脑配置分档的 worker profile”，但默认档必须保持轻量、离线、本地优先和 fail-closed。
- 服务端发布从“能运行 API”升级为“Windows Service 主进程 + 安装初始化向导 + 服务端控制面板 + profile/config evidence”。
- AI 配置从“单 provider/单模型思路”升级为“多个 provider profile + 多模型角色路由 + 普通用户简化模式 + 管理员高级设置”。
- 自动化从“脚本辅助”升级为“前置处理、候选生成、批量检查、视觉代理审查、工具执行和报告生成的 allowlisted 编排”。
- 组卷和成绩分析从 synthetic contract 升级为 DB-backed workflow。
- 标准互操作只做 profile map，不提前做完整 QTI/CASE/OneRoster/Caliper。

后置：

- 微服务、RabbitMQ/Kafka、Kubernetes、独立搜索引擎、图数据库、多校 SaaS。
- 完整 LMS、在线考试、在线监考、学生端、家长端。
- 自动主观题阅卷和复杂 IRT。

## 9. 验证策略

S0 每个任务都必须至少有：

- API 或 UI 的真实执行证据。
- `tools/run-gates.ps1` 或任务级 contract。
- `tools/run-roadmap-guard.ps1` 中的主线一致性检查。
- 证据文件，包含命令、关键输出、风险、回滚。
- 教师效率说明：减少哪一步，失败后如何继续，是否增加配置负担。
- automation-first 合同覆盖：确定性预检、专用功能面、AI/agent 允许范围、例外策略和 evidence 命令。
- worker profile 合同覆盖：隔离环境、版本诊断、模型缓存、路径映射、无云端默认依赖、golden set 对比和人工接管。

## 9.1 Worker Profile 安装与配置触发

进入文档/OCR/公式识别实现 slice 时，代理应按当前电脑配置和任务风险自动完成低风险安装、部署、配置和诊断；只有遇到系统级驱动、管理员权限、Docker Desktop/WSL 安装、GPU runtime、外部云 token、真实数据授权或不可逆环境变更时才暂停确认。

默认执行顺序：

1. 先诊断现有解释器、RapidOCR/ONNX、PaddleOCR/PaddlePaddle、CUDA/GPU、Poppler、Tesseract、Docker、WSL 和模型缓存目录。
2. `direct_venv_lite` 或 `uv_venv_lite` 属低风险本地安装；可由代理自动创建环境、安装依赖、写入 profile、运行 J003/J005/J006 和 worker diagnostic。
3. `conda_paddle_cpu` 属中风险依赖安装；可由代理先创建隔离 env 和 dry-run 诊断，切换默认 profile 前必须有 golden set 对比和回滚说明。
4. `wsl_or_docker_heavy` 属中高风险部署档；必须先生成 launcher/profile、path mapping、volume、timeout、模型缓存、日志和回滚证据，再执行安装或切换。
5. 任何 profile 失败都必须 fail-closed 到 `pending_review/takeoverRequired`，不能把缺引擎、路径错误或模型下载失败伪装成自动识别成功。

新电脑安装时，安装初始化必须先运行 worker profile diagnostic，然后根据 CPU、内存、GPU、Python、uv、conda、Docker、WSL、RapidOCR、PaddleOCR、Poppler、Tesseract 和模型缓存目录重新推荐默认 profile。允许代理按诊断结果调整 `PythonWorker.PythonExecutable`、worker profile、模型缓存目录和安装动作；生产默认 profile 切换仍必须有 golden set 对比和回滚证据。

诊断入口：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-worker-profile-diagnostic-contract.ps1
```

## 9.2 本地系统最佳配置触发

路线图、实施计划和任务清单必须把“新系统重新诊断并推荐配置”当成发布前置，不把当前开发机的环境当作通用事实。触发条件包括：新电脑安装、系统重装、隔离机试点、迁移数据目录、升级 PostgreSQL/.NET/Node/Python、替换 OCR/导出工具、启用云端 AI token、切换 Windows Service 或进入 P001 live readiness。

本地系统配置分为十个 profile：

| Profile | 影响范围 | 默认路线 |
|---|---|---|
| `runtimeProfile` | .NET、Node、前端构建、Windows Service 发布 | Windows Service + explicit content root；目标机缺 runtime 时 self-contained publish |
| `databaseProfile` | PostgreSQL、migration、backup/restore CLI | local PostgreSQL + `pg_dump`/`pg_restore` |
| `storageBackupProfile` | 数据目录、文件仓库、cache、备份盘 | local NTFS file store + manifest backup |
| `workerOcrProfile` | OCR、公式识别、PDF/图片解析 worker | `direct_venv_lite` 优先，按机器能力升级 |
| `exportPrintProfile` | Word/PDF/图片 artifact chain | docx/PDF preflight manifest；工具链不完整时保留 docx/html |
| `aiNetworkProfile` | 外部 AI、代理、token、缓存和成本 | offline-first；云端 token 默认关闭 |
| `aiLocalModelProfile` | 本地小参数模型、推理运行时、draft 候选和准入评测 | 高配置机器可选 3B/7B/14B 量化模型；默认不下载、不启用、不直接写入 |
| `searchProfile` | 题库检索、模糊搜索、语义搜索 | PostgreSQL FTS + `pg_trgm` first；pgvector 后置 |
| `queueProfile` | 后台任务、导入吞吐、重试和恢复 | PostgreSQL job store + `BackgroundService` first |
| `securityProfile` | 管理员初始化、RBAC、审计和 live fail-closed | bootstrap admin key 后必须完成 RBAC/audit |

诊断入口：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-host-capability-diagnostic-contract.ps1
```

安装初始化 `O002` 必须嵌入这个诊断，并把 `localSystemProfile` 写入 evidence。`P001` 进入真实试点前，必须同时具备 installer dry-run、host capability diagnostic、worker profile diagnostic、backup/restore、权限审计和四入口 smoke 证据。允许代理根据诊断结果执行低风险动作，例如生成 draft config、写入 profile、初始化数据/cache 目录和记录缺失工具；涉及管理员权限、系统服务、驱动、Docker/WSL、云 token、本地模型权重下载、本地模型默认路由切换、真实数据或生产默认切换时必须暂停确认。

高配置电脑可以推荐安装本地小参数大模型，但只能先作为 `aiLocalModelProfile` 的 draft/pending_review 候选能力：它可用于 OCR 文本清理候选、题干规范化候选、知识点/难度/讲评草稿候选；不得替代 OCR/公式识别专用引擎，不得直接写 active 数据，不得承担正式分析口径。切换为默认 AI 路由前必须补充 eval、成本/延迟、人工接管、no active write 和回滚证据。

## 9.3 技术情报刷新与 AI API 边界

`O008` 负责适应未来硬件、OCR、公式识别、本地推理 runtime 和模型能力变化。它不是生产功能开关，而是发布前和长期维护的 `report_only` 准入链：

```text
trusted sources
-> technology refresh report
-> capability taxonomy
-> model / OCR candidate catalog
-> host and worker diagnostic matching
-> golden set eval task
-> candidate profile
-> human confirmation before install/download/default
```

默认配置文件归宿：

| 文件 | 用途 | 默认边界 |
|---|---|---|
| `configs/technology-refresh.sources.yaml` | 官方文档、官方 repo、release、model card 和弱信号社区来源 allowlist | 只读抓取；来源不在 allowlist 时只进入人工复核 |
| `configs/capability-taxonomy.yaml` | 本项目关心的能力分类，如 OCR、公式、切题、题图、标注、讲评草稿 | 允许 `unknown`，但 unknown 不能自动启用 |
| `configs/model-admission.catalog.yaml` | 本地/云端模型候选、运行时、硬件要求、license、适用任务和 eval 状态 | 默认 `candidate`，不切 AI 默认路由 |
| `configs/ocr-engine-admission.catalog.yaml` | OCR、版面、公式识别和文档解析引擎候选 | 不替代当前 OCR profile，必须跑 golden set |
| `docs/evidence/technology-refresh-report.json` | 刷新结果、候选 diff、风险、待评测任务和 no-install/no-download 证明 | 不含 API key，不含真实试卷或学生数据 |

AI API 可以用于 `O008` 的公开资料摘要、release note 归纳、candidate catalog 草案和 eval checklist 生成；不得用于自动安装依赖、下载模型权重、修改系统 PATH、启用 Docker/WSL/GPU runtime、切换默认 OCR/AI route、处理真实未脱敏材料或把候选写入 active。没有 AI API 时，`O008` 仍应能抓取元数据并生成机械 diff；有 AI API 时只提升摘要质量，不改变准入边界。

## 9.4 NS13 产品化运行形态收束

NS13 是 P001 之前的发布形态收束，不替代 S0 已完成链路，也不提前进入现场。它解决的是：真实学校电脑性能差异大、安装/升级/恢复步骤多、AI provider/model 配置复杂、前后端入口逐渐变厚、自动化边界需要产品化。

NS13 任务：

| ID | 任务 | 验收重点 |
|---|---|---|
| NS1301 | 薄入口、页面拆分与 service 收口 | endpoint/page/BackgroundService 职责 inventory，业务编排回 application service/workflow service |
| NS1302 | Windows Service 发布主形态与服务端控制面板 | service/content root/data root/log root 显式配置，控制面板只做管理入口 |
| NS1303 | 硬件探测到运行 profile 自动配置 | host/worker diagnostic 输出 profile、工具链推荐、本机 config diff 和人工确认边界 |
| NS1304 | 开源/免费工具链自动选择与配置 | OpenXML、PDF text、Docling、PaddleOCR、OCRmyPDF、qpdf、Ghostscript、ImageMagick/libvips 等按 profile 准入 |
| NS1305 | 多 API、多模型、按角色自动路由 | 普通用户简化模式，管理员 provider profile，业务代码只按角色路由 |
| NS1306 | 自动化优先的 AI/agent 工具执行编排 | agent 只调用 allowlisted tool/runbook，覆盖前置处理、候选、批检、视觉审查、工具执行和报告 |
| NS1307 | Golden OCR/import、视觉代理和 LLM security/eval gate | golden set、visual surrogate、prompt injection/output validation/schema/cost/cache/eval 进入 gate |
| NS1308 | 安装、升级、备份、恢复与 release evidence pack | installer、migration bundle、backup/restore、权限、四入口 smoke 和 P001 readiness pack |

安装器和控制面板必须共享同一套 profile/config schema，不允许出现“安装时一套规则、面板里另一套规则”。云 API key、生图 API key、文本模型 API key、并发和预算以 provider profile 保存；普通用户只看到推荐模式和连接状态，管理员才能展开 provider、role、fallback、budget、batch/cache/eval 设置。

模型路由角色必须保持抽象，不以具体模型名作为业务分支。默认角色包括 `ocr_cleanup_candidate`、`layout_reasoning_candidate`、`semantic_tagging_candidate`、`answer_rubric_check_candidate`、`paper_blueprint_planner`、`commentary_report_writer`、`visual_surrogate_reviewer`、`tool_orchestration_agent` 和 `high_risk_arbitration`。所有角色输出默认 `draft/candidate/pending_review`；高风险仲裁必须人工确认。

NS13 的机器可读任务归宿：

- `tasks/non-site-implementation-plan.csv`
- `tasks/productization-roadmap.csv`
- `tasks/backlog.csv`
- `tasks/automation-first-contract.csv`

S0 结束时必须通过：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-gates.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-s001-completion-state-dashboard.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-s0-execution-plan-guard.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-automation-first-feature-contract-guard.ps1
```

## 10. 回滚

- 文档和任务清单回滚：`git restore -- docs/03_Architecture.md docs/04_TechnologyStack.md docs/07_Document_AI_ImportPipeline.md docs/19_Roadmap.md docs/20_TaskBreakdown.md docs/99_ProductizationFullRoadmapAndTaskPlan.md docs/101_NonSiteCapabilityImplementationRoadmap.md docs/decisions/ADR-013-productized-runtime-profiles-service-control-panel-and-role-routed-ai.md tasks/backlog.csv tasks/non-site-implementation-plan.csv tasks/productization-roadmap.csv tasks/automation-first-contract.csv sources/references.md README.md`
- 代码实现阶段回滚：按每个 S 任务独立提交回滚。
- 数据与运行时回滚：继续使用 `D:\KQG_Backups` manifest、`tools/restore.ps1` 和对应 evidence 中的 restore 命令。


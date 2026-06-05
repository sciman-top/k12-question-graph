# ADR-013 · 产品化运行形态、硬件 Profile 与角色化 AI 路由

状态：Accepted

日期：2026-06-04

## 背景

本项目目标不是做一套只能在开发机上运行的重环境，而是在真实学校 Windows 电脑、教师个人工作站或校内局域网机器上，以较少步骤完成安装、恢复、升级和回滚。服务端应以 Windows Service 或后台进程为主；窗口 UI 暂时只作为服务端控制面板，负责安装初始化、运行诊断、配置和运维，不承载普通教师的主要业务工作流。

本轮复核参考：

- Microsoft ASP.NET Core Windows Service 文档：Windows Service 可不经 IIS 承载 ASP.NET Core，并可随服务器重启自动启动；`AddWindowsService` 会设置 Windows Service lifetime、content root 和 EventLog 行为。<https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/windows-service>
- Microsoft hosted services 文档：后台任务可用 `IHostedService`/`BackgroundService`，并可实现排队后台任务。<https://learn.microsoft.com/en-us/aspnet/core/fundamentals/host/hosted-services>
- EF Core migrations 文档：生产迁移应优先使用可审查 SQL 或 migration bundle，避免应用启动时直接迁移生产库。<https://learn.microsoft.com/en-us/ef/core/managing-schemas/migrations/applying>
- React/Vite/Ant Design/TanStack Query 官方文档：Vite 支持快速前端构建，Ant Design 适合企业级 React 工作台，TanStack Query 专注 server state 缓存和刷新。
- OpenAI 官方文档：Structured Outputs、Batch、Prompt Caching 和 Evals 支持结构化输出、离线批处理、成本/延迟优化和模型升级评测。
- OWASP LLM Top 10 与 NIST AI RMF：LLM 应用必须防 Prompt Injection、Insecure Output Handling，并把生成式 AI 风险纳入治理。
- Docling、PaddleOCR、paperless-ngx 和 Moodle Question Bank：文档解析/OCR/题库治理应强调可追踪来源、队列、审核、分类、版本和权限，而不是把模型输出直接当事实。

## 决策

1. 产品形态采用三层收束：
   - `Installer / Init Wizard / Service Control Panel`：安装包、初始化向导和服务端控制面板。它负责硬件探测、profile 推荐、服务安装/启动/停止、备份恢复、升级演练、AI provider/routing 配置和健康诊断。
   - `Windows Service Runtime`：ASP.NET Core 模块化单体作为主要服务端进程，承载 API、BackgroundService job loop、健康检查、管理端口和静态前端发布资源。
   - `Adapters / Data / Toolchain`：PostgreSQL 事实源、本地文件仓库、Python 文档/OCR/AI Adapter、导出工具和备份恢复工具链全部通过 profile 与 port 接入。

2. 普通教师仍通过浏览器访问 React/Vite/Ant Design 教师工作台。服务端控制面板面向安装者或管理员，只做少量按钮和状态，不做复杂业务页面。

3. 做一轮结构瘦身：
   - endpoint 只做协议转换、权限入口和错误映射；
   - application service/workflow service 承担导入、审核、AI 候选、组卷、导出、成绩分析和运维编排；
   - 前端页面按教师任务拆分，组件不直接持有业务规则；
   - 后台执行统一收口到 PostgreSQL job store、BackgroundService 和 adapter launcher/profile。

4. 不发布固定重环境。安装器和管理面板必须产品化 `hardware profile -> automatic toolchain selection -> local config generation`：
   - 先只读探测 CPU、内存、磁盘、GPU、.NET、Node、PostgreSQL CLI、Python、uv、conda、Docker/WSL、OCR/导出工具和模型缓存；
   - 输出 `localSystemProfile`、`workerOcrProfile`、`aiNetworkProfile`、`aiLocalModelProfile`、`queueProfile`、`searchProfile` 等分档；
   - 自动执行低风险动作，如创建目录、生成 draft config、初始化轻量 venv、写 profile、运行 diagnostic；
   - 系统服务安装、驱动/GPU runtime、Docker/WSL、云 API key、本地模型权重下载、默认路由切换、真实数据处理和生产 active 切换必须人工确认。

5. AI 配置采用“多 API、多模型、按任务自动路由”，但普通用户只看到简化设置。内部不按具体模型名写死，而按角色路由：
   - `local_deterministic_precheck`
   - `ocr_cleanup_candidate`
   - `layout_reasoning_candidate`
   - `semantic_tagging_candidate`
   - `answer_rubric_check_candidate`
   - `paper_blueprint_planner`
   - `commentary_report_writer`
   - `visual_surrogate_reviewer`
   - `tool_orchestration_agent`
   - `high_risk_arbitration`

   每个角色可绑定一个或多个 provider profile、并发限制、预算、超时、缓存策略、是否允许 batch、是否允许本地小模型、是否必须人工审核。具体模型名、API key、base URL 和并发数量存于配置和密钥存储，不进入业务代码常量。

6. 自动化优先，AI 增强。可高度自动化的部分包括前置解析、候选生成、批量一致性检查、视觉代理审查、工具执行、报告生成和 evidence 汇总。人工只保留在高风险裁决和异常确认上：生产 active、真实学生数据、真实外部 AI 自动写入、默认模型/工具切换、migration apply、备份恢复覆盖、现场 release decision。

## 影响

- `docs/19_Roadmap.md`、`docs/20_TaskBreakdown.md`、`docs/99_ProductizationFullRoadmapAndTaskPlan.md` 和 `docs/101_NonSiteCapabilityImplementationRoadmap.md` 增加 NS13 产品化运行形态波次。
- `tasks/backlog.csv`、`tasks/non-site-implementation-plan.csv`、`tasks/productization-roadmap.csv` 和 `tasks/automation-first-contract.csv` 增加 NS1301-NS1308。
- `P001` 进入隔离机/现场前，需要先通过 NS13 的结构瘦身、安装/profile、服务控制面板、AI role routing、自动化代理和 release evidence pack。

## 回滚

本 ADR 是规划裁决。若后续实测证明服务端控制面板或 profile 自动配置路线不适配目标学校电脑，可通过 Git 回滚本 ADR 和关联任务清单；已生成的本机配置必须保留 rollback snapshot，并禁止在没有人工确认的情况下自动覆盖生产默认配置。

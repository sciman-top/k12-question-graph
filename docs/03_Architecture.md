# 03 · 总体架构设计

## 1. 架构目标

1. Windows-first。
2. 终态校本局域网部署。
3. 浏览器 Web UI。
4. 模块化单体 + 独立 Worker，不做早期微服务。
5. 数据与程序分离。
6. AI 模型路由内置。
7. 文件、数据库、配置、AI 结果、教师偏好全部可备份恢复。
8. P0/P1 优先可运行、可验证、可回滚，而不是一次铺满所有未来模块。
9. 教学领域资产可版本化、可替换、可追溯、可迁移。

AI 推荐：继续采用“ASP.NET Core 模块化单体 + PostgreSQL + 本地文件仓库 + Python Worker”的架构。理由：它匹配 Windows/LAN 部署、学校低运维能力、Word/Excel 文件工作流、结构化数据与大文件分离、AI/OCR 工具多为 Python 生态这些事实；微服务、图数据库和纯云 SaaS 都会在 v0.1 过早增加部署和恢复成本。

## 2. 终态架构

```text
Windows Server / 校内服务器
        │
        ▼
浏览器 Web UI
        │
        ▼
ASP.NET Core API
        │
        ├── PostgreSQL：结构化数据、JSONB、自定义字段、全文检索、pgvector
        ├── 文件仓库：原始文件、优化文件、题图、公式、导出文件
        ├── Job Store：数据库持久化任务、状态、重试、审计
        ├── BackgroundService：P0/P1 本机任务执行循环
        ├── Document Worker：Docling / PaddleOCR / OpenXML / Pandoc
        ├── Formula Worker：LaTeX / MathML / OMML / SVG / PNG
        ├── AI Worker：切题、标注、校验、组卷、分析
        ├── Export Worker：Word / PDF / 图片
        └── Backup/Storage Worker：备份、压缩、缓存清理、恢复包
```

## 3. 运行模式

| 模式 | 用途 | 数据库 | 文件仓库 |
|---|---|---|---|
| 本机开发模式 | 开发与试点 | 本机 PostgreSQL | 本机固定目录 |
| 教师单机模式 | 个人题库 | PostgreSQL | 本机固定目录 |
| 校本局域网模式 | 正式使用 | 校内服务器 PostgreSQL | 校内服务器/NAS |

v0.1 直接用 PostgreSQL，避免从 SQLite 迁移带来的 JSONB、全文检索、pgvector、并发和备份语义差异。SQLite 只可作为未来离线导入工具或测试替身，不作为产品运行数据库。

## 4. 推荐目录

```text
程序：
C:\Program Files\K12QuestionGraph\

数据：
D:\KQG_Data\
  database_backups\
  file_store\
    original\
    optimized\
    assets\
    thumbnails\
    exports\
  config\
  templates\
  prompts\
  ai_rules\
  teacher_profiles\
  logs\
  recovery\
  cache\

备份：
D:\KQG_Backups\
```

## 5. 模块划分

| 模块 | 职责 |
|---|---|
| Web UI | 教师任务入口、试题导入、组卷、成绩分析、报告展示 |
| API | 权限、业务规则、任务调度、数据库访问 |
| Domain | 试题、试卷、知识点、成绩、文件、AI 任务、备份模型 |
| Domain Asset Versioning | 知识点、标签、题型、教材/课标映射、评分规则、组卷规则、AI/pipeline 策略的版本、状态、替换映射和影响报告 |
| Job Store | ImportJob/AIJob/ExportJob/BackupJob 的状态机、重试、幂等键、审计 |
| Document Worker | 文档解析、OCR、版面识别、公式/表格初处理 |
| AI Worker | 结构化输出、知识点标注、答案校验、自然语言组卷 |
| Export Worker | Word/PDF/图片导出，导出前审校 |
| Backup Worker | pg_dump、文件复制、manifest、校验、恢复包 |
| Storage Manager | 文件去重、生命周期、压缩、清理、容量监控 |
| Model Router | 决定 AI 任务用规则、本地工具、小模型、强模型或人工 |

### 5.1 模块化单体边界

长期终态仍是 modular monolith，不是分布式微服务。内部边界按 Clean/Hexagonal 思路收敛：

| 层 | 允许依赖 | 不允许依赖 |
|---|---|---|
| Domain | 领域实体、值对象、领域事件、纯规则 | EF Core、HTTP、OpenAI SDK、文件系统、Python 工具、前端 DTO |
| Application | Use case、port interface、事务边界、权限和状态流转 | 具体数据库实现、具体 OCR/AI/导出工具 |
| Ports | repository、file store、document parser、AI provider、exporter、clock、audit 等抽象 | 外部工具原始输出直接穿透到 Domain |
| Adapters | EF/Npgsql、local file store、Docling/PaddleOCR/OpenXML/OCRmyPDF、OpenAI provider、Word/PDF exporter | 反向修改 Domain 规则或绕过 use case |
| API/Web | HTTP contract、teacher workflow、view model、typed client | 把 UI 草稿或裸 JSON 形状当作业务事实源 |

验收标准：核心 use case 测试应能用 fake/in-memory ports 运行；涉及 PostgreSQL、文件系统、Python、外部 AI 或导出工具的测试属于 adapter/contract/integration 层。若某个功能必须先接真实工具，也必须先定义内部模型和 AdapterDiagnostic，不得让第三方输出成为领域模型。

## 6. 边界原则

- 大文件不进数据库。
- 数据库保存元数据、引用、hash、状态、结构化 JSON。
- 外部工具必须经过 Adapter，不把核心模型绑定到工具输出。
- AI 输出必须走 JSON Schema，不使用自由文本作为业务数据。
- 每个 AI 任务要记录模型、prompt 版本、schema 版本、成本、置信度、人工修改。
- 知识点、教材章节、课程标准、地区考点、题型、标签、难度/能力维度、评分标准、组卷规则、AI 策略、解析 pipeline、分析指标和导出模板不得作为不可迁移的静态常量写死。
- 规则和 AI 可以自动生成领域资产映射和替换建议；高影响、低置信度、一拆多、多合一或影响历史分析口径的变更必须进入人工审核。

## 7. 任务与 Worker 边界

P0/P1 默认不引入 RabbitMQ。任务状态先保存在 PostgreSQL，ASP.NET Core `BackgroundService` 轮询可执行任务并调用本机 Adapter/Worker。

任务表必须支持：

```text
job_id
job_type
status: queued/running/succeeded/failed/cancelled/retry_waiting
idempotency_key
input_file_asset_id
locked_by
locked_until
attempt_count
max_attempts
last_error_code
last_error_message
created_at/started_at/finished_at
created_by
```

`BackgroundService` 只负责执行循环，不作为任务事实源。实现时必须遵守：

- `StartAsync` 只做快速初始化，不执行长耗时导入。
- 每次领取任务必须写入 `locked_by`、`locked_until` 和 `attempt_count`，防止进程重启后任务永久卡死。
- 外部工具调用必须有超时、取消、stderr/stdout 截断和诊断落库。
- 任务重试必须幂等；同一 `idempotency_key` 不能重复创建业务结果。
- 内存队列只能做进程内加速，不能替代 PostgreSQL job table。
- Windows Service 运行时不得依赖当前工作目录；程序目录、数据目录、日志目录和文件仓库必须来自显式配置。

升级到 Hangfire 的触发条件：

- 需要成熟的仪表盘、延迟任务、重复任务和重试策略。
- P0/P1 自建 job loop 已经通过测试，且迁移成本可控。
- PostgreSQL job schema 与业务审计仍保留为事实来源。

RabbitMQ 只在需要多机 Worker、跨服务吞吐或严格队列隔离时进入后续架构评估。

## 8. 外部工具 Adapter 契约

Docling、PaddleOCR、OpenXML、Pandoc、OCRmyPDF、qpdf、Ghostscript、ImageMagick、libvips 等工具不得把原始输出直接写入业务表。每个 Adapter 必须返回稳定内部模型：

```text
DocumentModel
PageModel
LayoutBlock
QuestionBlockCandidate
FormulaObject
TableObject
ImageAsset
SourceRegion
AdapterDiagnostic
```

Adapter 输出必须记录工具名称、版本、命令参数、耗时、输入 hash、输出 hash、错误和警告。这样后续替换工具不会破坏领域模型。

## 9. Windows 部署约束

Windows-first 不等于把数据写进程序目录。P0 起必须区分：

| 路径 | 规则 |
|---|---|
| 程序目录 | 只放发布产物；升级可覆盖 |
| 数据目录 | 固定到 `D:\KQG_Data\` 或配置值；数据库备份、文件仓库、模板、prompt、日志均在此 |
| 备份目录 | 固定到 `D:\KQG_Backups\` 或配置值；可指向另一个磁盘或共享目录 |
| 当前工作目录 | 不作为任何数据定位依据 |

发布为 Windows Service 时，必须通过配置读取数据目录，并在健康检查中验证目录存在、可写、空间足够。若目标机器不能安装 .NET runtime，优先评估 self-contained publish，而不是降低目标框架。

## 10. 架构后置清单

| 能力 | 后置原因 |
|---|---|
| 微服务拆分 | v0.1 部署和恢复成本高于收益 |
| 图数据库 | PostgreSQL 表结构、JSONB、FTS、pgvector 足够支撑初中物理 |
| RabbitMQ/Kafka | P0/P1 无多机吞吐需求 |
| Kubernetes | 校本/LAN 场景运维负担过高 |
| 公网 SaaS | 数据、采购、隐私和网络约束不匹配 |

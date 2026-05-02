# 校本题谱 · Executive Spec

本文件是给人和 AI Coding Agent 的压缩入口。详细事实以 `README.md` 与 `docs/` 下分文件为准；若本文件与分文件冲突，以更具体的分文件为准。

## 1. 项目定位

**校本题谱 / K12 Question Graph** 是面向 K-12 教师的 AI 原生校本题库、组卷和学情分析平台。v0.1 只聚焦初中物理，目标是替代教师日常 Word/Excel 低效流程，而不是一次性实现完整教育平台。

## 2. 最高原则

> 教师工作流效率最大化。

可验收含义：

- 常规组卷从需求输入到可打印导出，目标不超过 10 分钟。
- 试卷导入时教师只处理异常项，不逐题确认全部结果。
- 高频流程默认值来自教师偏好、模板和历史映射。
- 每个新字段都必须证明会用于检索、组卷、分析、导出或治理。
- AI 输出必须结构化、可审计、可人工接管、可回滚。

## 3. v0.1 范围

v0.1 完整闭环：

```text
上传文件 -> AI/人工切题 -> 入库 -> 检索 -> 组卷 -> 导出 -> Excel 成绩导入 -> 基础分析 -> 备份恢复
```

明确不做：

- 在线考试、在线监考、防作弊。
- 学生端、家长端、公网 SaaS。
- 全学科一次上线。
- 自动主观题阅卷。
- 复杂 IRT。
- 完整 QTI/CASE/OneRoster/Caliper 实现。

## 4. 当前编码焦点

先做 P0/P1 最小纵切，不横向铺完整平台。

```text
P0: 打开应用 -> 登录占位 -> 上传文件 -> 创建 ImportJob -> 写数据库 -> 文件入仓 -> 备份 manifest
P1: 上传试卷 -> 文档解析/OCR 占位 -> 页面预览 -> 异常确认队列 -> 单题入库 -> 来源回看
```

P1 验收前不得实现真实在线考试、自然语言组卷、完整 AI 自动入库、成绩分析、学生端或复杂消息队列。

## 5. 默认技术栈

| 层 | 默认选择 |
| --- | --- |
| 前端 | React + TypeScript + Vite + Ant Design |
| 前端状态 | TanStack Query + React Router |
| 后端 | ASP.NET Core / .NET 10 LTS |
| ORM | EF Core 10 + Npgsql |
| 数据库 | PostgreSQL + JSONB + FTS + pg_trgm + pgvector |
| 文件 | 本地 File Store，数据库只存 metadata/path/hash |
| 任务 | PostgreSQL job table + ASP.NET Core BackgroundService |
| Worker | Python Adapter for Docling/OpenXML/PaddleOCR/AI |
| AI | Provider abstraction + Structured Outputs + Evals + prompt caching |
| 部署 | Windows-first；后续 Windows Service / LAN |
| 备份 | pg_dump + File Store manifest + config + sha256 |

后置条件：

- Hangfire：需要仪表盘、复杂重试、定时任务后再引入。
- RabbitMQ：需要跨机高吞吐和独立 worker 扩缩容后再评估。
- 图数据库/独立搜索引擎：PostgreSQL 无法支撑真实查询模式后再评估。
- 对象存储：校内 NAS/MinIO 需求明确后再引入。

## 6. 核心领域模型

P0/P1 必须先覆盖：

- `User`
- `TeacherPreference`
- `FileAsset`
- `ImportJob`
- `AIJob`
- `ReviewQueueItem`
- `BackupJob`
- `SourceDocument`
- `SourceRegion`
- `QuestionItem`
- `QuestionBlock`
- `QuestionAsset`
- `SharedMaterial`

后续阶段再扩展：

- `KnowledgeNode`
- `KnowledgeEdge`
- `KnowledgeMapping`
- `Paper`
- `Exam`
- `ScoreRecord`
- `FeedbackEvent`
- `AnalysisReport`

## 7. AI 与文档处理原则

- 外部工具必须通过 Adapter，不把 Docling/PaddleOCR/OpenXML 输出直接当领域模型。
- Adapter 输出必须包含 `tool_version`、`input_hash`、`output_hash`、`diagnostics`、`duration_ms`。
- AI 输出必须使用 JSON Schema/Structured Outputs。
- AI 任务必须记录 model、prompt_version、schema_version、cost、confidence、latency、review_status。
- 低置信度、高影响或正式题目进入人工确认队列。

## 8. 门禁

硬门禁顺序：

```text
build -> test -> contract/invariant -> hotspot
```

P0 最小门禁：

- 后端 build/test。
- 前端 build/test。
- Worker smoke test。
- JSON schema 可解析。
- YAML/CSV 可解析。
- backup manifest 可生成和校验。
- README、roadmap、task CSV、handoff prompt 的 P0/P1 术语一致。

## 9. 关键文档入口

- 产品与最高原则：`docs/00_ProjectConstitution.md`
- PRD：`docs/01_PRD.md`
- 范围控制：`docs/02_MVP_Scope_and_ScopeControl.md`
- 架构：`docs/03_Architecture.md`
- 技术栈：`docs/04_TechnologyStack.md`
- 路线图：`docs/19_Roadmap.md`
- 任务拆解：`docs/20_TaskBreakdown.md`
- 机器任务清单：`tasks/backlog.csv`
- 外部审查和决策：`docs/27_ExternalReview_DecisionLog.md`
- 功能范围审查：`docs/28_FunctionScopeReview.md`
- ADR：`docs/decisions/`

## 10. 下一步

下一步只做 P0：

1. 完成 `A000` P0 准入预检：SDK/runtime、PostgreSQL、数据目录、Windows Service/content root、BackgroundService job lease/retry/idempotency、文档门禁。
2. 创建 monorepo 目录。
3. 创建 ASP.NET Core API、React Web、Python Worker 占位。
4. 建立 PostgreSQL migration 与 FileStore。
5. 实现上传文件、ImportJob、基础状态查询。
6. 生成 backup manifest。
7. 建立统一 gate 和 P0 证据包。

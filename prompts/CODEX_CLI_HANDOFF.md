# Codex CLI 交接提示词

你正在实现“校本题谱：AI 原生校本题库与学情诊断平台”。请先阅读本文件包的 README.md 与 docs/00_ProjectConstitution.md。

## 最高约束

教师工作流效率最大化。任何实现选择都必须降低教师工作量和认知负担。

## v0.1 实现范围

完整 v0.1 只实现初中物理核心闭环：

```text
文件上传 → 文档解析/AI 入库 → 人工异常确认 → 题库检索 → 自然语言组卷 → 一键换题 → Word/PDF 导出 → Excel 成绩导入 → 基础学情分析 → 备份恢复
```

明确不做：在线考试、学生端、自动主观题阅卷、全学科、复杂 IRT、完整 QTI/CASE/OneRoster 实现。

当前只允许先实现 P0/P1：

```text
P0: 打开应用 -> 登录占位 -> 上传文件 -> 创建 ImportJob -> 写数据库 -> 文件入仓 -> 备份 manifest
P1: 上传试卷 -> 文档解析/OCR 占位 -> 页面预览 -> 异常确认队列 -> 单题入库 -> 来源回看
```

功能范围以 `docs/28_FunctionScopeReview.md` 为准。任何新功能必须先通过 `docs/25_FeatureAdmissionCriteria.md` 的准入卡，明确阶段归属和失败接管路径。

## 技术栈

- Frontend: React + TypeScript + Vite + Ant Design。
- Backend: ASP.NET Core / .NET 10 LTS。
- ORM: EF Core 10 + Npgsql。
- Database: PostgreSQL + JSONB + FTS + pg_trgm + pgvector。
- Job: PostgreSQL job table + ASP.NET Core BackgroundService first；Hangfire/RabbitMQ 后置。
- Worker: Python Adapter for Docling/OpenXML/PaddleOCR/AI tasks。
- File store: local directory first。
- AI output: JSON Schema Structured Outputs + prompt/schema/model/cost/confidence trace。
- Deployment: Windows-first。

## 初始编码顺序

1. 先执行 `A000`：确认 .NET/Node/Python/PostgreSQL 版本、数据目录、Windows Service/content root、BackgroundService job lease/retry/idempotency、文档门禁。
2. 建立 monorepo 目录。
3. 建立 ASP.NET Core API + PostgreSQL 连接 + migrations。
4. 建立 React + Vite + Ant Design UI skeleton。
5. 建立 FileStore 与 FileAsset 模型。
6. 建立 upload endpoint。
7. 建立 ImportJob/AIJob/ReviewQueue 数据模型。
8. 建立 BackupManager 最小脚本。
9. 建立统一 gate 命令，纳入 build/test/contract/invariant/hotspot。
10. 建立 P0 证据包与回滚入口。
11. 再进入 P1：文档解析/OCR Adapter、页面预览、人工确认队列、QuestionItem 保存。
12. P1 验收前不得实现题库检索、自然语言组卷、成绩分析或学生端。

不要先做高级功能。

## 质量要求

- 所有大文件不进数据库。
- 所有删除都先软删除或进回收站。
- 所有 AI 任务记录成本、置信度、prompt 版本、schema 版本。
- 所有复杂流程必须可回滚。
- 所有核心操作写入操作日志。

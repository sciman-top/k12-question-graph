# ADR-004 · 外部复核后的 P0 技术栈与门禁合同

## Status

Accepted

## Context

2026-05-02 对官方文档、标准资料和社区项目复核后，现有最高原则、技术栈、模块化单体架构和 P0/P1 路线整体成立。需要补强的是进入编码前的版本锁、Windows 本地部署约束、BackgroundService 任务事实源约束和 P0 证据门禁。

## Decision

保留默认技术栈：

```text
React + TypeScript + Vite + Ant Design
ASP.NET Core / .NET 10 LTS
EF Core 10 + Npgsql 10.x
PostgreSQL + JSONB + FTS + pg_trgm + pgvector
PostgreSQL job table + ASP.NET Core BackgroundService
Python Adapter Worker
Local File Store
```

进入 P0 编码前先完成 `A000` 准入预检；P0 收尾必须完成 `A011` 证据包与回滚入口。

## Rationale

- .NET 10/EF Core 10 与 Windows Service 部署路径匹配本项目 Windows-first/LAN 目标。
- PostgreSQL 能同时覆盖结构化数据、JSONB、全文、模糊和向量检索，减少学校环境的运维组件。
- `BackgroundService` 足够支撑 P0/P1，但任务事实源必须是 PostgreSQL job table，而不是进程内队列。
- Moodle/Open edX/TAO 证明教育平台能力边界很大，但不应把本项目拖向完整 LMS/在线考试路线。
- Paperless-ngx 证明本地文档归档、OCR、搜索和备份值得参考，但本项目的核心仍是题目语义、组卷和教师效率。

## Consequences

- `A000` 必须记录 .NET/Node/Python/PostgreSQL 版本、数据目录、Windows Service content root、job lease/retry/idempotency 和文档门禁。
- `BackgroundService` 实现必须支持 `locked_by`、`locked_until`、`attempt_count`、`max_attempts`、`idempotency_key`、错误诊断和重跑。
- Windows Service 不得依赖当前工作目录；程序、数据、备份、日志目录必须显式配置。
- 若 pgvector 或某个外部工具在 P0 环境不可用，只能按 `gate_na` 留痕，不得改变架构事实。
- P1 前不得引入微服务、RabbitMQ、完整标准互操作、学生端、在线考试或真实复杂 AI 自动入库。

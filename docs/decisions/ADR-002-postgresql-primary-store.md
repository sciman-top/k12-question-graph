# ADR-002 · PostgreSQL 作为主数据存储

## Status

Accepted

## Context

项目需要同时管理结构化题目、半结构化自定义字段、全文检索、模糊搜索、向量检索、备份恢复和事务一致性。初期团队和学校部署不适合同时维护多个数据基础设施。

## Decision

v0.1 默认使用 PostgreSQL 作为主数据库。自定义字段使用 JSONB，全文检索先用 PostgreSQL Full Text Search，模糊匹配用 pg_trgm，向量检索预留 pgvector。大文件进入 File Store，不进入数据库。

## Rationale

- 一个数据库覆盖 v0.1 的主要数据能力，降低部署和恢复复杂度。
- JSONB 能承载学校差异化字段，但字段 admission 必须证明用于检索、组卷、分析、导出或治理。
- FTS、pg_trgm、pgvector 足以覆盖早期找题和相似题能力，独立搜索引擎/图数据库后置。

## Consequences

- 所有大文件只保存 metadata、path、hash、mime、size、status。
- 备份必须同时覆盖 PostgreSQL dump、File Store manifest、配置和校验 hash。
- 若后续引入独立搜索或图数据库，PostgreSQL 仍是事实源，外部索引必须可重建。


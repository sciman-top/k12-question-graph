# ADR-010 · 搜索与语义检索准入边界

## Status

Accepted

## Date

2026-05-22

## Context

本仓当前题库检索已经通过 `E001`、`S008A/S008B`、`K001` 和 `REAL012` 证明了基本产品路径：题库检索默认引用 active C002 v1，题卡能显示来源、版本、题图/公式/表格状态，真实广州 2015 样题也能进入题号排序检索、题篮、导出预检和学情讲评引用。

同时，`REAL005` 仍保持 `not_closed`，`P001/P006` 仍未完成现场/发布证据。当前没有真实查询瓶颈、miss case 集合、latency p95 或教师找题耗时证据能证明 PostgreSQL FTS + `pg_trgm` 不足。

## Decision

R001 采取 fail-closed 准入策略。

继续允许推进的范围：

- PostgreSQL FTS + `pg_trgm` first 的基线和查询合同。
- benchmark 设计、miss case 收集模板和只读 admission report。
- pgvector 或外部搜索的候选风险分析。

阻断进入产品的范围：

- 无 benchmark 的 pgvector migration。
- 无隐私/成本/缓存策略的 embedding 生成。
- 独立搜索引擎或外部搜索服务。
- 任何绕过 active C002 version、来源证据、权限过滤或教师审核的语义排序。

语义检索或外部搜索进入 feature admission 前，至少需要：

- P006 release decision record。
- 真实题量和真实查询集合。
- PostgreSQL FTS/`pg_trgm` latency p50/p95、miss case 和排序质量基线。
- 教师找题耗时改善目标。
- extension 可用性和 index rebuild plan。
- embedding 模型、成本、缓存、隐私和删除策略。
- rollback/disable switch。

## Consequences

- R001 可以产出 admission report，但不得因为 checklist 通过就启用 pgvector 或外部搜索。
- PostgreSQL 继续作为事实源；外部索引即使未来引入也必须可重建、可禁用、可回滚。
- embedding 不得保存真实学生数据或未经授权的敏感材料。
- 任何语义检索输出都只能作为候选召回/排序，不得替代来源证据和教师审核。

## Alternatives Considered

### 立即启用 pgvector

Rejected. 当前没有真实不足证据、extension 验收、embedding 成本/隐私方案或回滚脚本。

### 接入独立搜索引擎

Rejected. 学校运维复杂度、数据同步、权限过滤和备份恢复成本高于当前收益。

### 继续 PostgreSQL first 并机器化准入报告

Accepted. 这保留后续升级通道，同时避免在教师核心流程稳定前扩大基础设施。

# ADR-011 · 队列与 Worker 扩展准入边界

## Status

Accepted

## Date

2026-05-22

## Context

本仓当前默认架构是 PostgreSQL job store + ASP.NET Core `BackgroundService` first。`docs/03_Architecture.md` 已要求 job 表保存状态、幂等键、`locked_by`、`locked_until`、`attempt_count` 和诊断；`docs/04_TechnologyStack.md` 明确 `queueProfile` 为 `postgresql_job_store_backgroundservice_first`，无吞吐瓶颈不引入 Hangfire/RabbitMQ。

`S012B` 已证明非现场代理 E2E 能跑通导入、切题、审核、标注、保存、组卷、导出、成绩、分析和备份恢复，但这仍不是现场吞吐验收。`P001` 和 `P006` 仍未关闭，没有真实机器上的 queue depth、latency p50/p95、retry rate、stuck-job、worker saturation 或教师等待时间证据。

## Decision

R002 采取 fail-closed 准入策略。

继续允许推进的范围：

- PostgreSQL job store + `BackgroundService` 的状态机、lease/retry/idempotency 合同。
- 只读或非现场的 elapsed time、queue depth、失败恢复和人工接管证据采集设计。
- Hangfire / RabbitMQ 的候选风险分析和迁移草案。

阻断进入产品的范围：

- 无 operational metrics 的 Hangfire package、schema 或 dashboard。
- 无多机 Worker 需求的 RabbitMQ / Kafka / broker service。
- 默认 worker route、发布说明或安装器默认配置改为分布式队列。
- 任何绕过 PostgreSQL 业务审计事实源的队列实现。

R002 进入 feature admission 前，至少需要：

- P006 release decision record。
- P001 隔离机或现场代理运行证据。
- BackgroundService throughput、latency p50/p95、queue depth、retry rate 和 stuck-job baseline。
- 教师工作流在队列饱和时的影响说明。
- 迁移 owner、rollback/disable switch 和恢复到 PostgreSQL job store 的方案。

## Consequences

- R002 可以产出 admission report，但不得因为 report pass 就引入 Hangfire 或 RabbitMQ。
- PostgreSQL 仍是任务事实源；外部队列即使未来引入，也只能作为执行/调度层，不能替代业务状态、审计和回滚证据。
- 任何扩展都必须证明减少教师等待或管理员排障成本，而不是只追求架构“更高级”。

## Alternatives Considered

### 立即引入 Hangfire

Rejected. 当前没有 dashboard、重复任务、延迟任务或重试策略缺口的现场证据。

### 立即引入 RabbitMQ

Rejected. 当前没有多机 Worker、严格队列隔离、broker 运维 owner 或恢复演练证据。

### 保持 BackgroundService first 并机器化准入报告

Accepted. 这保留扩展通道，同时避免在 v0.1 发布前增加学校部署和恢复复杂度。

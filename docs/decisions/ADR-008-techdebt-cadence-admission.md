# ADR-008 · 长期技术债节奏准入边界

## Status

Accepted

## Date

2026-05-22

## Context

R006 关注发布后的长期技术债节奏：门禁维护、依赖升级、性能基线和删除无效实验。当前 `P006` 仍是待办，`P001` 仍缺隔离机器安装、备份恢复、权限审计和四入口 smoke 证据。此时可以把技术债节奏做成可复跑准入合同，但不能把依赖升级、性能优化或实验清理直接当作发布动作。

仓库已有可引用的低风险基础：

- `tools/run-gates.ps1` 与 `tools/run-roadmap-guard.ps1` 承接 gate health。
- `O008` 技术情报刷新是 report-only，不安装依赖、不下载模型、不改默认路由。
- `G002` 缓存清理只允许配置化 cache root，并保留 dry-run/apply split。
- `O005` 容量和成本健康面板只做 draft/test 管理员诊断，不触达正式资产。

## Decision

R006 采取 fail-closed 准入策略。

继续允许推进的范围：

- gate health、roadmap guard、PQR preflight 和 full gate 证据刷新。
- report-only dependency/technology refresh。
- draft/test quality dashboard、storage/cost/failed-task 信号。
- 仅针对配置化 cache root 的 dry-run/apply 缓存清理。
- 技术债 inventory、owner、baseline、rollback 和 release cadence 草案。

阻断进入自动执行的范围：

- 自动升级 NuGet/npm/Python/OCR/model 依赖。
- 自动安装系统依赖、下载模型权重、改默认 OCR/AI 路由。
- 无性能基线的性能优化。
- 无 dry-run preview、owner、last-used evidence 和 rollback 的实验删除。
- 触达文件仓库、备份包、学生成绩、正式题库或生产配置的清理动作。

R006 进入正式发布节奏前，至少需要：

- P006 release decision record。
- release cadence owner。
- 最近一次 full gate、roadmap guard、dependency report 和 backup/restore evidence。
- 性能基线：场景、数据规模、机器规格、预算阈值和教师效率影响。
- stale experiment inventory：owner、last-used evidence、删除候选、dry-run preview 和 rollback。
- dependency upgrade plan：来源、版本差异、供应链风险、回滚和兼容验证。

## Consequences

- R006 可以产出 admission report，但不得因为 checklist 通过就执行依赖升级、性能改造或实验删除。
- 任何清理动作默认只允许 cache root；正式资产清理必须进入独立任务和备份/回滚门禁。
- 任何 dependency gate 因网络、源、工具或模型目录不可用时，只能记录 report-only 或 `platform_na`，不得降低供应链证据要求。
- 技术债节奏必须服务教师效率和发布稳定性，不能变成无边界重构或清理。

## Alternatives Considered

### 立即安排依赖升级和实验删除

Rejected. 当前缺 P006 发布裁决和 release cadence owner，直接升级/删除会扩大回归面。

### 只靠 full gate 代表技术债健康

Rejected. full gate 证明当前合同通过，但不能替代 dependency freshness、性能基线、stale experiment inventory 和 rollback evidence。

### 先做准入报告和 fail-closed 清单

Accepted. 这能把后续发布节奏需要的证据先机器化，同时不触碰生产数据、依赖和运行配置。

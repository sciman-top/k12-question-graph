# ADR-001 · Windows/LAN 优先的模块化单体

## Status

Accepted

## Context

本项目 v0.1 面向初中物理教师，目标是在 Windows 本机开发、后续校本局域网部署。最高原则是教师工作流效率最大化，而不是平台化扩展优先。

## Decision

采用 ASP.NET Core 模块化单体作为主应用形态，前端为 React Web UI，文档/OCR/AI 相关重任务通过 Python Worker Adapter 调用。P0/P1 不拆微服务。

## Rationale

- 单体部署、备份、排障和恢复成本最低，适合学校机房和普通教师使用场景。
- 模块化边界足以隔离题库、导入、组卷、学情、备份、AI 等领域。
- Python Worker 负责工具适配，不把工具输出格式扩散到核心领域模型。

## Consequences

- 所有跨模块契约先用内部接口和 JSON schema 固化。
- 如果后续出现跨机器高吞吐、独立扩缩容或强隔离合规要求，再用 ADR 升级到服务化。
- P0/P1 的完成证据必须证明单体路径内的上传、任务、文件、数据库和备份闭环可跑通。


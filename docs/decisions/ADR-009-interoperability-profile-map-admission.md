# ADR-009 · 标准互操作 Profile Map 准入边界

## Status

Accepted

## Date

2026-05-22

## Context

v0.1 已明确只做校本初中物理核心闭环，不完整实现 QTI、CASE、OneRoster 或 Caliper。`docs/04_TechnologyStack.md` 要求标准互操作采用 profile map 优先：先把本仓 `QuestionItem`、`Paper`、`KnowledgeNode`、`ScoreRecord`、`AnalysisEvent` 映射到 QTI/CASE/OneRoster/Caliper 的最小 profile，再按真实系统对接需求做 import/export spike。

当前 `P006` 仍是待办，没有真实第三方系统对接需求、授权样例包、字段差异报告或回滚计划。此时直接实现标准导入导出会扩大范围，并可能把外部标准字段污染内部主模型。

## Decision

R007 采取 fail-closed 准入策略。

继续允许推进的范围：

- 机器可读 profile map admission report。
- adapter/view model 边界设计。
- loss/risk/round-trip 字段标注。
- 基于公开标准语义的只读映射草案。

阻断进入产品的范围：

- 完整 QTI import/export。
- CASE 正式同步。
- OneRoster SIS 对接。
- Caliper 实时学习事件流。
- 任何把外部标准字段直接写进内部主模型、绕过版本映射或跳过人工复核的实现。

R007 进入 import/export spike 前，至少需要：

- P006 release decision record。
- 真实第三方系统需求来源。
- 授权或公开样例包。
- 字段差异、隐私风险和 round-trip 风险报告。
- adapter owner。
- rollback/disable switch。
- 人工复核入口和导入前 dry-run preview。

## Consequences

- R007 可以产出 profile map admission report，但不得因为 profile map 存在就声明标准互操作可用。
- `AnalysisEvent` 当前只按 conceptual profile 处理；未落库前不得声称 Caliper 事件流可用。
- 标准字段只能进入 adapter/view model 或 versioned mapping，不得污染 `QuestionItem`、`KnowledgeNode`、`ScoreRecord` 等内部核心模型。
- 任何 import/export spike 必须先证明真实需求和样例授权，并保留回滚和人工确认。

## Alternatives Considered

### 直接实现完整标准导入导出

Rejected. 当前没有真实系统、样例包、字段差异或验收边界，完整实现会拖慢教师核心工作流。

### 把标准字段直接加进主模型

Rejected. 这会让外部标准版本变化污染内部领域模型，破坏本仓以 adapter 隔离第三方输出的架构原则。

### 先产出 profile map 和 admission report

Accepted. 这能提前识别字段缺口和风险，同时不承诺不成熟的互操作能力。

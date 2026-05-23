# ADR-012 · 标准互操作评估准入边界

## Status

Accepted

## Date

2026-05-22

## Context

本仓 v0.1 明确后置完整标准互操作：`docs/02_MVP_Scope_and_ScopeControl.md` 允许 QTI、CASE、OneRoster、Caliper 的字段预留，但禁止完整 QTI/CASE/OneRoster 实现；`docs/04_TechnologyStack.md` 要求标准互操作采用 profile map 优先。

`R007 profile map` 已把 `QuestionItem`、`PaperBasket`、`KnowledgeNode`、`ScoreRecord` 和 `AnalysisReport/AnalysisEvent` 映射到 QTI、CASE、OneRoster、Caliper 的最小 profile，并明确它只允许 profile map，不允许 import/export spike。当前 `P006` 仍是待办，也没有真实第三方系统、授权样例包、conformance target、字段差异报告、隐私审查、adapter owner 或 rollback/disable switch。

## Decision

R003 采取 fail-closed 准入策略。

继续允许推进的范围：

- 引用 R007 profile map 的 admission report。
- 字段差异、round-trip loss、privacy risk 和 adapter/view model 边界分析。
- 只读样例解析草案和 dry-run preview 设计。

阻断进入产品的范围：

- QTI import/export 或认证声明。
- CASE sync 或把外部课程标准当作内部本体主干。
- OneRoster SIS sync、正式 roster import/export 或学生标识导出。
- Caliper event stream、学生行为事件导出或 analytics event schema migration。
- 任何把外部标准字段直接写入内部主模型、绕过版本映射或跳过人工复核的实现。

R003 进入 integration spike 前，至少需要：

- P006 release decision record。
- 真实第三方集成需求来源。
- 授权样例包和 conformance target。
- field-difference report 与 lossy round-trip risk report。
- 学生、成绩和分析数据 privacy review。
- adapter owner、dry-run preview、人工复核入口和 rollback/disable switch。

## Consequences

- R003 可以产出 admission report，但不得因为 R007 profile map 存在就声明互操作可用。
- OneRoster 和 Caliper 继续视为高隐私风险，真实学生/成绩/分析事件必须等 P001/P006 与隐私授权证据齐备。
- 标准字段只能进入 adapter/view model 或 versioned mapping，不污染内部核心模型。

## Alternatives Considered

### 直接实现 QTI import/export

Rejected. 当前没有真实目标系统、样例包、字段差异或教师收益证据。

### 把 OneRoster/Caliper 当作近期平台能力

Rejected. 这会提前触碰真实学生身份、成绩和行为事件边界，风险高于 v0.1 收益。

### 以 R007 profile map 为前置，R003 只做 admission

Accepted. 这保留未来集成通道，同时不让标准实现抢占教师核心闭环。

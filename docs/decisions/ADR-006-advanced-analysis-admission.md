# ADR-006 · 高级学情分析准入边界

## Status

Accepted

## Date

2026-05-20

## Context

`N004` 已经给出班级讲评报告 MVP：得分率、区分度、薄弱知识点和讲评建议。`REAL012` 也证明真实广州 2015 抽样题可被学情讲评引用，并且不写正式历史口径。

这些证据足以支持教师讲评中的描述性 CTT baseline，但不足以支持复杂 IRT、跨卷等值或长期成长分析。当前 F003 样本仍是 synthetic，样本量只有 2；`REAL012` 仍保持 `real005ClosureStatus=not_closed`。如果过早把高级测量结果做成教师可见报告，会制造错误解释责任，把小样本描述性指标误包装成能力量尺、成长分或跨卷可比分。

## Decision

R004 采取 fail-closed 准入策略。

允许继续使用的范围：

- 基础 CTT/讲评指标：得分率、区分度、薄弱知识点、讲评建议。
- 输出必须标注为 draft/test、非正式讲评或待现场验证口径。
- AI 只可基于确定性指标生成解释性 draft，不能直接写正式学情、IRT 参数、等值分或成长档案。

阻断进入产品的范围：

- IRT calibration。
- form equating。
- longitudinal growth。
- 任何声称跨卷可比、长期成长、能力量尺、学生排名趋势或正式历史学情的指标。

这些能力进入 feature admission 前，至少需要：

- 授权或匿名化的真实多班级样本。
- 稳定 item-to-question 映射与 active knowledge version 引用。
- 缺失数据策略。
- psychometric owner。
- teacher explanation boundary。
- rollback or disable switch。
- 对现有 CTT baseline 的收益和风险对照。

项目级暂定阈值：

- 描述性 CTT 最低样本：2；低于 30 必须提示小样本限制。
- IRT pilot 最低样本：500。
- operational equating 最低样本：1000。
- longitudinal growth 最低 cohort：3 期。

## Consequences

- R004 可以产出 admission report，但不得因为有 checklist 就把高级分析功能标为可用。
- `analysis-report` 继续保持非正式、draft/test 或现场前验证口径。
- `advanced-platform` 继续保持不可使用，直到真实瓶颈、样本、owner、解释责任和 rollback 齐备。
- 任何新增高级分析 endpoint、UI 文案、导出字段或数据库正式指标，都必须先通过 R004 合同和后续 ADR/feature admission。
- 小样本指标只能用于教师讲评辅助，不能用于学生长期评价、班级间比较或正式问责。

## Alternatives Considered

### 直接上线 IRT 或等值分析

Rejected. 当前没有足够样本、锚题设计、拟合/DIF 诊断、解释责任人和隐私授权。

### 只把高级分析做成隐藏管理员能力

Rejected. 隐藏入口不能消除解释责任和数据风险；只要指标可被导出或引用，就可能变成事实口径。

### 继续只保留基础讲评指标

Accepted for v0.1. 这条路径最符合教师效率目标：能支撑讲评和补弱，同时避免把本地工具变成高风险测量系统。

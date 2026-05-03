# 66 · Outer AI Model Selection

## 1. 目的

本文件记录外层 AI 在候选资料整理、CSV/Excel 校验、来源证据抽样、映射审核和项目注入时的模型选择。它不代表项目内已允许真实模型调用；项目内真实 AI 仍由 `D001-D003`、`AIJob`、人工审核和 production guard 控制。

## 2. 推荐策略

采用成本优先、质量兜底：

```text
规则/脚本/SQL
-> gpt-5.4-mini 批量初筛
-> gpt-5.3-codex 工程导入和复杂映射
-> gpt-5.4 高风险复核
-> gpt-5.5 少量最高风险裁决
-> 人工审核
```

## 3. 任务矩阵

| 任务 | 推荐模型 | 何时升级 |
| --- | --- | --- |
| CSV 字段、枚举、重复 ID、空来源字段检查 | `gpt-5.4-mini` | 错误原因不清，升 `gpt-5.3-codex` |
| ChatGPT Web 候选表批量初筛 | `gpt-5.4-mini` | 出现体系混淆，升 `gpt-5.3-codex` |
| 大批量机械清洗、拆文件、改列名 | `gpt-5.3-codex-spark` | 需要语义判断时，升 `gpt-5.4-mini` 或 `gpt-5.3-codex` |
| 来源证据抽样核验 | `gpt-5.3-codex` | 正式激活前存在争议，升 `gpt-5.4` |
| 复杂映射、一拆多、多合一、多对多 | `gpt-5.3-codex` | 影响组卷/学情/正式口径，升 `gpt-5.4` |
| 导入脚本、gate、migration impact、rollback | `gpt-5.3-codex` | 跨模块或数据迁移风险高，升 `gpt-5.4` |
| 正式激活前最终复核 | `gpt-5.4` | 影响长期政策口径或争议很高，升 `gpt-5.5` |
| 跨学科动态资产模型、重大 schema/路由策略 | `gpt-5.4` | 少量最高风险架构裁决，升 `gpt-5.5` |

## 4. gpt-5.5 边界

`gpt-5.5` 可以用，但只用于低频、高价值、高风险、不可轻易回滚的判断：

- 新旧课标或地区考试口径冲突。
- 正式知识点/考点体系重大重构。
- 学情指标口径迁移。
- 跨学科动态资产模型变更。
- 长期 AI routing / schema / governance 策略争议。

不得用 `gpt-5.5` 做常规 CSV 批量校验、格式转换、重复 ID 检查或普通候选表初筛。

## 5. 记录要求

每次外层 AI 校验结果进入项目时，至少记录：

- `model`
- `reasoning_effort`
- `input_artifact`
- `output_artifact`
- `sample_rate`
- `escalation_reason`
- `remaining_pending_review_count`

这些记录可以先放在会话报告中；正式导入链路完成后进入 `docs/evidence/` 或后续审核表。

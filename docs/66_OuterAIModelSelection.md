# 66 · Outer AI Model Selection

## 1. 目的

本文件记录外层 AI 在候选资料整理、CSV/Excel 校验、来源证据抽样、映射审核和项目注入时的模型选择。它不代表项目内已允许真实模型调用；项目内真实 AI 仍由 `D001-D003`、`AIJob`、人工审核和 production guard 控制。

## 2. 推荐策略

采用成本优先、质量兜底。这里的“最佳”指稳定路由策略最佳，不指某个模型名永久最佳；模型名只是当前可用性、价格和质量下的默认映射。

```text
规则/脚本/SQL/schema/hash/cache/中文显示 guard
-> gpt-5.4-mini 批量初筛
-> gpt-5.3-codex 工程导入和复杂映射
-> gpt-5.4 高风险复核
-> gpt-5.5 少量最高风险裁决
-> 人工审核
```

稳定决策顺序：

1. 能由 CSV parser、JSON Schema、SQL、hash、diff 或 gate 判断的，先用确定性工具 100% 检查。
2. 能由本地 chunk/cache、页码、题号、来源 hash、枚举映射和中文展示层 label 判断的，不调用外部 AI。
3. 批量低风险内容只用低成本模型做初筛，并把失败样本、低置信度样本和异常类别收敛出来。
4. 需要结合来源、映射、迁移影响、导入脚本或回滚脚本的任务，使用中强模型抽样或逐项复核。
5. 影响正式激活、长期学情口径、跨学科资产模型或不可轻易回滚的事项，才升级到强模型或最高档模型。
6. 模型输出不得替代来源证据、schema gate、migration impact、人工审核和 rollback evidence。

当前模型名可以随技术变化替换，但替换必须保持这些角色不变：`bulk_prefilter_model`、`engineering_review_model`、`high_risk_review_model`、`highest_risk_decision_model`。

## 3. 任务矩阵

| 任务 | 当前推荐模型 | 默认检查/抽样 | 何时升级 |
| --- | --- | --- | --- |
| 文件 hash、来源 metadata、CSV/JSON/YAML/schema、SQL、导入幂等、中文显示 guard | 不用外部 AI | 本地工具 100% | 只有本地失败原因需要解释时才给低成本模型看失败样本 |
| CSV 字段、枚举、重复 ID、空来源字段检查 | `gpt-5.4-mini` | 脚本 100%；AI 只看失败样本 | 错误原因不清，升 `gpt-5.3-codex` |
| ChatGPT Web 候选表批量初筛 | `gpt-5.4-mini` | 低风险行 5%-10%；低置信度/异常行 100% | 出现体系混淆，升 `gpt-5.3-codex` |
| 大批量机械清洗、拆文件、改列名 | `gpt-5.3-codex-spark` | 变更 diff/gate 100%；语义行不自动改 | 需要语义判断时，升 `gpt-5.4-mini` 或 `gpt-5.3-codex` |
| 来源证据抽样核验 | `gpt-5.3-codex` | draft/test 5%-10%；正式激活前 10%-20%；争议项 100% | 正式激活前存在争议，升 `gpt-5.4` |
| 复杂映射、一拆多、多合一、多对多 | `gpt-5.3-codex` | 100% 复核并保留 mapping impact | 影响组卷/学情/正式口径，升 `gpt-5.4` |
| 导入脚本、gate、migration impact、rollback | `gpt-5.3-codex` | 代码 diff、gate、rollback 入口 100% | 跨模块或数据迁移风险高，升 `gpt-5.4` |
| 正式激活前最终复核 | `gpt-5.4` | 高风险项 100%；普通项按 evidence risk 抽样 | 影响长期政策口径或争议很高，升 `gpt-5.5` |
| 跨学科动态资产模型、重大 schema/路由策略 | `gpt-5.4` | 决策材料 100%；候选方案必须可回滚 | 少量最高风险架构裁决，升 `gpt-5.5` |

## 4. gpt-5.5 边界

`gpt-5.5` 可以用，但只用于低频、高价值、高风险、不可轻易回滚的判断：

- 新旧课标或地区考试口径冲突。
- 正式知识点/考点体系重大重构。
- 学情指标口径迁移。
- 跨学科动态资产模型变更。
- 长期 AI routing / schema / governance 策略争议。

不得用 `gpt-5.5` 做常规 CSV 批量校验、格式转换、重复 ID 检查或普通候选表初筛。

## 5. Reasoning 档位

默认档位以任务风险而不是模型名决定：

| 层级 | 默认模型 | 默认 reasoning | 升级 |
| --- | --- | --- | --- |
| L0 本地确定性处理 | 不用外部 AI | none | 不允许升级，失败先修本地抽取、hash、schema 或 cache |
| L1 低成本筛查 | `gpt-5.4-mini` | low | 异常类型不清或反复失败时升 `gpt-5.3-codex medium` |
| L2 结构化候选提炼 | `gpt-5.4-mini` | medium | 多来源语义冲突、schema 反复失败时升 `gpt-5.3-codex high` |
| L3 体系合并与复杂映射 | `gpt-5.3-codex` | high | 影响组卷、检索或学情口径时升 `gpt-5.4 high` |
| L4 高风险仲裁 | `gpt-5.4` | high | 少量最高风险、难回滚裁决才升 `gpt-5.5 xhigh` |

`xhigh` 是 API/配置层对 Extra high 的可执行写法。它不是质量默认值，而是成本和风险都很高的仲裁手段。它必须有来源锚点、备选方案、影响报告和回滚计划，且不得用于批量提炼。

`tools/run-c002p-model-budget-guard.ps1` 会检查 `configs/model_routing.defaults.yaml` 中的 L0-L4 模型、reasoning、升级目标、dry-run token 上限、L4 数量上限、cache key 和 full extraction 人工预算确认要求。

## 6. 来源证据与人工审核

外层 AI 只能辅助发现风险和生成复核建议。正式激活链路必须保留可机器检查或人工复核的证据锚点：

- `source_id`
- `source_type`
- `source_title`
- `page`
- `question_number`
- `chapter_or_standard_ref`
- `evidence_excerpt`
- `source_hash`
- `mapping_id`
- `review_status`

若来源证据缺失，结果只能保持 `pending_review` 或 `candidate`，不得进入 `active` 或生产统计口径。

## 7. 记录要求

每次外层 AI 校验结果进入项目时，至少记录：

- `model_role`
- `model`
- `reasoning_effort`
- `input_artifact`
- `output_artifact`
- `sample_rate`
- `evidence_anchor_fields`
- `escalation_reason`
- `remaining_pending_review_count`

这些记录可以先放在会话报告中；正式导入链路完成后进入 `docs/evidence/` 或后续审核表。

## 8. 真实模型调用边界

本文件不改变项目内 AI 调用权限。D001-D003 当前只证明 draft/test 的 ModelRouter、AIJob 成本日志和 structured output/eval 合同；真正启用外部模型调用仍必须同时满足：

- `AllowRealModelCalls=true` 或等价配置显式开启。
- 动态领域资产满足正式来源、审核和 production guard。
- AIJob/AIResult 记录成本、tokens、cached_tokens、prompt_version、schema_version、confidence 和 review_status。
- 输出默认进入人工审核队列，不能自动写入正式 `active` 资产。
- 具备 rollback/evidence gate。

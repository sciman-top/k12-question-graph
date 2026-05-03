# 72 · C002Q AI Extract Dry Run

C002Q 在 C002Q0 readiness 通过后执行小批量候选提炼 dry-run。当前实现是合同 dry-run：使用 C002N 的真实来源 chunk/cache 锚点和 C002O 的候选提炼 schema，生成可审计候选输出、模型层级 trace、token/cost/cache 证据，但不调用真实模型、不写数据库、不覆盖 C002K。

## 1. 入口

```powershell
.\tools\run-c002q-ai-extract-dry-run.ps1
```

默认 manifest：

```text
configs/ai-evals/c002q-ai-extract-dry-run.sample.json
```

默认证据：

```text
docs/evidence/c002q-ai-extract-dry-run-report.json
```

## 2. 校验范围

- 必须先通过 `docs/evidence/c002q0-outer-ai-readiness-report.json`。
- 只抽样课程标准、教材、年报、真题 4 类来源，各取 C002N cache-hit 的 sample chunks。
- sample 不得超过 C002Q0/C002P 上限：4 个 source documents、32 个 chunks、120000 input tokens、20000 output tokens、3 个 L4 items。
- 输出必须符合 C002O 的结构化分区：knowledge point、curriculum standard item、textbook chapter、exam point、trend summary、mapping suggestion。
- 所有输出保持 `candidate/pending_review/production_eligible=false`。
- `allowRealModelCalls=false`、`externalAiCalls=0`、`noActiveWrite=true`。

## 3. 边界

本任务只证明 C002Q 小批量提炼链路、预算证据、来源锚点和人工审核边界成立。它不代表正式 C002 完成，不激活任何动态资产，也不替代 C002S 的正式化前审查。

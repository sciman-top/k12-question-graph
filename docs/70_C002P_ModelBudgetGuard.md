# 70 · C002P 分层模型路由预算门禁

## 目标

C002P 将 C002N 的真实 chunk/token 估算和 C002O 的 schema/eval 边界合并到模型路由预算门禁中。它证明后续 C002Q 只能做小批量 dry-run，不能把 33 份来源 PDF 全量提交给外部模型。

## 入口

```powershell
.\tools\run-c002p-model-budget-guard.ps1
```

该入口检查：

- `configs/model_routing.defaults.yaml` 中 L0-L4 的模型角色、reasoning、升级目标和 fail-closed 预算策略。
- C002N 报告必须 `status=pass`、`externalAiCalls=0`、source hash 覆盖通过且缓存命中。
- C002O 报告必须 `status=pass`、`allowRealModelCalls=false`、`productionEligible=false`。
- C002N 的 full source `estimatedInputTokens` 和 `chunkCount` 必须超过 C002Q dry-run 上限，从而证明 full extraction 必须要求显式预算报告和人工确认。

报告写入 `docs/evidence/c002p-model-budget-guard-report.json`。

## 当前证据

- `sourceCount`: 33
- `chunkCount`: 1478
- `estimatedInputTokens`: 520612
- C002Q dry-run 上限：最多 4 个 source documents、32 个 chunks、120000 input tokens、3 个 L4 items。
- `allow_real_model_calls`: false
- full extraction 要求：explicit budget report、human budget approval、cache hit report。

## 边界

- C002P 不调用真实模型。
- C002P 不导入候选 DB。
- C002P 不激活正式 C002。
- 超出 dry-run 上限时 fail closed；必须先进入 C002Q0 readiness，而不是直接运行外部模型。

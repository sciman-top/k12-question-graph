# 57 · D001 ModelRouter Draft/Test Contract

## 1. 目的

D001 在正式 C002 仍为 `暂缓` 时只进入 draft/test 模式。目标是建立 AI Provider 抽象和 ModelRouter 合同，而不是接入真实模型或启用生产 AI 标注。

## 2. 本轮范围

- `AiRouting` 配置声明 `AllowRealModelCalls=false`。
- `IAiProvider` 与 `StubAiProvider` 提供 provider 抽象。
- `IAiModelRouter` 返回任务路由决策。
- 规则任务可路由到 `rule`。
- LLM 类任务只能路由到 `stub_llm`。
- 路由结果包含 `routingVersion`、`promptVersion`、`schemaVersion`、`modelTier`、`costTier`、`requiresHumanReview`、`productionEligible` 和 blockers。
- 内部 API：`POST /internal/ai/model-route`。
- 内部 API：`GET /internal/ai/providers`。

## 3. 生产边界

D001 不调用外部 AI provider，不写 AI 结果，不写正式知识体系，不把 draft bootstrap 知识点作为生产输入。只要 `AllowRealModelCalls=false` 或领域资产不是 `active`，LLM 任务必须保持 `productionEligible=false` 并进入人工审核边界。

## 4. 验证

```powershell
.\tools\run-d001-model-router-contract.ps1
```

合同验证：

- `knowledge_tagging` 在 draft 资产下路由到 `stub_llm`。
- `stub_llm` provider 已注册且不支持真实模型调用。
- 真实模型调用保持禁用。
- schema 文件存在。
- draft LLM 路由不具备生产资格。
- `file_dedup` 路由到 `rule` 且无模型成本。
- 未知 AI task 返回 400。

`tools/run-gates.ps1` 已纳入 `d001 model router draft-test contract`。

## 5. 回滚

```powershell
git restore --source=HEAD -- apps/api/Program.cs apps/api/appsettings.json tools/run-gates.ps1 tools/README.md README.md docs/20_TaskBreakdown.md tasks/backlog.csv
git clean -f -- apps/api/Ai/AiModelRouter.cs apps/api/Ai/AiProvider.cs apps/api/Ai/AiRoutingOptions.cs tools/run-d001-model-router-contract.ps1 docs/57_D001_ModelRouterDraftTest.md
```

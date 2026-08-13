# 57 · D001 ModelRouter Draft/Test Contract

## 1. 目的

D001 最初在正式 C002 未激活时只进入 draft/test 模式，目标是建立 AI Provider 抽象和 ModelRouter 合同，而不是接入真实模型或启用生产 AI 标注。即使当前 C002 v1 已 active，D001 仍默认禁用真实模型调用，生产 AI 标注必须另走后续任务和人工审核边界。

## 2. 本轮范围

- `AiRouting` 配置声明 `AllowRealModelCalls=false`。
- `IAiProvider` 与 `StubAiProvider` 提供 provider 抽象。
- `IAiModelRouter` 返回任务路由决策。
- 规则任务可路由到 `rule`。
- LLM 类任务只能路由到 `stub_llm`。
- 路由结果包含 `routingVersion`、`promptVersion`、`schemaVersion`、`stage`、`modelRole`、`modelName`、`reasoningEffort`、`modelTier`、升级目标、`costTier`、`requiresHumanReview`、`productionEligible` 和 blockers。
- 业务任务按任务类型路由，而不是整份文档固定一个模型：批量结构化使用 `gpt-5.6-terra/high`，常规语义复核使用 `gpt-5.6-sol/medium`，疑难视觉使用 `gpt-5.6-terra/xhigh`，复杂映射和组卷裁决使用 `gpt-5.6-sol/xhigh`。
- `question_solving` 独立于 `answer_verification`：前者对普通、高难和复杂题均固定 `gpt-5.6-sol/xhigh` 且没有降档/换档路线；后者继续按普通一致性校验默认 `sol/medium`、风险升级 `sol/xhigh`。
- 切图模型只提出带 `bbox` 和来源锚点的候选区域，实际裁切仍由确定性工具执行；组卷模型只复核候选和软约束，硬约束仍由规则/求解器执行。
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
- `knowledge_tagging` 的计划路由为 `gpt-5.6-terra/high`，复杂语义升级到 `gpt-5.6-sol/medium`。
- `crop_candidate_generation` 的计划路由为 `gpt-5.6-terra/xhigh`，视觉与题干语义冲突可升级到 `gpt-5.6-sol/xhigh`。
- `paper_composition` 的计划路由为 `gpt-5.6-sol/xhigh`。
- `question_solving` 在 `low_cost`、`balanced`、`high_accuracy` 及全部难度/复杂度风险信号下均固定 `gpt-5.6-sol/xhigh`，不定义替代路线。
- `file_dedup` 保持 `local_deterministic/none`，不调用外部模型。
- `stub_llm` provider 已注册且不支持真实模型调用。
- 真实模型调用保持禁用。
- schema 文件存在。
- draft LLM 路由不具备生产资格。
- `file_dedup` 路由到 `rule` 且无模型成本。
- 未知 AI task 返回 400。

`tools/run-gates.ps1` 已纳入 `d001 model router draft-test contract`。

## 5. 回滚

```powershell
git restore --source=HEAD -- apps/api/Program.cs apps/api/appsettings.json configs/model_routing.defaults.yaml tools/run-gates.ps1 tools/README.md README.md docs/20_TaskBreakdown.md tasks/backlog.csv
git clean -f -- apps/api/Ai/AiModelRouter.cs apps/api/Ai/AiProvider.cs apps/api/Ai/AiRoutingOptions.cs schemas/ai/crop_candidate_generation.schema.json schemas/ai/paper_composition_review.schema.json schemas/ai/visual_asset_review.schema.json tools/run-d001-model-router-contract.ps1 docs/57_D001_ModelRouterDraftTest.md
```

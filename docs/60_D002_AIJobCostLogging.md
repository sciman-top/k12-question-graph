# 60 · D002 AIJob Cost Logging

## 1. 目的

D002 将 AIJob 从 P0 占位推进到 draft/test 可验证合同。它仍不接真实模型，不把 AI 输出写入正式知识体系，只证明每个 AI 结果都有可审计、可复算、可控成本的记录。

## 2. 本轮范围

- `AIJob` 增加：
  - `model_provider`
  - `model_name`
  - `routing_version`
  - `input_hash`
  - `input_tokens`
  - `output_tokens`
  - `cached_tokens`
  - `latency_ms`
  - `review_status`
  - `teacher_modified`
- 保留已有 `model_route`、`prompt_version`、`schema_version`、`estimated_cost`、`actual_cost`、`confidence`、`input`、`result`。
- 新增内部 draft/test API：`POST /internal/ai/jobs/stub`。
- Stub provider 写入 `pending_review`，`actual_cost = 0`，不调用外部 AI。

## 3. 生产边界

D002 不代表真实 AI 接入完成。正式模型调用仍被 D001/D002 合同阻断，直到 C002 来源提炼和后续 D003+ 审核/eval 合同满足。D002 只保证将来真实 AI 调用接入时，成本、版本、置信度、缓存和人工修改可以被追踪。

## 4. 验证

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\run-d002-ai-job-cost-contract.ps1
```

验证内容：

- EF migration 可应用。
- Stub AIJob 可创建。
- 同一 `idempotencyKey` 不重复创建 job。
- 记录 `stub_llm` provider 和 `stub` model。
- 记录 routing/prompt/schema version。
- 记录 input hash、input/output/cached tokens。
- Stub cost 为 0。
- confidence 在 0-1。
- review status 为 `pending_review`。
- `teacher_modified = false`。
- 数据库行和 API 响应一致。

`tools/run-gates.ps1` 已纳入 `d002 ai job cost contract`。

## 5. 回滚

数据库回滚：

```powershell
dotnet ef database update 20260502175147_AddDomainAssetVersioningForC002A --project apps\api\K12QuestionGraph.Api.csproj --startup-project apps\api\K12QuestionGraph.Api.csproj
dotnet ef migrations remove --project apps\api\K12QuestionGraph.Api.csproj --startup-project apps\api\K12QuestionGraph.Api.csproj
```

代码回滚：

```powershell
git restore --source=HEAD -- README.md apps/api/Program.cs apps/api/Domain/P0Entities.cs apps/api/Data/KqgDbContext.cs apps/api/Data/Migrations/KqgDbContextModelSnapshot.cs docs/20_TaskBreakdown.md tasks/backlog.csv tools/README.md tools/run-gates.ps1
git clean -f -- apps/api/Ai/AiJobDtos.cs apps/api/Data/Migrations/20260503053704_AddAiJobCostLoggingForD002.cs apps/api/Data/Migrations/20260503053704_AddAiJobCostLoggingForD002.Designer.cs tools/run-d002-ai-job-cost-contract.ps1 docs/60_D002_AIJobCostLogging.md
```

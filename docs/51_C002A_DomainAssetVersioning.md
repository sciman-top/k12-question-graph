# 51 · C002A Domain Asset Versioning

## 1. 目的

C002A 将“动态领域资产”从规则落到数据库和 gate。知识点、标签、题型、教材/课标/考点、难度/能力、rubric、组卷规则、AI 策略、解析 pipeline、分析指标和导出模板后续都必须依赖版本化资产契约，而不是静态 enum 或不可追溯字符串。

## 2. 已落库模型

- `domain_asset_versions`: 记录 `asset_type`、`stable_id`、`version`、`status`、`authority`、`effective_scope`、`source_evidence`、`metadata`。
- `domain_asset_mappings`: 记录 draft/formal 或新旧版本之间的 `equivalent/split/merge/broader/narrower/renamed/deprecated` 映射、置信度、审核状态和迁移引用。
- `domain_asset_migrations`: 记录 dry-run 或正式迁移的 `impact_report`、`rollback_snapshot`、状态和执行时间。

`KnowledgeNode.status` 同步扩展为 `draft/candidate/reviewed/active/deprecated/merged/superseded`，避免后续正式来源提炼、合并、替换和废弃流程被旧状态机卡住。

## 3. 自动化与人工审核边界

规则和 AI 可以先自动生成映射、替换和迁移建议。高置信度、低影响、可回滚的一对一映射可进入 `auto_applied`；一拆多、多合一、低置信度、高影响、影响历史学情口径或生产组卷规则的变更必须进入 `pending_review`。

## 4. 验证

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\run-c002a-domain-asset-contract.ps1
```

Full gate 已接入：

```powershell
.\tools\run-gates.ps1
```

验证内容：

- 三张动态资产表存在。
- version/status/authority/mapping/review/migration 约束存在。
- JSONB 证据、范围、影响报告和回滚快照字段存在。
- 映射和迁移外键存在。
- `KnowledgeNode.status` 支持 candidate/reviewed/merged/superseded。
- 可插入一组 dry-run draft -> formal 映射并通过 transaction rollback 清理。

## 5. 回滚

代码和 migration 回滚：

```powershell
dotnet ef database update 20260502164509_AddKnowledgeOntologyForC001 --project apps\api\K12QuestionGraph.Api.csproj --startup-project apps\api\K12QuestionGraph.Api.csproj
dotnet ef migrations remove --project apps\api\K12QuestionGraph.Api.csproj --startup-project apps\api\K12QuestionGraph.Api.csproj
git restore --source=HEAD -- apps/api/Domain/P0Entities.cs apps/api/Data/KqgDbContext.cs tools/run-gates.ps1 tools/README.md tasks/backlog.csv docs/20_TaskBreakdown.md
git clean -f -- apps/api/Data/Migrations/20260502175147_AddDomainAssetVersioningForC002A.cs apps/api/Data/Migrations/20260502175147_AddDomainAssetVersioningForC002A.Designer.cs tools/run-c002a-domain-asset-contract.ps1 docs/51_C002A_DomainAssetVersioning.md
```

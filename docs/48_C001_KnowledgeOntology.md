# 48 · C001 Knowledge Ontology 证据

执行日期：2026-05-03。

## 1. 完成范围

- 新增知识本体核心实体：
  - `KnowledgeNode`
  - `KnowledgeEdge`
  - `KnowledgeMapping`
- 新增 EF Core migration：
  - `AddKnowledgeOntologyForC001`
- `QuestionItem.PrimaryKnowledgeId` 从预留字段升级为真实外键。
- 三类知识本体表均包含 `version` 字段，用于后续映射变更不破坏历史记录。
- 当前不做 C002 的初中物理 L1-L3 seed，不做 AI 自动标注，不做前端知识点管理页面。

## 2. Contract 验证

独立命令：

```powershell
$env:PGPASSWORD='postgres'
.\tools\run-c001-contract.ps1
```

验证内容：

- `knowledge_nodes`、`knowledge_edges`、`knowledge_mappings` 表存在。
- 三张表均包含 `version` 字段。
- `metadata` / `evidence` 使用 `jsonb`。
- `QuestionItem -> KnowledgeNode`、`KnowledgeMapping -> QuestionItem/KnowledgeNode`、`KnowledgeEdge -> KnowledgeNode` 外键存在。
- status、edge type、mapping source、confidence、version、level 等约束存在。

Full gate：

```powershell
$env:PGPASSWORD='postgres'
.\tools\run-gates.ps1
```

关键输出应包含：

```text
c001 knowledge ontology contract: pass
```

## 3. 回滚

代码/文档回滚：

```powershell
git restore --source=HEAD -- apps/api/Domain/P0Entities.cs apps/api/Data/KqgDbContext.cs apps/api/Data/Migrations/KqgDbContextModelSnapshot.cs tools/run-gates.ps1 tools/README.md tasks/backlog.csv docs/20_TaskBreakdown.md docs/48_C001_KnowledgeOntology.md
git clean -f -- apps/api/Data/Migrations/20260502164509_AddKnowledgeOntologyForC001.cs apps/api/Data/Migrations/20260502164509_AddKnowledgeOntologyForC001.Designer.cs tools/run-c001-contract.ps1
```

若已应用数据库 migration：

```powershell
$env:PGPASSWORD='postgres'
dotnet ef database update AddQuestionBlocksAssetsForB005 --project apps/api/K12QuestionGraph.Api.csproj --startup-project apps/api/K12QuestionGraph.Api.csproj
```

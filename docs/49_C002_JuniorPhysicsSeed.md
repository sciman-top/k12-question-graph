# 49 · C002 Junior Physics L1-L3 Seed 证据

执行日期：2026-05-03。

## 1. 完成范围

- 新增版本化 seed 数据：
  - `configs/knowledge/junior-physics-l1-l3.json`
- 新增幂等 seed 脚本：
  - `tools/seed-knowledge.ps1`
- 新增 seed validation：
  - `tools/run-c002-seed-validation.ps1`
- Seed 范围：
  - L1：5 个模块。
  - L2：17 个专题。
  - L3：35 个核心知识点/规律/方法/实验。
  - Parent-child `KnowledgeEdge`：52 条。
- 当前不做 C003 的公式/实验/方法/易错点扩展治理，不做教材/课标/地区考点映射，不做 AI 自动标注。

## 2. 验证

独立命令：

```powershell
$env:PGPASSWORD='postgres'
.\tools\run-c002-seed-validation.ps1
```

验证内容：

- C001 三张知识本体表存在。
- Seed 脚本连续执行两次后节点数量不重复。
- L1/L2/L3 节点数量与 seed 文件一致。
- 所有 L2/L3 节点都有 `parent_id`。
- Parent-child edge 数量与 seed 文件一致。
- Synthetic question 可绑定 L3 知识点。
- 同一题目写入 version 1 和 version 2 的 `KnowledgeMapping` 后，原始 `SourceRegion` 仍可追溯。

Full gate：

```powershell
$env:PGPASSWORD='postgres'
.\tools\run-gates.ps1
```

关键输出应包含：

```text
c002 junior physics seed validation: pass
```

## 3. 回滚

代码/文档回滚：

```powershell
git restore --source=HEAD -- tools/run-gates.ps1 tools/README.md tasks/backlog.csv docs/20_TaskBreakdown.md docs/49_C002_JuniorPhysicsSeed.md
git clean -f -- configs/knowledge/junior-physics-l1-l3.json tools/seed-knowledge.ps1 tools/run-c002-seed-validation.ps1
```

数据库 seed 数据清理：

```sql
delete from knowledge_edges where metadata->>'seed_id' = 'C002_JUNIOR_PHYSICS_V1';
delete from question_items where custom_fields->>'validation' = 'C002';
delete from source_regions
where source_document_id in (
  select id from source_documents where source_title = 'C002 validation source'
);
delete from source_documents where source_title = 'C002 validation source';
delete from knowledge_nodes where metadata->>'seed_id' = 'C002_JUNIOR_PHYSICS_V1';
```

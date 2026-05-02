# 49 · C002 Junior Physics Draft Bootstrap 证据

执行日期：2026-05-03。

## 0. 口径修正

本文件记录的不是正式 C002 完成证据。正式知识点节点应在教师录入或导入各版本教材、学科课程标准、近年当地中考/高考真题、校本试卷等资料后，从来源资料中提炼候选节点并经人工审核确定。

当前 seed 仅是开发期 draft bootstrap，用于验证 C001 schema、层级关系、题目绑定、映射历史、来源追溯、测试筛选和组卷约束。它可以被测试题目绑定，但必须保持 `status = draft`，并带有 `source_basis = bootstrap_draft_not_authoritative` 标记；不得作为校本正式知识本体。

正式资料录入并审核后，可以用来源提炼后的节点版本替换或更新这些草稿节点。替换时必须保留版本、状态和来源证据：草稿继续用于历史测试追溯，正式 `active` 节点进入生产流程。

## 1. 完成范围

- 新增非权威 draft bootstrap 数据：
  - `configs/knowledge/junior-physics-l1-l3.json`
- 新增幂等 seed 脚本：
  - `tools/seed-knowledge.ps1`
- 新增 draft guard validation：
  - `tools/run-c002-seed-validation.ps1`
- Draft bootstrap 范围：
  - L1：5 个模块。
  - L2：17 个专题。
  - L3：35 个核心知识点/规律/方法/实验。
  - Parent-child `KnowledgeEdge`：52 条。
- 当前不做正式 C002 来源提炼，不做 C003 的公式/实验/方法/易错点扩展治理，不做教材/课标/地区考点映射，不做 AI 自动标注。

## 2. 验证

独立命令：

```powershell
$env:PGPASSWORD='postgres'
.\tools\run-c002-seed-validation.ps1
```

验证内容：

- C001 三张知识本体表存在。
- Seed 脚本连续执行两次后节点数量不重复。
- 所有 bootstrap 节点保持 `draft`。
- 所有 bootstrap 节点带有非权威来源标记。
- Bootstrap 节点可用于测试题目绑定，但不得作为正式来源提炼完成证据。
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

数据库 draft bootstrap 数据清理：

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

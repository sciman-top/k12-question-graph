# 44 · B005 Question Save 证据

执行日期：2026-05-03。

## 1. 完成范围

- 新增 `QuestionBlock` 领域实体与 `question_blocks` 表。
- 新增 `QuestionAsset` 领域实体与 `question_assets` 表。
- 保留 `QuestionItem.blocks` JSONB 快照，同时把结构化 block/asset 写入行表。
- 新增 API：
  - `POST /questions`
  - `GET /questions/{id}`
- 保存时校验引用的 `SourceRegion` 与 `FileAsset` 存在。
- 支持保存：
  - 题干文本。
  - 选项。
  - 公式。
  - 表格。
  - 答案。
  - 解析。
  - 图片/题图 asset。
  - `SourceRegion` 回看引用。

## 2. 数据库变更

Migration:

```text
20260502162853_AddQuestionBlocksAssetsForB005
```

新增表：

```text
question_blocks
question_assets
```

关键约束：

```text
question_blocks.question_item_id -> question_items.id cascade
question_blocks.source_region_id -> source_regions.id restrict
question_assets.question_item_id -> question_items.id cascade
question_assets.file_asset_id -> file_assets.id restrict
question_assets.source_region_id -> source_regions.id restrict
ck_question_blocks_sort_order: sort_order >= 0
```

## 3. Gate 结果

命令：

```powershell
$env:PGPASSWORD='postgres'
.\tools\run-gates.ps1
```

关键输出：

```text
backend build: pass
frontend build: pass
frontend lint: pass
b004 manual review ui contract: pass
b004a failure takeover ui contract: pass
worker smoke: pass
b002 adapter contract smoke: pass
doc schema config csv: pass
database smoke: pass
b001 duplicate upload smoke: pass
b003 source preview smoke: pass
b005 save question api smoke: pass
backup verify: pass
overall: pass
```

已知非阻断警告：

```text
Vite chunk-size warning due Ant Design bundle.
```

## 4. 回滚

代码/文档回滚：

```powershell
git restore --source=HEAD -- apps/api tools tasks docs/44_B005_QuestionSave.md
```

数据库回滚到 B003 migration：

```powershell
$env:KQG_CONNECTION_STRING='Host=127.0.0.1;Port=5432;Database=k12_question_graph;Username=postgres;Password=<local-password>'
dotnet tool run dotnet-ef database update 20260502161648_AddSourceRegionsForB003 --project apps\api\K12QuestionGraph.Api.csproj --startup-project apps\api\K12QuestionGraph.Api.csproj
```

不得使用 `git reset --hard`，除非明确确认要丢弃本轮所有改动。

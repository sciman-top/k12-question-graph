# 41 · B003 SourceRegion Preview 证据

执行日期：2026-05-03。

## 1. 完成范围

- 新增 `SourceRegion` 领域实体。
- 新增 `source_regions` 表，保存：
  - `source_document_id`
  - `page_number`
  - bbox: `x/y/width/height`
  - `coordinate_unit`
  - `screenshot_relative_path`
  - `region_type`
- 新增 API：
  - `POST /source-documents/{id}/regions`
  - `GET /source-documents/{id}/preview`
- 预览响应按页返回 page number 和 regions。
- 截图路径必须是 FileStore 内相对路径；截图缺失时 API 返回明确错误 `source_region_screenshot_missing`，不静默返回空白。
- `tools/run-gates.ps1` 新增 `b003 source preview smoke`。

## 2. 数据库变更

Migration:

```text
20260502161648_AddSourceRegionsForB003
```

关键约束：

```text
ck_source_regions_page_number: page_number >= 1
ck_source_regions_bbox: x >= 0 and y >= 0 and width > 0 and height > 0
ck_source_regions_coordinate_unit: pixel / point / percent
ix_source_regions_source_document_id_page_number
```

## 3. Smoke 证据

Gate 中执行的最小流程：

```text
upload sample file
create preview placeholder under FileStore
POST /source-documents/{id}/regions
GET /source-documents/{id}/preview
assert pageNumber=1
assert coordinateUnit=percent
assert screenshotRelativePath preserved
assert preview returns at least one page and one region
```

## 4. Gate 结果

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
worker smoke: pass
b002 adapter contract smoke: pass
doc schema config csv: pass
database smoke: pass
b001 duplicate upload smoke: pass
b003 source preview smoke: pass
backup verify: pass
overall: pass
```

已知非阻断警告：

```text
Vite chunk-size warning due Ant Design bundle.
```

## 5. 回滚

代码/文档回滚：

```powershell
git restore --source=HEAD -- apps/api tools tasks docs/41_B003_SourceRegionPreview.md
```

数据库回滚到 B001 migration：

```powershell
$env:KQG_CONNECTION_STRING='Host=127.0.0.1;Port=5432;Database=k12_question_graph;Username=postgres;Password=<local-password>'
dotnet tool run dotnet-ef database update 20260502160722_AddSourceDocumentsForB001 --project apps\api\K12QuestionGraph.Api.csproj --startup-project apps\api\K12QuestionGraph.Api.csproj
```

不得使用 `git reset --hard`，除非明确确认要丢弃本轮所有改动。

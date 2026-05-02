# 45 · B006 Question Source Review 证据

执行日期：2026-05-03。

## 1. 完成范围

- 新增 API：
  - `GET /questions/{id}/sources`
- 题目来源回看响应包含：
  - `sourceDocumentId`
  - source title
  - page number
  - bbox: `x/y/width/height`
  - coordinate unit
  - screenshot relative path
  - region type
- 若引用的 SourceRegion 截图缺失，API 返回明确错误：
  - HTTP `409`
  - `question_source_screenshot_missing`
- B006 不新增数据库 migration，复用 B003/B005 的 `source_regions`、`question_blocks`、`question_assets`。

## 2. Gate 结果

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
b006 question source review smoke: pass
backup verify: pass
overall: pass
```

Smoke 覆盖：

```text
create file/source document
create SourceRegion with screenshot path
save QuestionItem referencing SourceRegion
GET /questions/{id}/sources returns page number and screenshot path
delete screenshot
GET /questions/{id}/sources returns HTTP 409
```

已知非阻断警告：

```text
Vite chunk-size warning due Ant Design bundle.
```

## 3. 回滚

代码/文档回滚：

```powershell
git restore --source=HEAD -- apps/api/Program.cs apps/api/README.md tools/run-gates.ps1 tools/README.md tasks/backlog.csv docs/45_B006_QuestionSourceReview.md
```

B006 不新增数据库 migration。

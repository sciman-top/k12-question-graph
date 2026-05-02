# 39 · B001 SourceDocument 与 Hash 去重证据

执行日期：2026-05-03。

## 1. 完成范围

- `POST /files` 与 `POST /imports` 接收 multipart 来源字段：
  - `sourceType`
  - `sourceTitle`
  - `ownerScope`
  - `licenseOrPermission`
  - `sharingAllowed`
  - `containsStudentPii`
  - `anonymizationStatus`
- 新增 `source_documents` 表，记录来源、授权、传播限制、学生 PII 和脱敏状态。
- `file_assets(sha256, size_bytes)` 增加唯一索引。
- 重复上传按 hash/size 复用同一个 `FileAsset`，不复制大文件。
- 未知来源或含未脱敏学生 PII 时，应用层强制 `sharingAllowed=false`、`externalAiAllowed=false`。
- `tools/run-gates.ps1` 新增 `b001 duplicate upload smoke`。

## 2. 数据库变更

Migration:

```text
20260502160722_AddSourceDocumentsForB001
```

新增表：

```text
source_documents
```

关键约束：

```text
fk_source_documents_file_assets_file_asset_id
ck_source_documents_anonymization_status
ix_file_assets_sha256_size_bytes unique
```

## 3. Smoke 证据

重复上传同一内容两次，第二次使用不同文件名：

```json
{
  "firstUpload": {
    "isDuplicate": false,
    "sharingAllowed": true,
    "externalAiAllowed": true
  },
  "secondUpload": {
    "isDuplicate": true,
    "sharingAllowed": false,
    "containsStudentPii": true,
    "anonymizationStatus": "none",
    "externalAiAllowed": false
  },
  "sameFileAssetId": true
}
```

`source_documents` 查询结果包含同一 `file_asset_id` 下两条来源记录：

```text
school_paper | internal_authorized | sharing_allowed=t | contains_student_pii=f | external_ai_allowed=t
unknown      | unknown             | sharing_allowed=f | contains_student_pii=t | external_ai_allowed=f
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
doc schema config csv: pass
database smoke: pass
b001 duplicate upload smoke: pass
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
git restore --source=HEAD -- apps/api tools tasks docs
```

数据库回滚到 P0 初始 migration：

```powershell
$env:KQG_CONNECTION_STRING='Host=127.0.0.1;Port=5432;Database=k12_question_graph;Username=postgres;Password=<local-password>'
dotnet tool run dotnet-ef database update 20260502153148_InitialP0 --project apps\api\K12QuestionGraph.Api.csproj --startup-project apps\api\K12QuestionGraph.Api.csproj
```

不得使用 `git reset --hard`，除非明确确认要丢弃本轮所有改动。

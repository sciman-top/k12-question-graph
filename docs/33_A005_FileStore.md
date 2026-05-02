# 33 · A005 FileStore 与 FileAsset 证据

执行日期：2026-05-02。

## 1. 完成范围

- 新增 `IFileStore` / `LocalFileStore`。
- 新增 `POST /files` 上传入口。
- 文件内容写入 `KqgPaths:FileStoreRoot`。
- 数据库 `file_assets` 只保存 metadata、relative path、hash、size 和 JSONB source metadata。

## 2. 教师效率准入

- 减少教师工作：为后续 Word/PDF/图片导入提供一次上传入口，教师不需要手工维护文件路径。
- 负担控制：P0 不要求教师配置文件仓库，默认使用 `D:\KQG_Data\file_store`。
- 失败接管：上传失败不会创建 `ImportJob`，后续 A006 再接入任务状态。
- 成本/隐私/备份：文件在本机数据目录，数据库不保存大文件；A009 会把 manifest/backup 纳入门禁。
- P0/P1 必需性：A005 是 A006/A007/A009 的前置。

## 3. Smoke

启动 API 时使用临时环境变量：

```powershell
$env:KQG_CONNECTION_STRING='Host=127.0.0.1;Port=5432;Database=k12_question_graph;Username=postgres;Password=<local-password>'
dotnet run --project apps\api\K12QuestionGraph.Api.csproj --urls http://127.0.0.1:5275
```

上传：

```powershell
curl.exe -F "file=@$sample;type=text/plain" http://127.0.0.1:5275/files
```

关键响应：

```json
{
  "relativePath": "original/a2/55/a25501174f2275d408c79b112767713445fdb36de4f630b09fb25b2123c73e2c.txt",
  "storageScope": "original",
  "contentType": "text/plain",
  "sha256": "a25501174f2275d408c79b112767713445fdb36de4f630b09fb25b2123c73e2c",
  "sizeBytes": 19
}
```

文件落盘：

```text
D:\KQG_Data\file_store\original\a2\55\a25501174f2275d408c79b112767713445fdb36de4f630b09fb25b2123c73e2c.txt
```

数据库 metadata：

```text
original_file_name
relative_path
storage_scope
content_type
sha256
size_bytes
```

## 4. 回滚

代码回滚：

```powershell
git restore --source=HEAD -- apps/api/Program.cs apps/api/README.md tasks/backlog.csv docs/31_A000_to_A003_Execution_Log.md
```

删除本地 smoke 文件：

```powershell
Remove-Item -LiteralPath 'D:\KQG_Data\file_store\original\a2\55\a25501174f2275d408c79b112767713445fdb36de4f630b09fb25b2123c73e2c.txt' -Force
```

删除 smoke metadata：

```powershell
$env:PGPASSWORD='<local-password>'
& 'C:\Program Files\PostgreSQL\17\bin\psql.exe' -h 127.0.0.1 -U postgres -d k12_question_graph -c "delete from file_assets where sha256='a25501174f2275d408c79b112767713445fdb36de4f630b09fb25b2123c73e2c';"
```

## 5. 剩余注意事项

- A005 只完成上传和 FileAsset metadata；ImportJob 创建、状态机和 retry/idempotency 在 A006。
- 当前上传入口未做文件大小上限、来源授权表单和 PII 标记；B001 会补来源 metadata，A010 前应补 smoke test。

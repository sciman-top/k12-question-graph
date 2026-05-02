# 35 · A007 Python Worker 调用协议证据

执行日期：2026-05-02。

## 1. 完成范围

- 新增 `workers/document/worker.py` 占位 worker。
- 新增 `PythonWorker` 配置段。
- 新增 `IDocumentWorkerClient` / `DocumentWorkerClient`。
- 新增 `POST /imports/{id}/worker-smoke` API。

## 2. 协议

API 调用 worker 时传入：

```text
--job-id <guid>
--relative-path <file_store_relative_path>
--file-root <configured_file_store_root>
```

worker 成功输出 JSON：

```json
{"status":"ok","jobId":"...","relativePath":"...","sizeBytes":54}
```

失败通过非零 exit code 和 stderr 返回诊断。

## 3. Smoke

成功路径：

```text
job: 87709950-f8cb-4f92-964e-9120b98686ae
worker exitCode: 0
ImportJob status: succeeded
```

失败路径：

```text
job: c35aea01-4b2e-4794-941c-29283565993a
worker exitCode: 2
stderr: simulated worker failure
ImportJob status: failed
last_error_code: worker_failed
file_asset_exists: true
```

直接 worker smoke：

```powershell
python workers\document\worker.py --job-id smoke --relative-path original/75/2d/752d9c0dce1cc7e9f1ad09f13d6cac1160838f30c9073412428b56cfe818b620.txt --file-root D:\KQG_Data\file_store
python workers\document\worker.py --job-id smoke --relative-path original/75/2d/752d9c0dce1cc7e9f1ad09f13d6cac1160838f30c9073412428b56cfe818b620.txt --file-root D:\KQG_Data\file_store --simulate-failure
```

## 4. 教师效率准入

- 减少教师工作：导入任务失败后会留下可解释的 job 诊断，不让教师重新猜文件是否丢失。
- 负担控制：P0 不暴露 Python/OCR/AI 参数给普通教师。
- 失败接管：worker 失败时 `FileAsset` 和 `ImportJob` 均保留，A008 后可在健康检查/诊断中暴露。
- 成本/隐私/备份：worker 只读取本地文件仓库，不外发数据。
- P0/P1 必需性：A007 是后续 Docling/OCR Adapter 和 ImportJob 执行循环的协议地基。

## 5. 回滚

代码回滚：

```powershell
git restore --source=HEAD -- apps/api/Program.cs apps/api/appsettings.json apps/api/README.md tasks/backlog.csv docs/31_A000_to_A003_Execution_Log.md
```

清理 smoke 数据：

```powershell
$env:PGPASSWORD='<local-password>'
& 'C:\Program Files\PostgreSQL\17\bin\psql.exe' -h 127.0.0.1 -U postgres -d k12_question_graph -c "delete from import_jobs where id in ('87709950-f8cb-4f92-964e-9120b98686ae','c35aea01-4b2e-4794-941c-29283565993a');"
```

## 6. 剩余注意事项

- 当前 worker 只做协议 smoke，不做 OCR、版面解析或 AI。

# 31 · A000-A003 连续执行记录

执行日期：2026-05-02。

## 1. 完成范围

本轮按 `tasks/backlog.csv` 顺序完成：

| 任务 | 状态 | 证据 |
|---|---|---|
| A000 P0 准入预检 | 已完成 | `docs/29_A000_Preflight.md`, `global.json` |
| A000A P0 编码前契约收口 | 已完成 | `docs/30_A000A_Contract_Closure.md` |
| A001 创建 monorepo 目录结构 | 已完成 | `apps/api`, `apps/web`, `workers/document`, `tools`, `tests` |
| A002 创建 ASP.NET Core API 项目 | 已完成 | `apps/api/K12QuestionGraph.Api.csproj`, `/health` |
| A003 创建 React + Vite + Ant Design 前端 | 已完成 | `apps/web/package.json`, teacher workspace UI |
| A004 配置 PostgreSQL 与 EF Core migrations | 已完成 | `apps/api/Data/Migrations`, `k12_question_graph` migration smoke |
| A005 实现 FileStore 与 FileAsset 模型 | 已完成 | `POST /files`, `D:\KQG_Data\file_store`, `file_assets` query |
| A006 实现 ImportJob 状态机 | 已完成 | `POST /imports`, `GET /imports/{id}`, `POST /imports/{id}/status` |
| A007 建立 Python Worker 调用协议 | 已完成 | `workers/document/worker.py`, `POST /imports/{id}/worker-smoke` |
| A008 建立日志配置健康检查 | 已完成 | `/health/ready`, bad FileStore config returns HTTP 503 |
| A009 建立基础备份脚本与 manifest | 已完成 | `tools/backup.ps1`, `tools/verify-backup.ps1` |
| A010 建立测试框架与统一 gate | 已完成 | `tools/run-gates.ps1` |

## 2. 验证结果

| 命令 | 结果 |
|---|---|
| `dotnet build apps\api\K12QuestionGraph.Api.csproj` | pass: 0 warnings, 0 errors |
| `Invoke-RestMethod http://127.0.0.1:5275/health` | pass: `status=ok`, `programDataSeparated=true` |
| `npm run build` in `apps/web` | pass; Vite reports one chunk-size warning due Ant Design bundle |
| `npm run lint` in `apps/web` | pass |
| Vite dev smoke on `http://127.0.0.1:5173/` | pass: HTTP 200, root element and module entry present |
| CSV/JSON/YAML doc gates | pass: `doc gates ok 37` |
| `winget install --id PostgreSQL.PostgreSQL.17 --silent --accept-package-agreements --accept-source-agreements --disable-interactivity` | pass: PostgreSQL 17.9 installed |
| `psql -h 127.0.0.1 -U postgres -d postgres -c 'select version();'` | pass: PostgreSQL 17.9 |
| `dotnet tool run dotnet-ef migrations add InitialP0 ...` | pass: migration generated |
| `dotnet tool run dotnet-ef database update ...` | pass: `Applying migration '20260502153148_InitialP0'` |
| `Invoke-RestMethod http://127.0.0.1:5275/health/db` | pass: `status=ok`, `canConnect=true` |
| `curl.exe -F file=@... http://127.0.0.1:5275/files` | pass: uploaded sample with sha256 path |
| `select ... from file_assets where sha256=...` | pass: DB stores metadata/path/hash only |
| `POST /imports` + `POST /imports/{id}/status` | pass: `queued -> running -> succeeded` |
| invalid transition `succeeded -> running` | pass: HTTP 409 |
| retry smoke | pass: `queued -> running -> failed -> queued -> running -> retry_waiting`, `attemptCount=2` |
| document worker success smoke | pass: worker exit 0, ImportJob `succeeded` |
| document worker failure smoke | pass: worker exit 2, ImportJob `failed`, FileAsset still exists |
| `Invoke-RestMethod /health/ready` | pass: API, database, file_store, logs, worker script all ok |
| bad `KqgPaths__FileStoreRoot=Z:\...` | pass: HTTP 503, file_store check false |
| `.\tools\backup.ps1` | pass: manifest at `D:\KQG_Backups\20260502-234648\manifest.json`, fileCount=9, configCount=3 |
| `.\tools\verify-backup.ps1 -ManifestPath ...` | pass: `status=ok` |
| verify missing manifest | pass: failed as expected, no false success |
| `.\tools\run-gates.ps1` | pass: backend build, frontend build/lint, worker smoke, doc gates, database smoke, backup verify |

## 3. A004 结果

`A004 配置 PostgreSQL 与 EF Core migrations` 已解除阻断并完成。关键事实：

- PostgreSQL 17.9 已通过官方 winget 包安装。
- Windows service `postgresql-x64-17` 正在运行，监听 `5432`。
- 数据库 `k12_question_graph` 已创建。
- 初始 migration 包含 `teacher_preferences`, `file_assets`, `import_jobs`, `ai_jobs`, `review_queue_items`, `backup_jobs`, `question_items`。
- 初始 migration 包含 job/review/backup/question status check constraints。

本轮验证使用临时环境变量 `KQG_CONNECTION_STRING` 注入本机连接串；仓库配置不提交固定密码。

## 4. A005 结果

`A005 实现 FileStore 与 FileAsset 模型` 已完成。关键事实：

- `POST /files` 接收 multipart file。
- `LocalFileStore` 按 SHA-256 分片写入 `KqgPaths:FileStoreRoot`。
- 数据库 `file_assets` 保存 metadata、relative path、hash、size，不保存文件内容。
- 重复内容复用已存在文件路径，不重复写大文件。

Smoke 证据：

```text
relativePath: original/a2/55/a25501174f2275d408c79b112767713445fdb36de4f630b09fb25b2123c73e2c.txt
file exists: D:\KQG_Data\file_store\original\a2\55\a25501174f2275d408c79b112767713445fdb36de4f630b09fb25b2123c73e2c.txt
file_assets row: original_file_name, relative_path, storage_scope, content_type, sha256, size_bytes
```

## 5. A006 结果

`A006 实现 ImportJob 状态机` 已完成。关键事实：

- `POST /imports` 上传文件并创建 `ImportJob`，初始状态为 `queued`。
- `GET /imports/{id}` 可追踪 job 状态、attempt、lock、错误和时间戳。
- `POST /imports/{id}/status` 只允许受控状态迁移。
- 非法状态迁移返回 HTTP 409。
- 外部传入 `DateTimeOffset` 会在 API 边界转为 UTC，避免 PostgreSQL `timestamptz` 写入失败。

Smoke 证据：

```text
queued -> running -> succeeded: pass
succeeded -> running: HTTP 409
queued -> running -> failed -> queued -> running -> retry_waiting: pass
attemptCount after retry: 2
```

## 6. A007 结果

`A007 建立 Python Worker 调用协议` 已完成。关键事实：

- `workers/document/worker.py` 接收 `job_id` 和 `relative_path`，输出结构化 JSON。
- API 通过 `IDocumentWorkerClient` 以非 shell 方式调用 Python worker。
- `POST /imports/{id}/worker-smoke` 会把 job 置为 `running`，按 worker exit code 写回 `succeeded` 或 `failed`。
- 失败路径保留 `ImportJob` 和 `FileAsset`，并写入 `last_error_code=worker_failed`。
- worker 超时会杀进程树并返回失败诊断。

Smoke 证据：

```text
success job: 87709950-f8cb-4f92-964e-9120b98686ae, status=succeeded, exitCode=0
failure job: c35aea01-4b2e-4794-941c-29283565993a, status=failed, exitCode=2
failure persistence: file_asset_exists=true
```

## 7. A008 结果

`A008 建立日志配置健康检查` 已完成。关键事实：

- `/health/ready` 覆盖 API process、PostgreSQL、FileStore 可写、logs 可写、document worker script 存在。
- 正常配置返回 HTTP 200 和 `status=ok`。
- 错误 FileStore 目录返回 HTTP 503 和 `status=unhealthy`。

Smoke 证据：

```text
/health/ready: status=ok
checks: api=true, database=true, file_store=true, logs=true, document_worker_script=true
bad KqgPaths__FileStoreRoot=Z:\KQG_NoDrive\file_store: HTTP 503, file_store=false
```

## 8. A009 结果

`A009 建立基础备份脚本与 manifest` 已完成。关键事实：

- `tools/backup.ps1` 生成 PostgreSQL custom dump、FileStore 文件清单和配置 sha256。
- `tools/verify-backup.ps1` 校验 database dump、FileStore 文件和配置 hash。
- 校验失败会抛错并返回非 0，不报告成功。

Smoke 证据：

```text
backupDir: D:\KQG_Backups\20260502-234648
manifest: D:\KQG_Backups\20260502-234648\manifest.json
fileCount: 9
configCount: 3
verify: status=ok
missing manifest: failed as expected
```

## 9. A010 结果

`A010 建立测试框架与统一 gate` 已完成。关键事实：

- `tools/run-gates.ps1` 是当前统一 gate 入口。
- 覆盖 backend build、frontend build/lint、worker smoke、doc/schema/config/CSV、database smoke、backup/verify。
- gate 成功返回 JSON summary。

Smoke 证据：

```text
backend build: pass
frontend build: pass, Vite chunk-size warning due Ant Design bundle
frontend lint: pass
worker smoke: pass
doc schema config csv: pass, doc gates ok 37
database smoke: pass, public table count 8
backup verify: pass
overall: pass
```

下一任务是 `A011 建立 P0 证据包与回滚入口`。

## 10. 回滚

代码/文档回滚方式：

```powershell
git diff --name-only
git restore --source=HEAD -- <file>
```

数据库回滚方式：

```powershell
$env:KQG_CONNECTION_STRING='Host=127.0.0.1;Port=5432;Database=k12_question_graph;Username=postgres;Password=<local-password>'
dotnet tool run dotnet-ef database update 0 --project apps/api/K12QuestionGraph.Api.csproj --startup-project apps/api/K12QuestionGraph.Api.csproj
```

主机依赖回滚方式：

```powershell
winget uninstall --id PostgreSQL.PostgreSQL.17
```

不得使用 `git reset --hard`，除非明确确认要丢弃本轮所有改动。

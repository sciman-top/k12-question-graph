# 32 · A004 PostgreSQL 与 EF Core Migration 证据

执行日期：2026-05-02。

## 1. 落点与归宿

- 当前落点：`A004 配置 PostgreSQL 与 EF Core migrations`。
- 目标归宿：`apps/api` 拥有可迁移的 PostgreSQL P0 核心数据模型。
- 下一最小任务：`A005 实现 FileStore 与 FileAsset 模型`。

## 2. 主机依赖

本机初始状态未发现 `psql/postgres/pg_config` 和 PostgreSQL service。已通过官方 winget 包安装 PostgreSQL 17：

```powershell
winget install --id PostgreSQL.PostgreSQL.17 --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
```

安装后事实：

```text
Package: PostgreSQL.PostgreSQL.17
Version: 17.9-3
Install root: C:\Program Files\PostgreSQL\17
Service: postgresql-x64-17
Port: 5432
psql: 17.9
```

## 3. 仓库变更

- 新增 EF Core/Npgsql 依赖。
- 新增本地 `dotnet-ef` tool manifest。
- 新增 `KqgDbContext` 和设计时 factory。
- 新增 P0 核心实体：`TeacherPreference`, `FileAsset`, `ImportJob`, `AIJob`, `ReviewQueueItem`, `BackupJob`, `QuestionItem`。
- 新增 `/health/db` 数据库连通性健康检查。
- 新增 migration `InitialP0`。

## 4. Migration Smoke

本轮用临时环境变量注入连接串：

```powershell
$env:KQG_CONNECTION_STRING='Host=127.0.0.1;Port=5432;Database=k12_question_graph;Username=postgres;Password=<local-password>'
```

执行：

```powershell
dotnet tool run dotnet-ef migrations add InitialP0 --project apps\api\K12QuestionGraph.Api.csproj --startup-project apps\api\K12QuestionGraph.Api.csproj --output-dir Data\Migrations
dotnet tool run dotnet-ef database update --project apps\api\K12QuestionGraph.Api.csproj --startup-project apps\api\K12QuestionGraph.Api.csproj
```

关键输出：

```text
Build succeeded.
Applying migration '20260502153148_InitialP0'.
Done.
```

数据库表 smoke：

```text
__EFMigrationsHistory
ai_jobs
backup_jobs
file_assets
import_jobs
question_items
review_queue_items
teacher_preferences
```

状态约束 smoke：

```text
ck_ai_jobs_status
ck_backup_jobs_status
ck_import_jobs_status
ck_question_items_status
ck_review_queue_items_status
```

健康检查：

```json
{"status":"ok","provider":"PostgreSQL","canConnect":true}
```

## 5. 回滚

撤销数据库 migration：

```powershell
$env:KQG_CONNECTION_STRING='Host=127.0.0.1;Port=5432;Database=k12_question_graph;Username=postgres;Password=<local-password>'
dotnet tool run dotnet-ef database update 0 --project apps\api\K12QuestionGraph.Api.csproj --startup-project apps\api\K12QuestionGraph.Api.csproj
```

删除本地数据库：

```powershell
$env:PGPASSWORD='<local-password>'
& 'C:\Program Files\PostgreSQL\17\bin\dropdb.exe' -h 127.0.0.1 -U postgres k12_question_graph
```

卸载 PostgreSQL：

```powershell
winget uninstall --id PostgreSQL.PostgreSQL.17
```

## 6. 剩余注意事项

- 本机开发密码只通过环境变量传入，不提交到仓库。
- `dotnet --info` 在本机仍会触发 workload info 的宿主异常；`dotnet build` 和 `dotnet-ef` 当前可用。后续做 full gate 时应单独记录该宿主问题。
- A005 开始后，`FileAsset` 表已存在，但文件落盘、hash 去重、目录创建和大文件不入库规则仍未实现。

# 34 · A006 ImportJob 状态机证据

执行日期：2026-05-02。

## 1. 完成范围

- `POST /imports`：上传文件并创建 `ImportJob`。
- `GET /imports/{id}`：查询 job 状态。
- `POST /imports/{id}/status`：受控状态迁移。
- `ImportJobTransitions`：集中定义合法迁移。

## 2. 状态契约

当前允许迁移：

```text
queued -> running | cancelled
running -> succeeded | failed | cancelled | retry_waiting
retry_waiting -> queued | cancelled
failed -> queued
succeeded -> terminal
cancelled -> terminal
```

状态字段仍由 PostgreSQL check constraint 兜底：

```text
queued
running
succeeded
failed
cancelled
retry_waiting
```

## 3. Smoke

创建并完成：

```text
POST /imports: queued
POST /imports/{id}/status running: running
POST /imports/{id}/status succeeded: succeeded
```

非法迁移：

```text
succeeded -> running: HTTP 409
```

重试路径：

```text
queued -> running -> failed -> queued -> running -> retry_waiting
attemptCount: 2
```

数据库查询：

```text
id: 2e445c9d-91ca-46ea-a2ec-9b2522df2d1b
finalStatus: retry_waiting
attemptCount: 2
```

## 4. 教师效率准入

- 减少教师工作：上传后系统有明确 job 状态，不让教师猜导入是否卡住。
- 负担控制：P0 不暴露 worker/model/provider 配置给普通教师。
- 失败接管：`failed` 和 `retry_waiting` 保存错误字段，A007/A008 后可展示诊断并允许重试。
- 成本/隐私/备份：job fact 在 PostgreSQL，后续备份可包含任务审计。
- P0/P1 必需性：A006 是 A007 worker protocol 和 A008 health 的前置。

## 5. 回滚

代码回滚：

```powershell
git restore --source=HEAD -- apps/api/Program.cs apps/api/README.md tasks/backlog.csv docs/31_A000_to_A003_Execution_Log.md
```

清理 smoke 数据：

```powershell
$env:PGPASSWORD='<local-password>'
& 'C:\Program Files\PostgreSQL\17\bin\psql.exe' -h 127.0.0.1 -U postgres -d k12_question_graph -c "delete from import_jobs where id in ('558de64b-0fb3-421c-8aed-e1197cc78e99','2e445c9d-91ca-46ea-a2ec-9b2522df2d1b');"
```

## 6. 剩余注意事项

- 当前状态迁移由 API smoke 验证；A010 建立测试框架后应转为自动化 integration test。
- A006 尚未调用 Python Worker；A007 只建立调用协议和占位，不接真实 OCR/AI。

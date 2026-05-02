# 38 · A010 统一 Gate 证据

执行日期：2026-05-02。

## 1. 完成范围

- 新增 `tools/run-gates.ps1`。
- 后端：`dotnet build apps\api\K12QuestionGraph.Api.csproj`。
- 前端：`npm run build` 与 `npm run lint`。
- Worker：`python workers\document\worker.py` smoke。
- Contract：CSV/JSON/YAML 解析。
- Database：PostgreSQL table smoke。
- Backup：`tools/backup.ps1` + `tools/verify-backup.ps1`。

## 2. Gate Smoke

```powershell
$env:PGPASSWORD='postgres'
.\tools\run-gates.ps1
```

关键输出：

```json
{
  "status": "pass",
  "steps": [
    {"name": "backend build", "status": "pass"},
    {"name": "frontend build", "status": "pass"},
    {"name": "frontend lint", "status": "pass"},
    {"name": "worker smoke", "status": "pass"},
    {"name": "doc schema config csv", "status": "pass"},
    {"name": "database smoke", "status": "pass"},
    {"name": "backup verify", "status": "pass"}
  ]
}
```

## 3. Gate N/A

当前没有 remaining hard-gate N/A；但仍是 smoke-level gate，不等价于完整产品测试：

- 尚未建立 xUnit/Playwright/pytest 测试项目。
- 上传/import/health/backup 的 API smoke 已手工验证，A010 后应逐步转自动测试。
- Vite build 有 Ant Design bundle chunk-size warning，不阻断 P0。

## 4. 回滚

```powershell
git restore --source=HEAD -- tools/run-gates.ps1 tools/README.md tasks/backlog.csv docs/31_A000_to_A003_Execution_Log.md
```

# 36 · A008 日志配置与健康检查证据

执行日期：2026-05-02。

## 1. 完成范围

- 新增 `/health/ready`。
- 覆盖 API、database、file_store、logs、document_worker_script。
- FileStore/logs 使用真实目录创建和临时写入探测。
- 失败返回 HTTP 503。

## 2. 正常配置 Smoke

```powershell
Invoke-RestMethod http://127.0.0.1:5275/health/ready
```

关键输出：

```json
{
  "status": "ok",
  "checks": [
    {"name": "api", "ok": true},
    {"name": "database", "ok": true},
    {"name": "file_store", "ok": true},
    {"name": "logs", "ok": true},
    {"name": "document_worker_script", "ok": true}
  ]
}
```

## 3. Bad Config Smoke

```powershell
$env:KqgPaths__FileStoreRoot='Z:\KQG_NoDrive\file_store'
Invoke-WebRequest http://127.0.0.1:5275/health/ready -SkipHttpErrorCheck
```

关键输出：

```text
status_code=503
file_store ok=false
detail=Could not find a part of the path 'Z:\KQG_NoDrive\file_store'.
```

## 4. 回滚

```powershell
git restore --source=HEAD -- apps/api/Program.cs apps/api/README.md tasks/backlog.csv docs/31_A000_to_A003_Execution_Log.md
```

## 5. 剩余注意事项

- A008 仍是 smoke-level health；A010 应把 readiness 和 bad-config case 纳入统一 gate。
- 后续 Windows Service 发布时还需要补磁盘空间、权限用户和 content root 检查。

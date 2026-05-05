# O001 Windows Service 发布包合同证据（2026-05-05）

- 规则 ID: `O001`
- 风险等级: 中
- 当前落点: `Windows Service 发布包`
- 目标归宿: 发布后 API/Worker/Web 配置不依赖仓库当前目录，支持后续 `O002/O007`

## 执行命令

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-o001-windows-service-publish-contract.ps1
```

## 关键输出摘要

- `status=pass`
- 产物目录: `tmp/o001/windows-service-package`
- API 发布目录: `tmp/o001/windows-service-package/api`
- Web 发布目录: `tmp/o001/windows-service-package/web`
- Worker 脚本打包路径: `tmp/o001/windows-service-package/api/worker/document/worker.py`
- 启动 smoke 使用临时工作目录（非仓库目录）并通过 `--contentRoot`:
  - `runWorkingDirectory=C:\Users\sciman\AppData\Local\Temp\kqg-o001-run-...`
  - `contentRoot=D:\CODE\k12-question-graph\tmp\o001\windows-service-package\api`
  - `document_worker_script.ok=true`
- 配置检查：
  - `PythonWorker.DocumentWorkerScript=worker\\document\\worker.py`
  - `KqgPaths.DataRoot/FileStoreRoot/BackupRoot/LogsRoot` 均为绝对路径

## 兼容性判断

- 本地开发兼容：`appsettings.Development.json` 覆盖 `DocumentWorkerScript=..\\..\\workers\\document\\worker.py`，不影响仓库内 `dotnet run`。
- 发布兼容：发布包内使用 `worker\\document\\worker.py`，与打包路径一致。

## 回滚动作

- 删除发布验证产物：

```powershell
Remove-Item -LiteralPath 'D:\CODE\k12-question-graph\tmp\o001\windows-service-package' -Recurse -Force
```

## 证据文件

- `tmp/o001/windows-service-package/published-api.out.log`
- `tmp/o001/windows-service-package/published-api.err.log`

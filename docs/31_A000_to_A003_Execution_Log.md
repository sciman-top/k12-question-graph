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

## 2. 验证结果

| 命令 | 结果 |
|---|---|
| `dotnet build apps\api\K12QuestionGraph.Api.csproj` | pass: 0 warnings, 0 errors |
| `Invoke-RestMethod http://127.0.0.1:5275/health` | pass: `status=ok`, `programDataSeparated=true` |
| `npm run build` in `apps/web` | pass; Vite reports one chunk-size warning due Ant Design bundle |
| `npm run lint` in `apps/web` | pass |
| Vite dev smoke on `http://127.0.0.1:5173/` | pass: HTTP 200, root element and module entry present |
| CSV/JSON/YAML doc gates | pass: `doc gates ok 37` |

## 3. A004 阻断

下一任务是 `A004 配置 PostgreSQL 与 EF Core migrations`。当前阻断原因：

- 本机未发现 `psql`、`postgres`、`pg_config`。
- 本机未发现 PostgreSQL Windows service。
- `D:\KQG_Data\` 与 `D:\KQG_Backups\` 尚未创建。

继续 A004 前必须先完成：

```text
PostgreSQL server installed or located
psql available or absolute path documented
server version query succeeds
pg_dump available for later A009
target data and backup directory policy confirmed
```

## 4. 回滚

当前变更均在 Git 工作区中。回滚方式：

```powershell
git diff --name-only
git restore --source=HEAD -- <file>
```

不得使用 `git reset --hard`，除非明确确认要丢弃本轮所有改动。

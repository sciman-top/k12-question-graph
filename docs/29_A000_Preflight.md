# 29 · A000 P0 准入预检记录

执行日期：2026-05-02。

## 1. 结论

`A000` 已完成“记录与锁定”层面的准入预检。本机具备 .NET 10 SDK、Node.js、npm 和 Python；PostgreSQL 当前未在 PATH 或 Windows service 中发现；`dotnet --info` 能打印 SDK/runtime 信息但退出码为 1，需作为 host readiness 风险跟踪。

AI 推荐：继续推进 `A000A` 与 `A001-A003`，但在 `A004` 配置 PostgreSQL/EF migrations 前，必须先安装或定位 PostgreSQL，并复测 `psql`/server version、扩展可用性与备份命令。理由：P0 目录、API/Web/Worker 骨架不依赖数据库已运行；数据库 migration 和 backup smoke 依赖真实 PostgreSQL。

## 2. 版本与命令证据

| 项 | 命令 | 结果 | 判定 |
|---|---|---|---|
| .NET SDK pinned | `dotnet --version` | `10.0.202` | pass |
| .NET SDK list | `dotnet --list-sdks` | `8.0.420`, `10.0.202` | pass |
| .NET runtime list | `dotnet --list-runtimes` | `Microsoft.AspNetCore.App 10.0.6`, `Microsoft.NETCore.App 10.0.6`, `Microsoft.WindowsDesktop.App 10.0.6` 等 | pass |
| .NET full info | `dotnet --info` | 打印 .NET 10 信息后 `System.TypeInitializationException`，退出码 1 | host_risk |
| Node.js | `node --version` | `v24.12.0` | pass |
| npm | `npm --version` | `11.7.0` | pass |
| Python | `python --version` | `Python 3.13.7` | pass |
| PostgreSQL CLI | `Get-Command psql,postgres,pg_config` | 未发现命令 | platform_na |
| PostgreSQL service | `Get-Service -Name '*postgres*','*pgsql*'` | 未发现服务 | platform_na |
| PostgreSQL install dir | `Get-ChildItem 'C:\Program Files','C:\Program Files (x86)' -Filter PostgreSQL` | 未发现目录 | platform_na |

## 3. 版本锁定

新增 `global.json`，将 .NET SDK 锁定到 `10.0.202`，允许同 feature band 内 roll-forward：

```json
{
  "sdk": {
    "version": "10.0.202",
    "rollForward": "latestFeature"
  }
}
```

Node/npm/Python 暂仅记录当前主机版本；进入 `A003/A007` 时再分别由前端 `package.json`、worker runtime 文件和 gate 固化项目级版本策略。

## 4. 数据目录与 Windows Service 约束

当前目标目录仍按架构文档锁定：

| 用途 | 目标 |
|---|---|
| 程序目录 | `C:\Program Files\K12QuestionGraph\` |
| 数据目录 | `D:\KQG_Data\` |
| 备份目录 | `D:\KQG_Backups\` |
| 日志目录 | `D:\KQG_Data\logs\` |
| FileStore | `D:\KQG_Data\file_store\` |

实测：`D:\KQG_Data\` 与 `D:\KQG_Backups\` 当前不存在。A000 不创建本机数据目录；A008/A009 必须通过配置和健康检查创建或验证目录，且 Windows Service 不得依赖当前工作目录。

## 5. BackgroundService Job 约束

P0 job table 必须继续使用以下命名，不得在实现中改名：

```text
locked_by
locked_until
attempt_count
max_attempts
idempotency_key
last_error_code
last_error_message
```

事实来源：

- `docs/03_Architecture.md`
- `docs/24_DatabasePhysicalModel_Draft.md`
- `docs/decisions/ADR-004-verified-p0-stack-and-gate-contract.md`

## 6. 文档门禁

| 门禁 | 命令 | 结果 |
|---|---|---|
| CSV | `python -c "import csv; rows=list(csv.DictReader(open('tasks/backlog.csv', encoding='utf-8-sig'))); print('csv ok', len(rows))"` | `csv ok 37` |
| JSON schema | `python -c "import json, pathlib; files=list(pathlib.Path('schemas').rglob('*.json')); [json.loads(p.read_text(encoding='utf-8')) for p in files]; print('json ok', len(files))"` | `json ok 6` |
| YAML config | `python -c "import pathlib, yaml; files=list(pathlib.Path('configs').rglob('*.yaml')); [yaml.safe_load(p.read_text(encoding='utf-8')) for p in files]; print('yaml ok', len(files))"` | `yaml ok 6` |
| P0/P1 consistency | `rg -n "GlobalUser/.*v9.49|A000|A000A|P0|P1" AGENTS.md CLAUDE.md GEMINI.md README.md docs\19_Roadmap.md docs\20_TaskBreakdown.md tasks\backlog.csv` | pass |

## 7. gate_na / platform_na

| 项 | reason | alternative_verification | evidence_link | expires_at |
|---|---|---|---|---|
| PostgreSQL version query | 本机未发现 `psql`、`postgres`、`pg_config` 或 PostgreSQL service | PATH/服务/安装目录检查 | 本文件第 2 节 | A004 前 |
| build gate | 尚无 `apps/api`、`apps/web`、`workers/document` | 文档、schema、config、CSV parser | 本文件第 6 节 | A001/A002/A003/A007 创建后 |
| test gate | 尚无测试框架 | 文档门禁与一致性检索 | 本文件第 6 节 | A010 前 |
| hotspot gate | 尚无上传、ImportJob、FileStore、backup manifest 实现 | P0/P1 任务编号和范围一致性检查 | 本文件第 6 节 | A009/A010 完成前 |

## 8. 后续阻断条件

- `A004` 前必须安装或定位 PostgreSQL，并能执行 server version query。
- `A009` 前必须确认 `pg_dump`、备份目录可写和 manifest/hash 校验策略。
- 若 `dotnet --info` 异常持续存在，`A002` 可先使用 `dotnet --version`、`dotnet --list-sdks`、`dotnet --list-runtimes` 作为替代证据，但首次 `dotnet build` 失败时必须先排查宿主 .NET 安装链路。

# 2026-05-05 Local Web Persistence Evidence

## Goal

Persist the local Web dev entry for `http://127.0.0.1:5173/` so the site is not dependent on an interactive shell staying open.

## Change

- Added `tools/start-local-web.ps1`.
- Updated `README.md` and `apps/web/README.md` to use the repo-level helper.

## Commands

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/start-local-web.ps1
npm --prefix apps/web run build
dotnet build apps/api/K12QuestionGraph.Api.csproj
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/start-local-web.ps1 -Status
Invoke-WebRequest -UseBasicParsing -Uri http://127.0.0.1:5173/ -TimeoutSec 5
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1
```

## Evidence

- `tools/start-local-web.ps1 -Status` returned `status=running`, `ready=true`, `listenerProcess=node`, and `url=http://127.0.0.1:5173/`.
- `Get-NetTCPConnection -LocalPort 5173 -State Listen` showed `LocalAddress=127.0.0.1`, `LocalPort=5173`, and `OwningProcess=31296`.
- `Invoke-WebRequest http://127.0.0.1:5173/` returned `HTTP=200`.
- Vite log `logs/dev-web/vite.out.log` showed `Local: http://127.0.0.1:5173/`.
- Playwright loaded `http://127.0.0.1:5173/` with page title `web` and visible heading `校本题谱`.
- `npm --prefix apps/web run build` passed.
- `dotnet build apps/api/K12QuestionGraph.Api.csproj` passed with `0 warnings` and `0 errors`.
- `tools/run-roadmap-guard.ps1` returned `status=pass`.

## Known Boundary

- The Web shell is reachable, but `/health/ready` currently returns Vite proxy `502` because API `http://127.0.0.1:5275` is not running.
- Current process environment has no `KQG_CONNECTION_STRING`, no `PGPASSWORD`, and no `psql`, so full API/DB persistence was not claimed in this slice.
- Browser Use IAB backend was unavailable in this session; Playwright MCP was used as alternative browser verification.

## Rollback

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/start-local-web.ps1 -Stop
git restore -- tools/start-local-web.ps1 README.md apps/web/README.md docs/evidence/20260505-local-web-persistence.md
```

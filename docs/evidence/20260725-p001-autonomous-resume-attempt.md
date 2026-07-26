# P001 autonomous resume attempt

日期：2026-07-25

## Goal

- 根据当前机器可读计划，从 `P001A` 恢复连续推进。
- 先刷新 repo-side readiness，再生成最新 `NS1001` 隔离机执行包。
- 不在开发机伪造隔离机安装、打印、学校网络、权限域或操作者签收事实。

## Commands and evidence

1. `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-p001-live-pilot-readiness-preflight-contract.ps1`
   - exit code: `0`
   - result: `status=pass`
   - result: `readyForIsolatedMachineRun=true`
   - result: `p001CanClose=false`
   - next open: `P001A`
   - report: `docs/evidence/20260725-p001-live-pilot-readiness-preflight-report.json`
2. `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-ns1001-isolated-machine-execution-pack.ps1 -PackRoot tmp/ns1001-execution-pack-20260725`
   - exit code: `1`
   - fail-closed reason: latest `NS805` evidence referenced missing temporary backup manifest `tmp/ns801-backups/20260625-002728/manifest.json`
   - no complete manifest was produced for this attempted pack.
3. PostgreSQL availability diagnostics:
   - `pg_isready`: `127.0.0.1:5432 - no response`
   - Windows service: `postgresql-x64-17`, original and final state `Stopped`, start type `Manual`
   - `Start-Service`: blocked because the current host session cannot open the service.
   - direct `pg_ctl` start with repository defaults: PostgreSQL stopped after TCP socket bind returned `Permission denied` for `::` and `0.0.0.0`.
   - direct `pg_ctl` start with command-line `listen_addresses=127.0.0.1`: PostgreSQL again stopped after TCP socket bind returned `Permission denied` for `127.0.0.1`.
4. Existing portable pack verification:
   - pack: `tmp/ns1001-execution-pack/20260608-015422`
   - manifest entries checked: `71`
   - missing or SHA-256 mismatches: `0`
   - return evidence remains unfilled: install, backup/restore, role audit and four teacher-entry statuses are all `not_run`; signoff remains `keep_blocked`.

## Result

- The repo-side prerequisites are ready for an isolated-machine run.
- A fresh execution pack could not be generated in this host session because a fresh backup/restore evidence chain requires PostgreSQL, and PostgreSQL cannot be started under the current service/network permission boundary.
- The existing 2026-06-08 pack is internally intact, but it is anchored to commit `496b656` and older reports. It may be used only as a historical/reference pack, not represented as a fresh 2026-07-25 release package.
- `P001A`, `P001`, `REAL005` and the release decision remain open.

## Continuation resolution

The initial result above records the first fail-closed attempt. Continued diagnostics found that Windows excluded TCP ports `5334-5433`, including PostgreSQL's configured port `5432`. The database cluster and ACL were healthy.

- A temporary PostgreSQL instance was started from the same data directory on `127.0.0.1:55432`; the Windows service configuration and `postgresql.conf` were not changed.
- `tools/run-gates.ps1 -DatabasePort 55432` completed on 2026-07-26 with `RUN_GATES_EXIT=0`; the full log is `docs/evidence/20260725-run-gates-port-55432.log`.
- `NS801`, `NS802`, `NS803`, `NS804`, `NS805`, `NS806`, `NS904`, `NS1308`, P001 readiness, NS1001 execution pack/contract, roadmap guard, live closeout guard and NS905 status sync all passed with refreshed 2026-07-26 evidence.
- `tools/run-g004-pgpass-installer-dry-run.ps1` now explicitly sets and restores `PGPASSFILE`, because changing `APPDATA` alone did not make Windows libpq discover the temporary file.
- `tools/run-host-capability-diagnostic-contract.ps1` now invokes Python with `-X utf8`, preventing GBK stdout failures on non-ASCII diagnostic output.
- Database parameters are now propagated through the Windows Service, installer, recovery, upgrade, offline-emergency and REAL005B nested gate chains instead of silently falling back to port `5432`.
- Fresh pack: `tmp/ns1001-execution-pack/20260726-114733`
- Fresh manifest: `tmp/ns1001-execution-pack/20260726-114733/manifest.json`
- Manifest verification: `79` entries checked, `0` missing files, `0` SHA-256 mismatches.
- The repo-side pack is ready for transfer, but no isolated-machine facts or operator signoff have been returned. `P001A`, `P001`, `REAL005` and the release decision therefore remain open.

## N/A and recovery

- `platform_na`
  - reason: current host session cannot start `postgresql-x64-17`, and direct PostgreSQL startup cannot bind either wildcard or loopback TCP sockets.
  - alternative_verification: refreshed P001 readiness contract and verified all 71 files in the latest existing NS1001 pack against its SHA-256 manifest.
  - evidence_link: `docs/evidence/20260725-p001-autonomous-resume-attempt.md`
  - expires_at: `next_privileged_or_unrestricted_p001_pack_refresh`
  - recovery_condition: PostgreSQL 17 is reachable on `127.0.0.1:5432` in a session allowed to run the backup/restore chain.
  - resolution: the configured `5432` port is inside a Windows excluded range; the repo-side refresh was completed on temporary port `55432` without changing the service configuration.
- `gate_na`
  - reason: initial attempt did not run `tools/run-gates.ps1` because PostgreSQL was unavailable on its configured port and the command can affect repository API processes.
  - alternative_verification: the initial attempt used live closeout guard, roadmap guard and P001 readiness preflight.
  - evidence_link: `docs/evidence/20260725-p001-autonomous-resume-attempt.md`
  - expires_at: `next_executable_change`
  - recovery_condition: PostgreSQL is reachable and the process-impacting full gate is explicitly authorized.
  - resolution: authorization was present; the full gate was rerun against the temporary loopback instance on port `55432` and completed with `RUN_GATES_EXIT=0`.

## Host cleanup status

- The temporary `127.0.0.1:55432` instance is no longer running; `pg_isready` returns `no response`, and the ignored full-gate runner plus exit marker were removed.
- At final cleanup, Windows SCM reported `postgresql-x64-17` as `Running`, start type `Manual`, with PostgreSQL accepting connections on `127.0.0.1:5432`.
- The non-elevated Codex session could not stop the SCM-owned instance:
  - `Stop-Service -Name 'postgresql-x64-17'` failed with `Cannot open 'postgresql-x64-17' service on computer '.'`.
  - `pg_ctl stop -D 'C:\Program Files\PostgreSQL\17\data' -m fast -w` failed with `Operation not permitted`.
- Required administrator closeout:
  - `Stop-Service -Name 'postgresql-x64-17'`
  - verify `Get-Service -Name 'postgresql-x64-17'` reports `Stopped` / `Manual`
  - verify `pg_isready -h 127.0.0.1 -p 5432` reports `no response`
- This host-local privilege boundary does not create isolated-machine, onsite, teacher-observation, operator-signoff or release-decision evidence.

## Rollback

- Repository evidence slice: revert only the 2026-07-25 generated evidence and this status update.
- Ignored failed-pack residue, if no longer needed: remove only `tmp/ns1001-execution-pack-20260725`.
- Repository files do not change the PostgreSQL service configuration; the final observed host state is recorded above and still requires the administrator closeout command.

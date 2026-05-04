# 2026-05-04 phase closeout roadmap rebuild evidence

## Scope

- Rule IDs: R1, R2, R5, R6, R8.
- Risk: low. Planning, documentation, and backlog reconstruction only.
- Current branch: `codex/c002-quality-review-overlay`.
- Current landing point: close old A000-G004 backlog and rebuild the next long-term H001-R006 task line.
- Target home: `docs/87_PhaseCloseoutAndFullRoadmap.md`, `tasks/backlog.csv`, README, roadmap, task breakdown, and Codex handoff prompt.

## Changes

- Added `docs/87_PhaseCloseoutAndFullRoadmap.md`.
- Updated `README.md` to point to the H0 phase closeout and new long-term roadmap.
- Updated `docs/19_Roadmap.md` with the 2026-05-04 phase transition.
- Updated `docs/20_TaskBreakdown.md` with the H-R task-line summary.
- Updated `prompts/CODEX_CLI_HANDOFF.md` so future agents do not follow the stale P0/P1-only instruction.
- Appended H001-R006 to `tasks/backlog.csv`.

## Verification

| Command | Result | Key output |
|---|---|---|
| `python -c "import csv, json, pathlib, yaml; ..."` | pass | `doc gates ok 126 H001 R006` |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-roadmap-guard.ps1` | pass | `status=pass`, `c002Status=已完成`, `draftTestSystemBuildAllowed=true` |
| `git diff --check` | pass | no output |
| `rg -n "当前只允许先实现 P0/P1|P0/P1 不把真实学生" ...` | pass | no matches |

Full `tools/run-gates.ps1` was not run for this planning-only update. The alternative verification is CSV/JSON/YAML parsing plus roadmap guard. Full gate should be refreshed by H002 when the stage closeout begins, with database credentials available.

## Known workspace state

`git status --short --branch` showed the expected modified planning files and the new roadmap evidence file. It also showed an unrelated untracked `.playwright-mcp/` directory; this evidence record does not claim ownership of that directory.

## Rollback

Planning rollback is Git-based:

```powershell
git restore -- README.md docs/19_Roadmap.md docs/20_TaskBreakdown.md prompts/CODEX_CLI_HANDOFF.md tasks/backlog.csv
Remove-Item -LiteralPath docs/87_PhaseCloseoutAndFullRoadmap.md -Force
Remove-Item -LiteralPath docs/evidence/20260504-phase-closeout-roadmap-rebuild.md -Force
```

No database, file store, backup manifest, active switch, or external AI call was changed by this update.

# 20260510 Gate Group Runner

## Goal
- Landing: `D:\CODE\k12-question-graph`
- Target home: `tools/run-gate-group.ps1`
- Intent: add a target-local grouped gate entrypoint so daily or affected work can run narrower deterministic checks without replacing the authoritative `tools/run-gates.ps1` full gate.

## Changes
- Added `tools/run-gate-group.ps1` with groups:
  - `list`
  - `quick`
  - `roadmap`
  - `ui`
  - `pqr`
  - `full`
- `full` delegates to `tools/run-gates.ps1` as the fallback full gate.
- No existing application, API, database, or full-gate script behavior was changed by this slice.

## Verification
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-gate-group.ps1 -Group list`
  - exit_code: `0`
  - key_output: `status=pass`; groups `quick`, `roadmap`, `ui`, `pqr`, `full`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-gate-group.ps1 -Group quick`
  - exit_code: `0`
  - key_output: `status=pass`; `run-c002-dry-run-suite.ps1` pass; `run-roadmap-guard.ps1` pass

## Compatibility
- This is an additive runner. Existing `tools/run-gates.ps1` remains the full gate source of truth.
- Grouped gates are fast feedback only until a future slice proves affected-path routing and coverage equivalence.

## Rollback
- Preferred rollback: restore from git history.
- File-level rollback candidates:
  - `tools/run-gate-group.ps1`
  - `docs/evidence/20260510-gate-group-runner.md`

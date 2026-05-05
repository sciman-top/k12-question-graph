# 2026-05-05 L002 Real AI Extract Pilot

## Goal
- Close `L002` with executable guards while keeping L0 boundary: sample-only, candidate-only, no production write.

## Commands
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-l002-real-ai-extract-pilot.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1`

## Key Output
- L002 guard enforces:
  - sample stays cache-hit and bounded (`sourceDocuments<=4`, `chunksTotal<=32`),
  - output remains `candidate/pending_review/productionEligible=false`,
  - token/cost evidence comes from C002Q report,
  - no overwrite to C002K,
  - human review evidence exists.

## Human Review Evidence
- `docs/evidence/20260505-l002-real-ai-extract-human-review.md`

## Rollback
- Revert:
  - `tools/run-l002-real-ai-extract-pilot.ps1`
  - `tools/run-gates.ps1`
  - `tools/run-roadmap-guard.ps1`
  - `tasks/backlog.csv`
  - `docs/evidence/20260505-l002-real-ai-extract-human-review.md`
  - `docs/evidence/20260505-l002-real-ai-extract-pilot.md`

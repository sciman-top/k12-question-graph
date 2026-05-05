# 2026-05-05 L007 LLM Security Red-Team Gate

## Goal
- Close `L007` with an executable security gate before any real-model pilot in L-phase.

## Commands
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-l007-llm-security-red-team-gate.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1`

## Key Output
- L007 gate now blocks completion if any of these are missing:
  - risk checklist coverage: prompt injection, sensitive information disclosure, insecure output handling, supply chain, vector/embedding weakness, excessive agency.
  - OWASP/NIST alignment document: `docs/98_L007_LlmSecurityRedTeamGate.md`.
  - baseline hard guards from readiness/dry-run evidence:
    - runtime real model calls disabled
    - no active write
    - human review required
    - dry-run external AI calls = 0
    - output remains `pending_review`

## Compatibility
- No runtime API behavior changed.
- This is a preflight governance gate for L0 real-model admission.

## Rollback
- Revert files:
  - `docs/98_L007_LlmSecurityRedTeamGate.md`
  - `tools/run-l007-llm-security-red-team-gate.ps1`
  - `tools/run-gates.ps1`
  - `tools/run-roadmap-guard.ps1`
  - `tasks/backlog.csv`
  - `docs/evidence/20260505-l007-llm-security-red-team-gate.md`

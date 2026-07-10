# 20260711 Agent Rule CI

- repository: `k12-question-graph`
- status: `verified_hosted`
- risk: low; this slice changes only `AGENTS.md`, `.github/workflows/agent-rule-contract.yml`, and this evidence.
- goal: make project-rule changes self-verifying in repository CI without replacing product gates.

## Changes

- `AGENTS.md` now names the deterministic rule-contract workflow and states that it does not replace repository product gates.
- `.github/workflows/agent-rule-contract.yml` validates project contract `2.0`, UTF-8/BOM, size/structure, gate/evidence/rollback tokens, host neutrality, and the exact one-line Claude wrapper.
- workflow permission is `contents: read`; no secret is required. `actions/checkout` is pinned to `34e114876b0b11c390a56381ad16ebd13914f8d5` (`v4`).
- canonical workflow SHA-256: `634eb76978774b8eaad39fe61172c9f65f5558fcd32ce7f13e98ecfae7214190`.

## Verification

- control audit: `python scripts/verify-target-project-rules.py --require-all`; result `selected=9 / failed=0 / unavailable=0 / blocking=[]`.
- the canonical embedded Python gate was executed against valid and invalid temporary repositories; valid `2.0` passed and invalid `1.9` failed.
- GitHub-hosted verification: [Agent Rule Contract](https://github.com/sciman-top/k12-question-graph/actions/runs/29110121650) completed successfully with checkout cleanup included.
- `gate_na`: `reason=rule Markdown/workflow-only change`; `alternative_verification=control contract tests + target hash audit + embedded gate execution`; `evidence_link=this file`; `expires_at=2026-08-09`.

## Rollback

Remove only `.github/workflows/agent-rule-contract.yml`, this evidence, and the single CI-reference line added to `AGENTS.md`. Preserve the 20260710 rule contract and every unrelated worktree change.

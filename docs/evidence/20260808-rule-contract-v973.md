# Global rule 9.73 project-contract evidence

- Repository: `k12-question-graph`
- Scope: project rule mapping only; no business-code or host-runtime mutation.
- Official basis: current Codex AGENTS loading/precedence and rules semantics; Claude platform delta remains separately verified.
- Git profile: baseline=`main`; upstream=`origin/main`.
- Before AGENTS SHA-256: `557E48B139614A79E0267A9E4E75A754A95D29D0A8FE0882F6ABB74865D5BF65`
- After AGENTS SHA-256: `B2943A8A0275810663E2E99B020F060811C3DFF3777CE5231CA24B23AE54484A`
- Planned gate: `pwsh -NoProfile -File tools/run-verification.ps1`
- Current verification: Quick passed inventory, backend/frontend build, lint, script quality and backend/frontend tests; worker stage failed because host Python lacks psycopg, pypdf, fitz, PIL and pdfplumber.
- N/A: reason=`pure rule slice and worker dependencies absent`; alternative_verification=`preceding Quick stages, RuleEstate and fresh prompt load`; expires_at=`2026-10-15`; recovery_condition=`worker environment dependencies are installed or worker code changes`.
- N/A: host loading and live acceptance remain outside repository-static verification.
- Rollback: revert only this repository's `AGENTS.md` and this evidence file to the recorded before hash.
- Truth boundary: `repo_verified=rule_contract_only`; `quick_gate=blocked_at_worker_dependencies`; `host_loaded=codex_fresh_prompt_verified`; `claude_loaded=not_run`; `onsite/live_accepted=not_run`.

# Agent Rule Governance 9.56

- verified_at: `2026-07-15T00:30:00+08:00`
- scope: `AGENTS.md` global review marker and N/A recovery fields; API, Web, Worker, database, FileStore, and domain assets unchanged.
- risk: low for the rule slice; PostgreSQL/API process-impacting full gate was intentionally not run.
- compatibility: project contract remains `2.0`; `CLAUDE.md` remains the one-line `@AGENTS.md` wrapper; `REAL005` remains `not_closed`.

## Ordered gates

| stage | command | exit | key result |
|---|---|---:|---|
| build | `dotnet build apps/api/K12QuestionGraph.Api.csproj` | 0 | build passed; existing `Microsoft.OpenApi 2.0.0` `GHSA-v5pm-xwqc-g5wc` warning retained |
| test/full | `gate_na` for `tools/run-gates.ps1` | N/A | command uses PostgreSQL and may pause/resume the API process; prohibited by this task boundary |
| contract/invariant | `tools/run-roadmap-guard.ps1` | 0 | roadmap guard passed; `REAL005=not_closed` preserved |
| hotspot | `gate_na` | N/A | repository has no independent hotspot command |
| alternatives | `tools/run-c002-dry-run-suite.ps1`; structured JSON/JSONC/CSV/YAML parse | 0 | C002 dry-run passed; 688 JSON, 2 JSONC tsconfig, 40 CSV, and 23 YAML parsed |
| rule contract | control-repo `verify-target-project-rules.py --require-all` | 0 | project rule/wrapper/workflow passed |

`gate_na test/full`: `reason=PostgreSQL and API process impact lacks authorization`; `alternative_verification=build + C002 dry-run + roadmap guard + structured parse + rule audit`; `evidence_link=this file`; `expires_at=next_executable_change`; `recovery_condition=obtain explicit process-impact authorization and run tools/run-gates.ps1`.

`gate_na hotspot`: `reason=no independent repository hotspot command`; `alternative_verification=affected contract review and the alternatives above`; `evidence_link=this file`; `expires_at=next_executable_change`; `recovery_condition=add an independent hotspot command to the ordered gate`.

Rollback is limited to this evidence file and the `AGENTS.md` 9.56/N/A marker slice; no generated REAL005 gate artifacts are retained.

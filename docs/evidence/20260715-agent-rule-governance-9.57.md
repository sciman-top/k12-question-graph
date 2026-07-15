# Agent Rule Governance 9.57

## Scope and boundary

- repository: `k12-question-graph`
- frozen baseline: `d6239a7671bd5d95861cdf57f50d3333cba01dc9`
- task branch: `codex/agent-rule-governance-9.57`
- write-set: `AGENTS.md` and this evidence file; `CLAUDE.md` remains the verified import-only wrapper
- release review: `rule_release=9.57 / project_contract_version=2.0 / coordination_schema=2.3`
- semantic basis: Claude Code's current official memory documentation permits imports up to five hops; the project WHERE/HOW contract itself is unchanged
- exclusions: no product/runtime/schema/data/dependency/auth/provider/secret/MCP/account/process/hosted-UI change

## Verification ledger

- wrapper: `CLAUDE.md` verified as the import-only `@AGENTS.md` wrapper, no BOM; control-repo `--require-all` target audit passed for all 9 isolated targets
- build: `dotnet build apps/api/K12QuestionGraph.Api.csproj` passed with 0 errors; existing `Microsoft.OpenApi 2.0.0` high-severity advisory produced 2 warnings and remains a separate dependency-remediation risk
- test: `gate_na`; reason=`the full gate controls PostgreSQL/API processes and the current task forbids process stop/start`; alternative_verification=`successful build, roadmap guard, static target-rule audit, and diff hygiene`; evidence_link=`docs/18_TestStrategy.md and this record`; expires_at=`next_executable_change`; recovery_condition=`an explicit safe maintenance window or process-owner run is available`
- contract/invariant: `tools/run-roadmap-guard.ps1` passed and preserved `REAL005=not_closed`; its generated timestamp/report artifacts were precisely removed from this governance write-set after validation
- hotspot: `gate_na`; reason=`rule-marker-only slice has no performance path and full gate requires process control`; alternative_verification=`roadmap guard plus five-axis static review`; evidence_link=`this record`; expires_at=`next runtime change`; recovery_condition=`a process-safe hotspot command or authorized maintenance window exists`
- five-axis review: correctness/readability/architecture/security/performance passed with no Critical or Required finding
- Git publication: not yet executed at this capture point

## Compatibility and rollback

- compatibility: content-release review marker only; repository commands, invariants, external behavior, data formats, and wrapper loading shape remain unchanged
- rollback: revert only `AGENTS.md` and this evidence file from the task commit; do not reset, clean, or include unrelated local history

## Completion boundary at capture

- `repo-side completed=true`
- `published branch=false`
- `default-branch effective=false`
- `hosted/manual accepted=false`
- `fully completed=false`

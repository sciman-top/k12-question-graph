# 20260504 Project Rule Governance Integration

## Goal

Map the governed runtime onboarding into K12 Question Graph project rules without copying private rules, scripts, CI, tests, or docs from other target repositories.

## Current Landing -> Target Destination -> Verification

- Current landing point: root project rule files `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md`.
- Target destination: K12-specific rule contract that references the control-repo catalog and `.governed-ai/repo-profile.json` as machine-readable governance profile.
- Verification: rule diff review, lightweight parse/search gates, K12 daily quick gates, and control-repo target governance consistency.

## pre_change_review

- `pre_change_review`: required because this changes project-level rule files and documents gate/profile coordination.
- `control_repo_manifest_and_rule_sources`: K12 is already registered in `D:\CODE\governed-ai-coding-runtime\docs\targets\target-repos-catalog.json`.
- `user_level_deployed_rule_files`: no user-level deployed rule files are changed.
- `target_repo_deployed_rule_files`: edited only root `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md`.
- `target_repo_gate_scripts_and_ci`: rule mapping uses existing `tools/run-gates.ps1`, `tools/run-c002-dry-run-suite.ps1`, and `tools/run-roadmap-guard.ps1`.
- `target_repo_repo_profile`: `.governed-ai/repo-profile.json` provides the machine-readable build/test/quick/contract mapping.
- `target_repo_readme_and_operator_docs`: `README.md` and `tools/README.md` already document full gate and C002 dry-run usage.
- `current_official_tool_loading_docs`: no Codex, Claude, or Gemini loading semantics are changed; the rule files keep their existing tool-specific entry roles.
- `drift-integration decision`: integrate only K12 facts and governed-runtime profile references; do not copy other target repos' private project rules or managed files.

## Changes

- `AGENTS.md`: replaced stale P0-era `gate_na` command section with current full gate, daily quick, governed runtime onboarding, managed asset boundary, rollback, and `Global Rule -> Repo Action` mapping.
- `CLAUDE.md`: updated global source version to v9.50 and clarified that managed `.claude` settings/hooks come from the control-repo governance path.
- `GEMINI.md`: updated global source version to v9.50 and clarified that Gemini still uses `GEMINI.md` plus `@AGENTS.md`, not `.governed-ai/` as project-rule input.

## Verification

- `python -c "import csv; list(csv.DictReader(open('tasks/backlog.csv', encoding='utf-8-sig'))); print('csv ok')"`: pass.
- `python -c "import json, pathlib; [json.loads(p.read_text(encoding='utf-8')) for p in pathlib.Path('schemas').rglob('*.json')]; print('json ok')"`: pass.
- `python -c "import pathlib, yaml; [yaml.safe_load(p.read_text(encoding='utf-8')) for p in pathlib.Path('configs').rglob('*.yaml')]; print('yaml ok')"`: pass.
- `rg -n "GlobalUser/.*v9.50|run-gates|run-c002-dry-run-suite|run-roadmap-guard|.governed-ai|governed-ai-coding-runtime|P0|P1|C002|F003" ...`: pass; expected references found.
- `pwsh -NoProfile -ExecutionPolicy Bypass -File D:\CODE\governed-ai-coding-runtime\scripts\runtime-flow-preset.ps1 -Target k12-question-graph -FlowMode daily -Mode quick -Json`: pass, `overall_status=pass`, commands were `tools/run-c002-dry-run-suite.ps1` and `tools/run-roadmap-guard.ps1`.
- `python D:\CODE\governed-ai-coding-runtime\scripts\verify-target-repo-governance-consistency.py`: pass, `target_count=6`, `drift_count=0`.
- `git diff --check`: pass.

## Git State Note

- During this work, the target repo advanced to local commit `b007f9c` (`Add C002R revision and F003 analytics contracts`), which includes the project rule integration together with existing C002R/F003 changes.
- This evidence file remains uncommitted after that commit.

## Compatibility

- No application source code was changed for this rule integration slice.
- No full gate command was redefined; `tools/run-gates.ps1` remains the full gate.
- `tools/run-c002-dry-run-suite.ps1` and `tools/run-roadmap-guard.ps1` remain daily quick feedback only.

## Rollback

- Revert `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, and this evidence file with Git.
- Re-run K12 quick gates and control-repo target governance consistency after rollback.

# 2026-05-05 Review Finding Simplification Follow-up

## Basis

- Review finding 1: roadmap guard did not enforce `I009/I010/O004B/P001`.
- Review finding 2: teacher simplification contract only checked `.admin-knowledge-panel`.
- Review finding 3: dev UI health check could call Vite origin and show `unknown` to teachers.
- Review finding 4: `docs/75_E004_PaperExportMvp.md` still pointed to deleted standalone `E005/E006`.

## Risk

- Risk level: low to medium.
- Reason: changes tighten existing roadmap/UI contracts and teacher-facing wording; no database migration, production active switch, real student data, external AI call, or backup/restore mutation.

## Changes

- `tools/run-roadmap-guard.ps1` now treats `I009/I010/O004B/P001` as first-class simplification blockers and checks their dependencies and completion evidence.
- `tools/run-i008-teacher-simplification-contract.ps1` now verifies all admin-only selectors remain hidden and are not re-opened by teacher-view CSS.
- `apps/web/src/App.tsx` now mounts `AdminGovernancePanels` outside the teacher `main.workspace` shell, so admin governance is no longer only a same-shell hidden block.
- `apps/web/src/api/client.ts` supports `VITE_KQG_API_BASE_URL`; `apps/web/vite.config.ts` proxies `/health` to the local API in development.
- `apps/web/src/App.tsx` maps missing health data to `服务未连接` instead of exposing `unknown`.
- `docs/75_E004_PaperExportMvp.md` now points old `E005/E006` scope to `M004/M005`.
- `docs/28_FunctionScopeReview.md` records that simplification findings must be enforced by gates, not only by prose.

## Verification

- `dotnet build apps/api/K12QuestionGraph.Api.csproj`: pass, 0 warnings, 0 errors.
- `npm --prefix apps/web run build`: pass.
- `npm --prefix apps/web run lint`: pass.
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-i007-frontend-boundary-contract.ps1`: pass.
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-i008-teacher-simplification-contract.ps1`: pass; checked `.admin-knowledge-panel`, `.source-material-panel`, `.activation-panel`, `.knowledge-health-panel`, `.storage-panel`, `.guardrail-panel`.
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1`: pass; checked `I008/I009/I010/O004B/P001`.
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-gates.ps1`: pass; full gate completed through backup verify.
- `git diff --check`: pass; only line-ending normalization warnings.

## Rollback

```powershell
git restore -- apps/web/src/App.tsx apps/web/src/api/client.ts apps/web/vite.config.ts docs/28_FunctionScopeReview.md docs/75_E004_PaperExportMvp.md tools/run-i007-frontend-boundary-contract.ps1 tools/run-i008-teacher-simplification-contract.ps1 tools/run-roadmap-guard.ps1
git clean -fd -- docs/evidence/20260505-review-finding-simplification-followup.md
```

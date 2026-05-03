# 62 · E001 Question Search Cards

E001 starts the P4 question bank flow with a draft/test question search and card contract. Formal production search by authoritative knowledge assets still waits for C002 source-derived activation.

## Contract

- API: `GET /questions`.
- UI marker: `data-flow="question-search"` in `apps/web/src/App.tsx`.
- Gate: `tools/run-e001-question-search-contract.ps1`.
- Unified gate steps:
  - `e001 question search ui contract`
  - `e001 question search api contract`

The API supports teacher-facing filters needed by the first search screen:

- `subject`
- `stage`
- `grade`
- `questionType`
- `status`
- `primaryKnowledgeId`
- `difficultyMin`
- `difficultyMax`
- `sourceType`
- `limit`

The response returns `mode=draft_test` and `productionEligible=false` while formal C002 is pending. Each question card includes preview text, type, estimated difficulty, status, primary knowledge summary, block/asset counts, and source summary.

## Boundary

This slice proves the searchable card shape and filter behavior. It does not claim that source-derived formal knowledge points are active, and it does not complete production paper assembly. Draft bootstrap knowledge can support API/UI regression and teacher workflow rehearsal only.

## Verification

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\run-e001-question-search-contract.ps1
.\tools\run-gates.ps1
```

## Rollback

```powershell
git clean -f -- tools/run-e001-question-search-contract.ps1 docs/62_E001_QuestionSearchCards.md
git checkout -- apps/api/Program.cs apps/web/src/App.tsx apps/web/src/App.css README.md docs/20_TaskBreakdown.md tasks/backlog.csv tools/README.md tools/run-gates.ps1
```

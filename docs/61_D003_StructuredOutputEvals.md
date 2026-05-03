# 61 · D003 Structured Output Evals

D003 keeps AI work in draft/test mode while formal C002 source-derived knowledge assets remain pending. The goal is to make structured AI outputs verifiable and repeatable before any real model call or production write is allowed.

## Contract

- Fixture suite: `configs/ai-evals/d003-structured-output-evals.sample.json`.
- Gate: `tools/run-d003-structured-output-eval.ps1`.
- Existing schema inputs:
  - `schemas/ai/knowledge_mapping.schema.json`
  - `schemas/ai/question_extraction.schema.json`
  - `schemas/ai/answer_verification.schema.json`
  - `schemas/ai/natural_language_paper_request.schema.json`
- Every fixture remains `mode=draft_test`, `allowRealModelCalls=false`, `productionEligible=false`, and `expectedReviewStatus=pending_review`.
- The gate validates required fields, JSON schema types, enum values, number ranges, item counts, confidence ranges, and schema path existence without installing external dependencies.

## Boundary

D003 does not call an external AI provider and does not mark any AI output as production ready. It only proves that future model output can be checked against stable schemas and golden smoke cases before a teacher review step.

If a schema, prompt, task type, or golden fixture changes, the suite must be updated in the same change so the old/new behavior remains reviewable. Low-confidence, split/merge, historical-analysis, or production-impacting output must continue to require manual review through the dynamic asset mapping and impact contracts.

## Verification

```powershell
.\tools\run-d003-structured-output-eval.ps1
$env:PGPASSWORD='<local-password>'
.\tools\run-gates.ps1
```

## Rollback

```powershell
git clean -f -- configs/ai-evals/d003-structured-output-evals.sample.json tools/run-d003-structured-output-eval.ps1 docs/61_D003_StructuredOutputEvals.md
git checkout -- README.md docs/20_TaskBreakdown.md tasks/backlog.csv tools/README.md tools/run-gates.ps1
```

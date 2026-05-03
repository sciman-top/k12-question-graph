# 63 · Dynamic Assets No-Stop Policy

Dynamic assets must not freeze project progress. Knowledge points are only one example. Tags, question types, difficulty and ability dimensions, rubrics, paper assembly rules, export templates, Excel field mappings, AI prompt/schema/model routing, document parsing pipelines, analytics metrics, organization structures, permissions, and privacy policies can all change over time.

The project should still build the full v0.1 system before all formal data is entered.

## Rule

When a formal version of a dynamic asset is unavailable, implement the feature in `draft/test` mode:

- Use synthetic fixtures, sample configs, draft bootstrap data, or a small temporary source set.
- Mark records and responses with `draft`, `candidate`, `pending_review`, or `productionEligible=false`.
- Add schema, API, UI, worker, eval, and gate coverage.
- Keep formal activation, official analytics, real student data, and real external AI writes blocked until review.

The task can be marked complete when the system capability is complete and the acceptance text clearly says `draft/test` or equivalent. A separate later task or gate handles production activation after formal data is imported and reviewed.

## Temporary Source Input

If a slice needs temporary raw materials, ask for the smallest useful set and store it outside Git:

```text
D:\KQG_Data\source_materials\staging\
```

Acceptable temporary material examples:

- One synthetic or teacher-provided sample paper.
- One small curriculum excerpt.
- One anonymized score Excel fixture.
- One export template draft.

Do not commit real textbook scans, copyrighted papers, student names, student IDs, class rosters, raw scores, or private school policy files to Git.

## Production Activation

Production activation requires:

- source evidence,
- version/status transition,
- mapping and replacement plan,
- migration impact report,
- human review for ambiguous or high-impact changes,
- rollback snapshot,
- full gate evidence.

Until then, the system still moves forward as a working draft/test product.

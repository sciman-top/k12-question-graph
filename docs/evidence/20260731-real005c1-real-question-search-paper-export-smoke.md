# REAL005C1 Reviewed Real Question Search Paper Export Smoke

- status: pass
- criterion_id: RG010
- rg010_status: pass
- success_sample_count: 10
- anomaly_sample_year: 2015
- success_preflight_status: ready_for_review
- anomaly_preflight_status: blocked
- artifact_status: pass

## Boundary
Repo-side reversible RG010 smoke only: it temporarily qualifies v2 pending-review samples for API exercise, generates draft Word/PDF artifacts, and restores every database mutation before reporting. It does not simulate or persist teacher approval. The 2015 answer-present/solution-missing sample remains blocked, and REAL005 stays not_closed.

# 20260505 PQR preflight dashboard

- checkedDate: 2026-05-18
- totals: all=18, todo=18, completed=0

## Blockers
- root: S012 productization and P006 release decision remain todo; downstream Q/R stay preflight-only by design
- P: P001-P006 require S012 productized E2E plus live/on-site evidence to transition from 待办
- Q: Q001-Q005 depend on P006 and second-subject real execution evidence
- R: R001-R003/R005-R007 depend on P006; R004 depends on N004 and advanced-analysis admission

## Next Actions
- Close S001->S012 first to productize the teacher workflow before live/on-site execution.
- When live/on-site execution becomes available, close P001->P006 in order with real evidence.
- After P006, execute Q001->Q005 second-subject pipeline with admission/review/activation proof.
- Then execute R-series evaluations with ADR/admission artifacts.

## Task Snapshot
| Group | Task | Status | Depends On |
|---|---|---|---|
| P | P001 | 待办 | S012;O004B;O006;O007;O008;REAL012 |
| P | P002 | 待办 | P001 |
| P | P003 | 待办 | P002 |
| P | P004 | 待办 | P003 |
| P | P005 | 待办 | P004 |
| P | P006 | 待办 | P005 |
| Q | Q001 | 待办 | P006 |
| Q | Q002 | 待办 | Q001 |
| Q | Q003 | 待办 | Q002 |
| Q | Q004 | 待办 | Q003 |
| Q | Q005 | 待办 | Q004 |
| R | R001 | 待办 | P006 |
| R | R002 | 待办 | P006 |
| R | R003 | 待办 | P006 |
| R | R004 | 待办 | N004 |
| R | R005 | 待办 | P006 |
| R | R006 | 待办 | P006 |
| R | R007 | 待办 | P006 |

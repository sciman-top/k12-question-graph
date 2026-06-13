# Reference-Basis / Repo-Preflight Slice Closeout

- status: pass_with_parallel_drift
- checkedAt: 2026-06-11T21:20:23
- recommendation: 本次主线已可单独识别，但提交或交接时应只挑选 dedicated/shared/evidence 清单，不要混入并行脏改动或临时产物。

## Dedicated Slice Dirty Paths
| Path | Git Status |
| --- | --- |
| .github/workflows/repo-preflight.yml | ?? |
| sources/reference-shelf.manifest.snapshot.json | ?? |
| tasks/reference-basis-module-map.csv | ?? |
| tasks/reference-basis-requirements.csv | ?? |
| tools/run-reference-basis-closeout-report.ps1 | ?? |
| tools/run-reference-basis-guard.ps1 | ?? |
| tools/run-repo-preflight.ps1 | ?? |
| tools/sync-reference-shelf-snapshot.ps1 | ?? |

## Shared Touchpoints Dirty Paths
| Path | Git Status |
| --- | --- |
| README.md | M |
| docs/111_ProjectNavigationOverview.md | M |
| docs/26_References.md | M |
| sources/references.md | M |
| tools/README.md | M |
| tools/run-gates.ps1 | M |

## Retained Evidence Dirty Paths
| Path | Git Status |
| --- | --- |
| docs/evidence/20260609-reference-basis-guard.json | ?? |
| docs/evidence/20260609-reference-basis-guard.md | ?? |
| docs/evidence/20260611-reference-basis-guard.json | ?? |
| docs/evidence/20260611-reference-basis-guard.md | ?? |

## Generated This Run Dirty Paths
| Path | Git Status |
| --- | --- |
| docs/evidence/20260611-reference-basis-preflight-closeout.json | ?? |
| docs/evidence/20260611-reference-basis-preflight-closeout.md | ?? |

## Temporary / Host-Local Paths
- none

On-disk temporary paths:
- tmp/ci
- tmp/repo-preflight

## Unrelated Dirty Paths
| Path | Git Status |
| --- | --- |
| apps/api/K12QuestionGraph.Api.csproj | M |
| docs/evidence/20260529-ns202-admin-internal-fail-closed-report.json | M |
| docs/evidence/20260529-ns203-privacy-license-scan-report.json | M |
| docs/evidence/20260529-ns204-no-active-write-guard-report.json | M |
| docs/evidence/20260607-ns1301-architecture-slimming.json | M |
| docs/evidence/20260607-ns1302-service-control-panel.json | M |
| docs/evidence/20260607-ns1303-host-capability-diagnostic-report.json | M |
| docs/evidence/20260607-ns1303-runtime-profile.json | M |
| docs/evidence/20260607-ns1304-toolchain-profile.json | M |
| docs/evidence/20260607-ns1305-role-routed-ai.json | M |
| docs/evidence/20260607-ns1308-release-evidence-pack.json | M |
| docs/evidence/i007-frontend-boundary-report.json | M |
| docs/evidence/20260529-ns201-role-audit-baseline-report.json | M |
| docs/evidence/j004-fidelity-regression-report.json | M |
| docs/evidence/j006-import-accuracy-workload-report.json | M |
| docs/evidence/k001-active-c002-production-query-report.json | M |
| docs/evidence/k002-c002r-teacher-revision-ux-report.json | M |
| docs/evidence/k003-mapping-review-workbench-ui-report.json | M |
| docs/evidence/k004-historical-version-explanation-report.json | M |
| docs/evidence/k005-c002-second-revision-drill-report.json | M |
| docs/evidence/k006-knowledge-asset-health-dashboard-report.json | M |
| tasks/automation-first-contract.csv | M |
| tools/run-ns203-privacy-license-scan.ps1 | M |
| tools/start-local-api.ps1 | M |
| tools/start-local-web.ps1 | M |
| docs/evidence/j005-adapter-diagnostic-supply-chain-report.json | M |
| docs/evidence/20260529-ns106-feature-profile-guard-report.json | M |
| docs/evidence/20260529-ns105-teacher-route-client-boundary-report.json | M |
| docs/evidence/20260529-ns104-application-service-boundary-report.json | M |
| apps/api/Program.cs | M |
| apps/web/.gitignore | M |
| apps/web/eslint.config.js | M |
| apps/web/src/App.css | M |
| apps/web/src/App.tsx | M |
| apps/web/src/api/client.ts | M |
| apps/web/src/api/contracts.ts | M |
| apps/web/src/api/queries.ts | M |
| apps/web/src/ui/AiRoutingControlPanel.tsx | M |
| apps/web/vite.config.ts | M |
| docs/103_ExecutionControlBoard.md | M |
| docs/104_OpenQuestionsAndAssumptions.md | M |
| docs/105_RoleApprovalAndExceptionMatrix.md | M |
| docs/107_AITrustAndReviewContract.md | M |
| docs/109_ReleaseGoNoGoCard.md | M |
| docs/110_EngineeringEndStateChecklist.md | M |
| docs/112_CurrentClosureStatus_20260609.md | M |
| docs/113_LocalRuntimeOperations_20260609.md | M |
| docs/99_ProductizationFullRoadmapAndTaskPlan.md | M |
| docs/evidence/20260506-s0-execution-plan-guard.json | M |
| docs/evidence/20260506-s001-completion-state-dashboard.json | M |
| docs/evidence/20260506-s001-completion-state-dashboard.md | M |
| docs/evidence/20260508-automation-first-feature-contract-report.json | M |
| docs/evidence/20260512-real005-guangzhou-2015-2025-closure-standard-report.json | M |
| docs/evidence/20260528-ns004-non-site-plan-guard-report.json | M |
| docs/evidence/20260609-ns1305a-admin-ai-settings-dialog.json | ?? |
| tools/run-ns1305a-admin-ai-settings-dialog-contract.ps1 | ?? |

## Missing Dedicated Paths
- none

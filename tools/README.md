# tools

Repository automation scripts live here and must run independently from the Web UI.

Current entries:

```powershell
tools/run-gates.ps1
tools/backup.ps1
tools/verify-backup.ps1
```

Run gates:

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\run-gates.ps1
```

The gate also covers `i001-i008 teacher workflow UI contracts`,
`b001 duplicate upload smoke`, `b002 adapter contract smoke`,
`b003 source preview smoke`, `b004/b004a UI contracts`, and
`b005 save question api smoke`, `b006 question source review smoke`,
`b007 golden import regression`, `b008 p1 proxy scenario`,
`roadmap dependency guard`, `c002 source material admission guard`,
`c001 knowledge ontology contract`, `c002a domain asset contract`,
`c002b replacement mapping contract`, `c002c migration impact contract`,
`c002d source-derived admission contract`, `c002e activation guard contract`,
`c002h mapping review workbench contract`,
`local-first ai consumption guard`,
`c002n source chunk cache guard`,
`c002o candidate extraction schema/eval guard`,
`c002p model budget guard`,
`c002q0 outer ai readiness guard`,
`c002q ai extract dry-run guard`,
`c002s formalization precheck guard`,
`c002 junior physics draft bootstrap guard`, and
`d001 model router draft-test contract`, and
`d002 ai job cost contract`, and
`d003 structured output eval contract`, and
`e001 question search ui/api contracts`, `e002 paper request contract`, and
`e003 question replacement undo contract`, and
`e004 paper export contract`, and
`j004 formula/table/figure fidelity regression`, and
`j005 adapter diagnostic supply-chain gate`, and
`j006 import accuracy workload baseline`, and
`k001 active c002 production query contract`, and
`f001 assessment model contract`, and
`f002 score import contract`.
It also includes `o004 admin internal auth boundary contract`, which requires
`/api/admin/*` and `/internal/ai/*` to be blocked outside explicit draft/test
or configured admin-key contexts.
It also includes `o001 windows service publish package contract`, which
publishes API/Web, packages worker script into publish output, and verifies the
published API can boot with `--contentRoot` from a non-repo working directory.
It starts temporary
API processes for API smoke steps, so `PGPASSWORD` must match the local PostgreSQL
password.

O001 windows service publish package contract:

```powershell
.\tools\run-o001-windows-service-publish-contract.ps1
```

This validates that the Windows publish package has API/Web artifacts,
`PythonWorker.DocumentWorkerScript` points to package-local worker path,
`KqgPaths` stays absolute, and health/readiness pass when the published API is
started from a temporary working directory (not repository root).

O002 installer initialization wizard contract:

```powershell
.\tools\run-o002-installer-init-wizard-contract.ps1
```

This validates installer initialization readiness in draft/test mode:
PostgreSQL connection parameters, data/backup/file-store/log/cache directory
creation and writable probes, embedded G004 pgpass dry-run, and bootstrap admin
key hashing (without persisting plaintext). It does not complete RBAC/audit
closure, which remains blocked by `O004B`.

NS803 installer host diagnostic:

```powershell
.\tools\run-ns803-installer-host.ps1
```

This reuses the installer initialization config for the non-site NS8 track. It
checks writable data/backup/file-store/log/cache/model-cache roots, runs the
pgpass dry-run, worker profile diagnostic, and host capability diagnostic, then
writes `docs/evidence/20260530-ns803-installer-host.json`. It stays read-only
for host capabilities: no dependency install, network requirement, model weight
download, production default switch, or plaintext password evidence.

NS804 windows service publish package:

```powershell
.\tools\run-ns804-windows-service-package.ps1
```

This reuses the O001 publish package contract for the non-site NS8 track. It
requires NS803 evidence, publishes API/Web plus the document worker package,
boots the published API from a temporary working directory with explicit
`--contentRoot`, checks health/readiness, and writes
`docs/evidence/20260530-ns804-windows-service.json`. It does not install a
Windows Service, change firewall rules, or switch production defaults.

NS805 capacity/cost/health dashboard:

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\run-ns805-health-dashboard.ps1
```

This aggregates the non-site NS8 dashboard readiness evidence: NS801/NS802
backup and restore signals, NS803 host diagnostic, NS804 package health,
NS503 AI cost evidence, G002 cache cleanup boundaries, K006 knowledge health,
and O005 admin UI/API contracts. It writes
`docs/evidence/20260530-ns805-health-dashboard.json` and stays draft/test:
no production data delete, external AI call, active asset write, or service
installation.

NS806 EF migration bundle upgrade rehearsal:

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\run-ns806-upgrade-bundle.ps1
```

This wraps the O007 EF migration bundle rehearsal for the non-site NS8 track.
It requires NS804 package health and NS805 dashboard evidence, builds/runs the
EF migration bundle through O007, then checks post-bundle backup verification
and isolated restore drill evidence. It writes
`docs/evidence/20260530-ns806-upgrade-bundle.json` and remains draft/test: no
Windows Service install, production default switch, production data cleanup,
external AI call, active asset write, or live deployment closure.

NS901 non-site scenario pack:

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\run-ns901-non-site-scenario-pack.ps1
```

This verifies the NS9 synthetic/proxy scenario pack from runtime evidence. It
requires NS607 export artifacts, NS704 commentary report export, NS806 upgrade
restore evidence, S012A fixture admission, and S012B non-site E2E rehearsal.
It writes `docs/evidence/20260530-ns901-non-site-scenario-pack.json`. It can
run with `-SkipS012Refresh` after S012A/S012B have just run in the full gate.
The report marks `nonSiteValidated=false`: authorized/anonymized school
materials, isolated-machine deployment, teacher observation, printer/network,
domain permission checks, and live operator signoff remain NS904/NS1001/P001
boundaries.

NS903 completion dashboard refresh:

```powershell
.\tools\run-ns903-completion-dashboard.ps1
```

This refreshes the completion-state evidence after NS901/NS902/NS906 runtime
checks. It verifies the S001 dashboard, keeps `release_ready=0`, keeps
`nonSiteValidated=false`, and preserves explicit P001/REAL005 blockers. It
writes `docs/evidence/20260530-ns903-completion-dashboard.json`. It is
evidence-only: no external AI call, real student data, production history
write, active asset mutation, or live pilot closure.

NS904 P001 readiness evidence pack:

```powershell
.\tools\run-ns904-p001-readiness-pack.ps1
```

This assembles the P001 readiness pack after NS903 and the P001 preflight
contract. It verifies NS803 installer/host diagnostics, NS804 publish package,
NS805 capacity/health evidence, NS806 upgrade/restore evidence, NS901 scenario
coverage, NS906 visual surrogate boundaries, and REAL005 `not_closed`. It
writes `docs/evidence/20260530-ns904-p001-readiness.json`, keeps
`p001CanClose=false`, keeps `releaseReady=false`, and lists the remaining
isolated-machine, onsite-teacher, printer, network, domain-permission, and
operator-signoff blockers for the P001 checklist.

NS905 status sync audit:

```powershell
.\tools\run-ns905-status-sync-audit.ps1
```

This audits the backlog, completion-state dashboard, and non-site plan after
NS904. It keeps P001-P006 as `待办`, requires zero `release_ready` and zero
`non_site_validated` rows, verifies dashboard P001 blockers still point to real
backlog tasks, and checks NS903/NS904 runtime evidence cannot be overwritten by
older planned states. It writes `docs/evidence/20260530-ns905-status-sync.md`.

NS1101 second-subject candidate boundary pack:

```powershell
.\tools\run-ns1101-second-subject-candidate-boundary.ps1
```

This verifies the Q001 second-subject candidate admission boundary after the
NS905 status sync. It keeps `P006` and `Q001` as `待办`, keeps NS1001-NS1005
as `blocked_by_onsite`, requires `closeTaskAllowed=false`, and writes
`docs/evidence/20260530-ns1101-second-subject-candidate.json` with
`productionEligible=false`, `activeAssetMutation=false`, and
`secondSubjectAdmissionExecuted=false`. It is a boundary/preflight pack only:
no source package import, candidate manifest creation, or active asset switch.

NS1102 second-subject teacher review template boundary pack:

```powershell
.\tools\run-ns1102-second-subject-review-template-boundary.ps1
```

This verifies the Q002 teacher review template boundary after NS1101. It keeps
`Q001`, `Q002`, and `Q003` as `待办`, requires `closeTaskAllowed=false`, and
writes `docs/evidence/20260530-ns1102-second-subject-review-template.json`
with `teacherReviewExecuted=false`, `realCandidateAssetsReviewed=false`,
`productionEligible=false`, and `q003CanAdvance=false`. It is a template
boundary/preflight pack only: no real teacher review execution, no real
candidate asset review, no Q003 active drill, and no active asset switch.

NS1103 second-subject active dry-run boundary pack:

```powershell
.\tools\run-ns1103-second-subject-active-dry-run-boundary.ps1
```

This verifies the Q003 second-subject active dry-run boundary after NS1102. It
keeps `Q002`, `Q003`, and `Q004` as `待办`, requires `closeTaskAllowed=false`,
and writes `docs/evidence/20260531-ns1103-second-subject-active-dry-run.json`
with `activeDryRunExecuted=false`, `activeSwitchPerformed=false`,
`rollbackSnapshotRecorded=false`, `productionEligible=false`, and
`q004CanAdvance=false`. It is an activation boundary/preflight pack only: no
active dry-run execution, no active asset switch, no rollback snapshot write,
and no Q004 cross-subject advancement.

NS1104 cross-subject UI boundary pack:

```powershell
.\tools\run-ns1104-cross-subject-ui-boundary.ps1
```

This verifies the Q004/Q005 cross-subject diff and multi-subject UI
simplification boundary after NS1103. It keeps `Q003`, `Q004`, and `Q005` as
`待办`, requires both Q004 and Q005 reports to remain `preflight_only`, and
writes `docs/evidence/20260531-ns1104-cross-subject-ui.json` with the ordinary
teacher surface still limited to four high-frequency entries. It is a
boundary/preflight pack only: no real cross-subject diff report, no subject
switching UI, no UI smoke execution, and no Q004/Q005 closure.

NS0-NS2 runtime closure pack:

```powershell
.\tools\run-ns0-ns2-runtime-closure.ps1
```

This verifies the early non-site governance and safety rows that were previously
`repo_landed`: NS001-NS005, NS103, NS105, NS106, and NS201-NS204. It checks the
status dictionary, completion dashboard, module ownership map, fixture/privacy
policy, raw-source Git boundary, refreshed NS103 typed API snapshot, and reruns
the NS004/105/106/201/202/203/204 guards. It writes
`docs/evidence/20260531-ns0-ns2-runtime-closure.json` and remains a
non-production closure pack only: no real student data, no external AI, no
active switch, and no production-history write.

NS1201 search and semantic retrieval admission boundary pack:

```powershell
.\tools\run-ns1201-search-eval.ps1
```

This verifies the R001 search/semantic retrieval upgrade boundary after the
NS1005 release decision remains blocked by onsite evidence. It keeps `P006`
and `R001` as `待办`, keeps PostgreSQL FTS/`pg_trgm` as the default route, and
writes `docs/evidence/20260531-ns1201-search-eval.json` with pgvector,
embedding generation, and external search still blocked until real FTS
insufficiency evidence exists. It is an admission boundary pack only: no field
benchmark, no pgvector migration, no embedding route, no external search setup,
and no teacher-facing search route change.

NS1202 queue and worker scale admission boundary pack:

```powershell
.\tools\run-ns1202-queue-eval.ps1
```

This verifies the R002 queue/worker scale boundary after the NS1005 release
decision remains blocked by onsite evidence. It keeps `P006` and `R002` as
`待办`, keeps PostgreSQL job store + `BackgroundService` as the default route,
and writes `docs/evidence/20260531-ns1202-queue-eval.json` with Hangfire,
RabbitMQ, broker setup, and distributed worker routing still blocked until real
throughput or reliability evidence exists. It is an admission boundary pack
only: no field throughput benchmark, no package install, no broker setup, and
no default worker route change.

NS1203 interoperability profile map boundary pack:

```powershell
.\tools\run-ns1203-interop-profile-map.ps1
```

This verifies the R007 profile-map boundary after the NS1005 release decision
remains blocked by onsite evidence. It keeps `P006`, `R003`, and `R007` as
`待办`, verifies the QuestionItem/Paper/KnowledgeNode/ScoreRecord/AnalysisEvent
profile map to QTI/CASE/OneRoster/Caliper, and writes
`docs/evidence/20260531-ns1203-interop-profile-map.json`. It is an admission
boundary pack only: no QTI/CASE/OneRoster/Caliper import/export, no SIS sync,
no Caliper event stream, and no schema mutation.

NS1204 advanced analysis admission boundary pack:

```powershell
.\tools\run-ns1204-advanced-analysis-admission.ps1
```

This verifies the R004 advanced-analysis boundary after NS704 commentary report
evidence. It keeps `R004` as `待办`, keeps basic CTT/commentary as draft/test,
and writes `docs/evidence/20260531-ns1204-advanced-analysis-admission.json`
with IRT, form equating, and longitudinal growth still blocked until sample,
owner, explanation, and rollback evidence exists. It is an admission boundary
pack only: no real student data, no IRT/equating/growth computation, no
advanced-analysis UI route, and no formal history write.

NS1205 public/multischool deployment admission boundary pack:

```powershell
.\tools\run-ns1205-multischool-admission.ps1
```

This verifies the R005 public/multischool deployment boundary after the NS1005
release decision remains blocked by onsite evidence. It keeps `P001`, `P006`,
and `R005` as `待办`, keeps single-school LAN as the only preferred future
route, and writes `docs/evidence/20260531-ns1205-multischool-admission.json`
with public internet exposure, multi-school shared deployment, and multi-tenant
SaaS still blocked. It is an admission boundary pack only: no network exposure,
no tenant schema/config, no reverse proxy/Kubernetes default, and no release
state change.

NS1206 tech-debt cadence boundary pack:

```powershell
.\tools\run-ns1206-techdebt-cadence.ps1
```

This verifies the R006 long-term maintenance cadence boundary after the NS1005
release decision remains blocked by onsite evidence. It keeps `P001`, `P006`,
and `R006` as `待办`, keeps dependency refresh as report-only, blocks
performance work until a baseline exists, and writes
`docs/evidence/20260531-ns1206-techdebt-cadence.json`. It is an admission
boundary pack only: no dependency upgrade, no model download, no performance
mutation, no experiment deletion, and no production cleanup.

NS1301 architecture slimming guard:

```powershell
.\tools\run-ns1301-architecture-slimming-guard.ps1
```

This verifies the NS13 structure-slimming baseline from repository facts. It
checks that `App.tsx` has already pushed large static workbench config and
display helpers into extracted UI/data modules, that the current architecture
inventory is documented in `docs/03_Architecture.md`, and that the API host
still exposes the Windows Service + workflow-service ownership markers. It
writes `docs/evidence/20260607-ns1301-architecture-slimming.json` and remains a
repo-structure guard only: it does not claim every import/review endpoint is
fully thin and it keeps the remaining NS104 legacy direct-DB debt explicit.

NS1302 service control panel contract:

```powershell
.\tools\run-ns1302-service-control-panel-contract.ps1
```

This verifies the NS13 Windows Service-first release shape plus the
administrator-only service control panel surface. It depends on NS804 package
smoke, NS805 health dashboard evidence, and NS806 upgrade rehearsal evidence,
then checks the `ServiceControlPanel` UI contract, CSS markers, admin-only
mounting, and the absence of teacher workflow leakage. It writes
`docs/evidence/20260607-ns1302-service-control-panel.json`. It does not install
or start a real Windows Service on a target machine; isolated-machine
deployment, operator validation, and live release signoff remain under
`NS1001/P001/P006`.

NS1303 runtime profile contract:

```powershell
.\tools\run-ns1303-runtime-profile-contract.ps1
```

This turns the existing worker-profile diagnostic plus host-capability
diagnostic into one NS13 draft config overlay pack. It reruns the read-only
diagnostics, verifies the required `localSystemProfile` keys
(`workerOcrProfile`, `aiNetworkProfile`, `aiLocalModelProfile`,
`searchProfile`, `queueProfile`, and the remaining runtime/storage/security
profiles), checks that the service control panel exposes
`service-open-config-diff`, and writes
`docs/evidence/20260607-ns1303-runtime-profile.json` together with fresh worker
and host diagnostic reports. It does not mutate `appsettings.json`, install
dependencies, download model weights, enable cloud providers, or switch any
production default.

NS1304 toolchain admission contract:

```powershell
.\tools\run-ns1304-toolchain-admission-contract.ps1
```

This validates the open-source/free toolchain admission boundary for the current
host. It reads `configs/toolchain-admission.catalog.yaml`, combines the
NS1303 runtime-profile overlay with J005/J006 plus NS304/NS305/NS306 evidence,
probes current CLI/module availability (`pdftotext`, `pdftoppm`,
`rapidocr_onnxruntime`, `qpdf`, `gswin64c`, `magick`, `vips`, PostgreSQL CLI,
`robocopy`, and candidate Python modules), and writes
`docs/evidence/20260607-ns1304-toolchain-profile.json`. Missing heavy tools
must remain fail-closed to lighter profiles or manual takeover; the contract
does not install packages, download models, or switch default OCR/export
routes.

O003 recovery drill upgrade contract:

```powershell
.\tools\run-o003-recovery-drill-contract.ps1
```

This runs a backup + verify cycle, then performs isolated restore drill steps
from the generated manifest: PostgreSQL dump restore plan extraction
(`pg_restore -l`), schema-only extraction, file store copy restore, config
restore, templates restore, and teacher preference restore. The drill writes to
`tmp/o003/*` only and does not mutate production active assets.

I008 teacher simplification contract:

```powershell
.\tools\run-i008-teacher-simplification-contract.ps1
```

This blocks ordinary teacher views from showing C002R governance workbenches,
mapping review, storage/asset health dashboards, and engineering/test terms
such as `draft_test`, `productionEligible=false`, `synthetic fixture`,
`active switch`, `candidate`, `migration`, and `rollback snapshot`.

F002 score import contract:

```powershell
.\tools\run-f002-score-import-contract.ps1
```

This validates synthetic `.xlsx` score import, reusable field mapping,
centralized row errors, database score import tables, no PII, and the
non-production boundary.

C002 dynamic assets dry-run suite:

```powershell
.\tools\run-c002-dry-run-suite.ps1
```

This runs source material admission, replacement mapping, migration impact,
candidate admission, and activation guard contracts without requiring database
access. It does not replace full gate database checks.

C002 candidate CSV cleanup:

```powershell
.\tools\prepare-c002-candidate-csvs.ps1
.\tools\prepare-c002-candidate-csvs.ps1 -InputDir 'guangzhou-physics-full-research-package-2016-2025\csv' -OutputDir 'c002-k12-question-graph-candidate-csvs\cleaned'
```

This validates and normalizes ChatGPT Web extracted candidate CSVs from
`c002-k12-question-graph-candidate-csvs`, writes the cleaned package under
`c002-k12-question-graph-candidate-csvs\cleaned`, and keeps all rows as
`pending_review` and non-production. The cleaned files are input for the later
C002K candidate DB import, not formal activation evidence by themselves.
When the input directory contains `c003-source-material.csv`, the same command
also accepts the complete Guangzhou physics C003 full research package and
converts `c003-*full` files into the existing C002 candidate import shape. This
is a candidate-data replacement path only; it still requires source hash
alignment, human review, impact confirmation, rollback evidence, and active
guard before any production activation.

C003 quality-review overlay:

```powershell
.\tools\merge-c003-quality-review-package.ps1 -Force
```

This overlays `guangzhou-physics-full-research-package-2016-2025\quality-review-complete-csv-package`
onto the complete C003 CSV package and writes the merged candidate package to
`D:\KQG_Data\candidate_packages\c003-merged-quality-review-2016-2025`.
The overlay preserves core ontology and mapping CSVs from the full package,
then applies the reviewed question, answer, year-report, source, and quality
issue evidence tables. It does not write the database and does not activate
C002.

C002 real source material import:

```powershell
.\tools\import-c002-source-materials.ps1
```

The default mode is dry-run only and writes
`docs/evidence/c002-source-material-import-report.json`. It classifies local PDF
materials and reports the intended `sourceType`, `materialBatchKey`, and
source-use flags without writing the database. The default raw PDF source root
is `D:\KQG_Data\source_materials\imported\guangzhou_physics_2016_2025`; raw
source PDFs stay outside git.

Persistent import requires a valid local database password and should be run
after a backup check:

```powershell
$env:PGPASSWORD='<local-password>'
$env:KQG_CONNECTION_STRING='Host=127.0.0.1;Port=5432;Database=k12_question_graph;Username=postgres;Password=<local-password>'
.\tools\import-c002-source-materials.ps1 -Apply -StartApi
```

This uploads the original files through the API into `SourceDocument/FileAsset`
evidence only. It must not mark C002 formal knowledge as complete and must not
activate candidate assets.

C002N source chunk cache:

```powershell
.\tools\run-c002n-source-chunk-cache.ps1
```

The default source root is
`D:\KQG_Data\source_materials\imported\guangzhou_physics_2016_2025`. The script
keeps using `docs\evidence\c002-source-material-import-report.json` for source
metadata, but resolves PDFs from the canonical Git-external imported source
directory so the old repository-local `广州中考` folder is no longer required.

This extracts local page-level text from the 33 admitted source PDFs, records
source/page/chunk hashes, block-type summaries, token estimates, cache
idempotency, and a Chinese report at
`docs/evidence/c002n-source-chunk-cache-report.json`. Cache files stay under
`tmp/c002n-source-chunk-cache` and are not committed. The script does not call
external AI and does not activate formal C002 assets.

C002O candidate extraction schema/eval:

```powershell
.\tools\run-c002o-candidate-extraction-eval.ps1
```

This validates the C002 candidate extraction schema and a golden eval fixture
for `knowledge_points`, `curriculum_standard_items`, `textbook_chapters`,
`exam_points`, `trend_summaries`, and `mapping_suggestions`. It reads C002N
chunk hashes as source anchors, keeps every item `pending_review`, and does not
call a real model or activate formal C002 assets.

C002P model budget guard:

```powershell
.\tools\run-c002p-model-budget-guard.ps1
```

This validates the L0-L4 extraction layers, default model roles, reasoning
effort, escalation targets, dry-run token caps, cache-key requirements, and
fail-closed budget policy. It also reads the C002N chunk/token report and C002O
schema/eval report, then writes
`docs/evidence/c002p-model-budget-guard-report.json`. It does not call external
AI and does not mark C002 as active.

C002S formalization precheck:

```powershell
.\tools\run-c002s-formalization-precheck.ps1
```

This reads the complete Guangzhou physics C003 candidate CSV package. When
`quality-review-complete-csv-package` exists, it first creates the merged
overlay package through `merge-c003-quality-review-package.ps1`, then samples
three questions per year for 2016-2025, checks exam stem, answer source,
year-report page anchor, exam point, knowledge point, curriculum, and textbook
references, then writes
`docs/evidence/c002s-formalization-precheck-report.json`. The current expected
C002S state is `pass`: sample evidence passes and 210 year-report page/metric
quality issues are resolved. Production activation still stays blocked until
C002L/C002M review blockers and active guard are cleared.

C002 candidate DB import:

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\import-c002-candidate-assets.ps1
```

The default mode is dry-run. It validates cleaned CSVs, source hash alignment,
mapping references, and active/reviewed overwrite guards.

Persistent candidate import requires a backup manifest:

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\backup.ps1
.\tools\import-c002-candidate-assets.ps1 -Apply -BackupManifest 'D:\KQG_Backups\<timestamp>\manifest.json'
```

This writes only `candidate` domain assets, `pending_review` mappings, a
`pending_review` migration plan, and one review queue item. It must leave
`active` domain assets at zero for this batch.

C002 candidate review readiness:

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\run-c002l-candidate-review-readiness.ps1
```

This reads the imported C002 candidate batch and reports remaining activation
blockers. It does not approve or activate data. C002 completion means a governed
v1 active default version, not a permanent freeze; future changes must enter as
new candidate versions with mapping, impact, review, rollback, and active guard.

C002 candidate review apply contract:

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\run-c002m-candidate-review-apply-contract.ps1
```

The default mode is dry-run. It generates and validates an approve/reject/
keep-pending decision contract from the real C002 candidate batch, requires
review reasons for approve/reject decisions, and records rollback expectations.
Real apply requires an explicit decision file and still must not activate C002.

C002 batch review decision generation:

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\generate-c002-review-decisions.ps1
.\tools\run-c002m-candidate-review-apply-contract.ps1 -DecisionFile 'docs\evidence\c002-review-decisions.generated.json' -Apply
```

The generated decision file approves source-hash-aligned candidate assets and
internal mappings only. It does not activate C002; active switch remains guarded
by readiness and active guard checks.

C002 active switch guard:

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\run-c002t-active-switch.ps1
$backup = .\tools\backup.ps1 | ConvertFrom-Json
.\tools\verify-backup.ps1 -ManifestPath $backup.manifest
.\tools\run-c002t-active-switch.ps1 -BackupManifest $backup.manifest -Apply
```

The default mode is dry-run. Apply requires a backup manifest and only switches
the reviewed Guangzhou physics C002 batch to `active` after source hashes,
review decisions, mappings, migration state, review queue, and rollback evidence
are clean. It is idempotent after activation.

Generic subject activation pipeline:

```powershell
.\tools\run-domain-asset-activation.ps1 `
  -ImportKey '<subject_candidate_import_key>' `
  -MaterialBatchKey '<source_material_batch_key>' `
  -EvidencePrefix '<subject>-activation' `
  -ExpectedSourceDocumentCount 0
```

This is the preferred entrypoint for future subjects. It orchestrates readiness,
optional review-decision generation/application, active dry-run, backup,
activation, and final idempotency evidence. See
`docs/78_SubjectDomainAssetActivationRunbook.md`.

Teacher review and activation templates:

```text
docs/templates/subject-candidate-review-checklist.md
docs/templates/subject-activation-approval-form.md
docs/79_TeacherCandidateReviewAndActivationGuide.md
```

These define what teachers should review, the minimum sampling rules, the
approval form, and the exact operation process before a subject goes active.

Subject activation workbench UI contract:

```powershell
.\tools\run-subject-activation-workbench-ui-contract.ps1
```

The Web workbench is the teacher-facing simplification layer for the same
process. It must keep teachers on review/confirmation actions and must not
expose a direct activation script button. The contract is included in
`tools/run-gates.ps1`; see `docs/80_SubjectActivationWorkbenchV0.md`.

Golden import regression:

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\run-import-golden.ps1
```

P1 proxy scenario:

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\run-p1-proxy-scenario.ps1
```

C001 knowledge ontology contract:

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\run-c001-contract.ps1
```

C002A domain asset contract:

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\run-c002a-domain-asset-contract.ps1
```

This verifies versioned domain asset tables, replacement mapping constraints,
dry-run migration reports, rollback snapshots, and non-destructive auto-apply
semantics for high-confidence low-impact mappings.

C002B replacement mapping contract:

```powershell
.\tools\run-c002b-replacement-mapping-contract.ps1
```

This validates draft -> formal mapping decisions without touching the database.
Only high-confidence, low-impact, reversible `equivalent` or `renamed` mappings
can be auto-applied; split/merge/broader/narrower/deprecated or higher-impact
changes stay in `pending_review`.

C002C migration impact contract:

```powershell
.\tools\run-c002c-migration-impact-contract.ps1
```

This validates the dry-run impact report for question bindings, tags, search
indexes, assembly constraints, analysis metrics, and fixtures. Historical
analysis metrics are frozen instead of rewritten automatically.

C002D source-derived admission contract:

```powershell
.\tools\run-c002d-source-derived-admission-contract.ps1
```

This validates that source-derived ontology candidates cite admitted source
materials, remain `candidate`, require teacher review before activation, and
feed the C002B/C002C dry-run replacement and impact plans.

C002E activation guard contract:

```powershell
.\tools\run-c002e-activation-guard-contract.ps1
```

This validates that source-derived candidates cannot become `active` while
teacher review, pending mapping decisions, or frozen historical analysis
approval remains unresolved.

C002H mapping review workbench contract:

```powershell
.\tools\run-c002h-mapping-review-workbench-contract.ps1
```

This validates the non-DB contract for convenient human mapping review:
required filters, views, keyboard actions, one-to-one/one-to-many/many-to-many
coverage, impact preview, rollback preview, audit fields, undo, and batch
approval limits.

C002 junior physics draft bootstrap guard:

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\run-c002-seed-validation.ps1
```

This is not the formal C002 completion gate. It keeps the non-authoritative
draft bootstrap data idempotent and marked as `draft` until teachers import
textbooks, curriculum standards, and recent local exam papers for source-derived
review. Draft nodes may be used by API/UI/regression tests, but production flows
must wait for source-derived `active` knowledge nodes.

D001 ModelRouter draft/test contract:

```powershell
.\tools\run-d001-model-router-contract.ps1
```

This starts a temporary API process and validates that real model calls remain
disabled, LLM tasks route to `stub_llm`, structured output schemas exist,
draft/domain-asset routes are not production eligible, and unknown AI tasks are
rejected. It does not call any external AI provider.

Roadmap dependency guard:

```powershell
.\tools\run-roadmap-guard.ps1
```

This blocks production P3+ completion while formal C002 remains `暂缓`.
Draft/test work is allowed when it stays behind schema, Evals, cost logging,
manual review, migration suggestions, and non-production evidence.

D002 AI job cost contract:

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\run-d002-ai-job-cost-contract.ps1
```

This applies the D002 migration and validates that a synthetic stub AI task
records provider, model, routing version, prompt/schema versions, input hash,
tokens, cached tokens, zero stub cost, latency, confidence, review status, and
idempotency without calling any external AI provider.

D003 structured output eval contract:

```powershell
.\tools\run-d003-structured-output-eval.ps1
```

This validates draft/test golden smoke fixtures against the AI structured output
schemas without calling external AI providers. It keeps all eval cases
`pending_review`, non-production, and repeatable.

E001 question search contract:

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\run-e001-question-search-contract.ps1
```

This validates draft/test question-card search by knowledge point, question type,
difficulty range, and source type. The response remains non-production while
formal C002 source-derived knowledge assets are pending.

E002 paper request contract:

```powershell
.\tools\run-e002-paper-request-contract.ps1
```

This validates natural-language paper request parsing in `draft_test` mode. It
returns system understanding, a blueprint draft, and review questions without
calling real models or writing production paper semantics.

E003 question replacement undo contract:

```powershell
.\tools\run-e003-question-replacement-contract.ps1
```

This validates one-click replacement and undo in `draft_test` mode. Replacement
keeps the same knowledge point, question type, similar difficulty, and score,
excludes duplicate/recently used questions, and returns an undo snapshot.

E004 paper export contract:

```powershell
.\tools\run-e004-paper-export-contract.ps1
```

This validates `draft_test` Word/PDF export artifacts without requiring formal
C002 activation. It checks the generated DOCX/PDF manifest, formula text, figure
media, table content, frontend export controls, and non-production boundary.

J004 formula/table/figure fidelity regression:

```powershell
.\tools\run-j004-fidelity-regression-contract.ps1
```

This validates a synthetic OpenXML import-to-export chain. It requires formula,
table, and image blocks from the worker, preserves source regions and image
assets in a draft question shape, then checks the exported DOCX/PDF artifacts.
It does not use real student data, external AI, or production activation.

J005 adapter diagnostic supply-chain gate:

```powershell
.\tools\run-j005-adapter-diagnostic-supply-chain-contract.ps1
```

This validates that every current worker adapter records adapter/tool versions,
command arguments, duration, input/output hashes, warnings, and errors. It also
locks this diagnostic gate to local synthetic fixtures without external OCR,
Docling, network access, real student data, or real AI calls.

J006 import accuracy workload baseline:

```powershell
.\tools\run-j006-import-accuracy-workload-contract.ps1
```

This writes the proxy import accuracy and teacher workload baseline from golden
samples plus J001-J005 evidence. It records source-region/block preservation,
confirmation items, failure takeover steps, and explicitly keeps automated cut
accuracy as N/A while no real OCR/AI cutting evidence exists.

K001 active C002 production query contract:

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\run-k001-active-c002-production-query-contract.ps1
```

This read-only database contract verifies that question search, paper assembly
constraints, and knowledge mastery analysis default to the active C002 v1
version reference. It does not mutate active assets, write production history,
use real student data, or call external AI.

K002 C002R teacher revision UX contract:

```powershell
.\tools\run-k002-c002r-teacher-revision-ux-contract.ps1
```

This runs the C002R versioned revision contract, then checks that the Web UI has
a teacher-facing revision intake with only the four low-friction fields:
change reason, source evidence, affected scope, and urgency. The UI contract
also verifies that system-generated candidate, mapping, impact, and rollback
outputs are visible while teacher-facing active switch actions stay absent.

K003 mapping review workbench UI contract:

```powershell
.\tools\run-k003-mapping-review-workbench-ui-contract.ps1
```

This runs the C002H mapping review workbench contract, then checks that the Web
UI exposes side-by-side old/new assets, mapping edges, source evidence, impact
preview, rollback preview, review history, and manual actions for high-risk
`split`, `merge`, and `deprecated` mappings. It also verifies that high-risk
bulk approval and direct active apply actions are absent.

K004 historical version explanation contract:

```powershell
.\tools\run-k004-historical-version-explanation-contract.ps1
```

This starts the API, posts the synthetic regression fixture to
`POST /knowledge-version-explanations/resolve`, and verifies that legacy
questions, legacy papers, and historical analysis reports keep a frozen
historical knowledge version while exposing the current-version mapping in a
teacher-visible summary. The contract is read-only, uses no real student data,
and does not rewrite production history.

K005 C002 second revision drill contract:

```powershell
.\tools\run-k005-c002-second-revision-drill-contract.ps1
```

This first re-runs the C002R versioned revision dependency contract, then
checks a second synthetic revision batch through `candidate`, `reviewed`, and
`active_dry_run`. It verifies rollback snapshot coverage, manual review
reasons, administrator-only active dry-run, old active preservation, and no
production history rewrite.

K006 knowledge asset health dashboard contract:

```powershell
.\tools\run-k006-knowledge-asset-health-dashboard-contract.ps1
```

This checks the Web UI for an administrator-facing, read-only knowledge asset
health dashboard covering active assets, candidate assets, pending mappings,
migrations, blockers, and evidence summaries. It also verifies that the panel
does not expose active switch, migration apply, or C002R revision apply actions.

F001 assessment model contract:

```powershell
.\tools\run-f001-assessment-model-contract.ps1
```

This validates the draft/test student, class group, assessment, and enrollment
model. It inserts only synthetic fixtures inside a rolled-back transaction,
checks privacy/production constraints, and ensures no student-facing endpoint is
exposed.

C002 source material admission guard:

```powershell
.\tools\run-c002-source-material-guard.ps1
```

This validates the source material manifest template and ensures real textbook,
curriculum standard, and local exam files stay outside git.

Backup:

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\backup.ps1
```

Verify backup:

```powershell
.\tools\verify-backup.ps1 -ManifestPath 'D:\KQG_Backups\<timestamp>\manifest.json'
```

G002 storage dashboard and cache cleanup contract:

```powershell
.\tools\run-g002-storage-cleanup-contract.ps1
```

This starts the API with synthetic configured roots, checks the admin storage
summary and cache cleanup endpoints, verifies the Web dashboard markers, and
confirms cleanup only deletes old files under the configured cache root.

O005 capacity and cost health dashboard contract:

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\run-o005-capacity-cost-health-dashboard-contract.ps1
```

This aggregates G002 storage/cache signals, D002 AI job cost signals, and
admin dashboard UI contracts (including failed-task signal), then writes
`docs/evidence/o005-capacity-cost-health-dashboard-report.json`.

G003 WinPE emergency copy media contract:

```powershell
.\tools\run-g003-winpe-emergency-copy-contract.ps1
```

This generates draft/test emergency copy scripts under
`tmp/g003-winpe-recovery-media`, verifies the generated scripts use copy-only
Robocopy behavior, and writes `docs/evidence/g003-winpe-emergency-copy-report.json`.

G004 pgpass installer credential dry-run:

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\run-g004-pgpass-installer-dry-run.ps1
```

This uses a temporary `APPDATA` root, writes a temporary PostgreSQL
`pgpass.conf`, tightens ACLs, clears the process-level `PGPASSWORD`, verifies
`psql -w`, deletes the temporary credential file, and writes
`docs/evidence/g004-pgpass-installer-dry-run-report.json`. It does not modify
the real user profile pgpass file and does not log the password.

O007 EF migration bundle and upgrade drill contract:

```powershell
.\tools\run-o007-ef-migration-bundle-upgrade-contract.ps1
```

This restores `dotnet-ef`, builds `efbundle.exe`, stages a release-like
migrations package, executes bundle migration with explicit connection string,
then chains backup/verify and isolated restore drill evidence. It validates the
upgrade path without requiring source-tree execution at migration runtime.

O004B role authorization and audit closure contract:

```powershell
.\tools\run-o004b-role-audit-closure-contract.ps1
```

This validates fail-closed role separation on guarded backend endpoints:
`teacher` blocked, `group_lead` read-only on `/api/admin/*`, `admin` required for
high-risk writes and `/internal/ai/*`. It also verifies structured audit logs
for high-risk operations with operator/time/object/result/rollback-reference
fields.

O006 offline emergency runbook and tabletop contract:

```powershell
.\tools\run-o006-offline-emergency-runbook-tabletop-contract.ps1
```

This validates the offline emergency runbook chain by combining: G003 recovery
media generation, backup+verify evidence, `restore.ps1` dry-run, and a 3-case
admin tabletop drill (unbootable Windows, manifest mismatch, restore failure)
with explicit fallback and rollback actions.

NS1306 agent tool orchestration boundary:

```powershell
.\tools\run-ns1306-agent-tool-orchestration-contract.ps1
```

This locks the allowlisted `tool_orchestration_agent` surface for NS13. It
reads `configs/agent-tool-orchestration.allowlist.json`, verifies that every
allowlisted tool/runbook exists, that every allowlisted tool stays read-only or
dry-run, and that high-risk scripts remain blocked by default. It also checks
the `NS1306` rows in `tasks/backlog.csv`, `tasks/non-site-implementation-plan.csv`,
and `tasks/automation-first-contract.csv`, then writes
`docs/evidence/20260606-ns1306-agent-tool-orchestration.json`.

NS1307 golden / visual / LLM security gate:

```powershell
.\tools\run-ns1307-golden-visual-llm-security-gate.ps1
```

This combines the existing golden import evidence (`S004A`, `J001-J006`), the
deterministic visual surrogate boundary (`NS906`), and the LLM no-active-write
security gate (`L007`, `C002Q0`, `C002Q`) into one NS13 runtime gate. It does
not call external AI and does not enable production writes. It writes
`docs/evidence/20260606-ns1307-golden-visual-llm-security.json`.

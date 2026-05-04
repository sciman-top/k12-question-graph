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
It starts temporary
API processes for API smoke steps, so `PGPASSWORD` must match the local PostgreSQL
password.

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

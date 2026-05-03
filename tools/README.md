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

The gate also covers `b001 duplicate upload smoke`, `b002 adapter contract smoke`,
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
`e004 paper export contract`.
It starts temporary
API processes for API smoke steps, so `PGPASSWORD` must match the local PostgreSQL
password.

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

C002 real source material import:

```powershell
.\tools\import-c002-source-materials.ps1 -SourceRoot 'D:\CODE\k12-question-graph\广州中考'
```

The default mode is dry-run only and writes
`docs/evidence/c002-source-material-import-report.json`. It classifies local PDF
materials and reports the intended `sourceType`, `materialBatchKey`, and
source-use flags without writing the database.

Persistent import requires a valid local database password and should be run
after a backup check:

```powershell
$env:PGPASSWORD='<local-password>'
$env:KQG_CONNECTION_STRING='Host=127.0.0.1;Port=5432;Database=k12_question_graph;Username=postgres;Password=<local-password>'
.\tools\import-c002-source-materials.ps1 -SourceRoot 'D:\CODE\k12-question-graph\广州中考' -Apply -StartApi
```

This uploads the original files through the API into `SourceDocument/FileAsset`
evidence only. It must not mark C002 formal knowledge as complete and must not
activate candidate assets.

C002N source chunk cache:

```powershell
.\tools\run-c002n-source-chunk-cache.ps1
```

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

This reads the complete Guangzhou physics C003 candidate CSV package, samples
three questions per year for 2016-2025, checks exam stem, answer source,
year-report page anchor, exam point, knowledge point, curriculum, and textbook
references, then writes
`docs/evidence/c002s-formalization-precheck-report.json`. The current expected
state is `blocked`: sample evidence passes, but 210 year-report page/metric
quality issues remain open, so production activation must stay blocked.

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

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
`c002 junior physics draft bootstrap guard`, and
`d001 model router draft-test contract`.
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

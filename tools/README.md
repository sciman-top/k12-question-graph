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
`c001 knowledge ontology contract`, and `c002 junior physics draft bootstrap guard`.
It starts temporary
API processes for API smoke steps, so `PGPASSWORD` must match the local PostgreSQL
password.

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

C002 junior physics draft bootstrap guard:

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\run-c002-seed-validation.ps1
```

This is not the formal C002 completion gate. It only keeps the non-authoritative
draft bootstrap data idempotent and marked as `draft` until teachers import
textbooks, curriculum standards, and recent local exam papers for source-derived
review.

Backup:

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\backup.ps1
```

Verify backup:

```powershell
.\tools\verify-backup.ps1 -ManifestPath 'D:\KQG_Backups\<timestamp>\manifest.json'
```

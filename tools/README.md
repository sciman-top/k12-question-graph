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

Backup:

```powershell
$env:PGPASSWORD='<local-password>'
.\tools\backup.ps1
```

Verify backup:

```powershell
.\tools\verify-backup.ps1 -ManifestPath 'D:\KQG_Backups\<timestamp>\manifest.json'
```

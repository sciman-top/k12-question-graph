# workers/document

Target home for the Python document adapter placeholder created by `A007` and
extended by `B002`.

Contract smoke:

```powershell
$workerDir = 'D:\KQG_Data\file_store\gate'
New-Item -ItemType Directory -Path $workerDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $workerDir 'b002-smoke.txt') -Value 'adapter contract smoke' -Encoding UTF8
python workers/document/worker.py --job-id b002 --relative-path gate/b002-smoke.txt --file-root D:\KQG_Data\file_store
```

The placeholder returns stable internal JSON with `DocumentModel`, `PageModel`,
`LayoutBlock`, and `AdapterDiagnostic`. It does not run Docling, OpenXML, or
PaddleOCR yet.

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

The worker returns stable internal JSON with `DocumentModel`, `PageModel`,
`LayoutBlock`, and `AdapterDiagnostic`.

Local OCR dependency for scanned PDF/image input:

```powershell
python -m pip install -r workers/document/requirements.txt
```

Current adapter order:

1. `.docx`: OpenXML text/table/image/formula blocks.
2. text PDF: local `pdftotext` layout extraction.
3. scanned PDF: `pdftoppm` page rendering plus local `rapidocr_onnxruntime`.
4. scanned image: local `rapidocr_onnxruntime`.
5. missing/failed OCR engine: fail-closed `pending_review` takeover block.

Each RapidOCR image/page call has a worker-local 60-second deadline. A timeout
discards partial OCR for that document and routes it to the same
`pending_review` takeover path; the API process timeout remains an outer guard,
not a prerequisite for direct worker safety.

Formula recognition for scanned/image-only formulas is not implemented here yet;
formula-heavy image blocks must stay in teacher review until a dedicated formula
adapter is integrated. OMML formulas from `.docx` are captured verbatim as raw
Open XML: `reviewStatus: verified` and `confidence` describe source capture only,
`conversionStatus: pending_conversion` states that `latex`/`mathml` are `null`
until a conversion adapter exists, the plain-text stand-in lives in `text`, and
rendering must fall back to the OMML payload.

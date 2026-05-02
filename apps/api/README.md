# apps/api

ASP.NET Core API created by `A002`.

Run:

```powershell
$env:KQG_CONNECTION_STRING='Host=127.0.0.1;Port=5432;Database=k12_question_graph;Username=postgres;Password=<local-password>'
dotnet run --project apps/api
```

Health check:

```powershell
Invoke-RestMethod http://localhost:5275/health
Invoke-RestMethod http://localhost:5275/health/db
Invoke-RestMethod http://localhost:5275/health/ready
```

Upload smoke:

```powershell
$sample = Join-Path $env:TEMP 'kqg-upload-smoke.txt'
Set-Content -LiteralPath $sample -Value 'upload smoke' -Encoding UTF8
curl.exe -F "file=@$sample;type=text/plain" `
  -F "sourceType=school_paper" `
  -F "sourceTitle=校本物理样卷" `
  -F "ownerScope=school" `
  -F "licenseOrPermission=internal_authorized" `
  -F "sharingAllowed=true" `
  -F "containsStudentPii=false" `
  -F "anonymizationStatus=not_applicable" `
  http://localhost:5275/files
```

`/files` returns `isDuplicate`, `duplicateOfFileAssetId`, and `sourceDocument`.
Unknown sources and non-anonymized student PII are not shareable and are not eligible for external AI.

Import job smoke:

```powershell
$created = curl.exe -s -F "file=@$sample;type=text/plain" http://localhost:5275/imports | ConvertFrom-Json
Invoke-RestMethod -Method Post -Uri "http://localhost:5275/imports/$($created.id)/status" -ContentType 'application/json' -Body '{"status":"running","lockedBy":"smoke"}'
Invoke-RestMethod -Method Post -Uri "http://localhost:5275/imports/$($created.id)/status" -ContentType 'application/json' -Body '{"status":"succeeded"}'
```

Document worker smoke:

```powershell
$created = curl.exe -s -F "file=@$sample;type=text/plain" http://localhost:5275/imports | ConvertFrom-Json
Invoke-RestMethod -Method Post -Uri "http://localhost:5275/imports/$($created.id)/worker-smoke"
Invoke-RestMethod -Method Post -Uri "http://localhost:5275/imports/$($created.id)/worker-smoke?simulateFailure=true"
```

Source preview smoke:

```powershell
$uploaded = curl.exe -s -F "file=@$sample;type=text/plain" -F "sourceType=school_paper" http://localhost:5275/files | ConvertFrom-Json
$screenshot = 'previews/sample/page-1.txt'
New-Item -ItemType Directory -Path 'D:\KQG_Data\file_store\previews\sample' -Force | Out-Null
Set-Content -LiteralPath 'D:\KQG_Data\file_store\previews\sample\page-1.txt' -Value 'preview placeholder' -Encoding UTF8
Invoke-RestMethod -Method Post -Uri "http://localhost:5275/source-documents/$($uploaded.sourceDocument.id)/regions" -ContentType 'application/json' -Body (@{
  pageNumber = 1
  x = 10
  y = 15
  width = 50
  height = 30
  coordinateUnit = 'percent'
  screenshotRelativePath = $screenshot
  regionType = 'preview'
} | ConvertTo-Json)
Invoke-RestMethod "http://localhost:5275/source-documents/$($uploaded.sourceDocument.id)/preview"
```

Question save smoke:

```powershell
$question = @{
  subject = 'physics'
  stage = 'junior_middle_school'
  questionType = 'single_choice'
  blocks = @(
    @{ blockType = 'text'; sortOrder = 0; content = @{ text = '题干' }; sourceRegionId = '<source-region-id>' },
    @{ blockType = 'formula'; sortOrder = 1; content = @{ latex = 'F=ma' }; sourceRegionId = '<source-region-id>' },
    @{ blockType = 'answer'; sortOrder = 2; content = @{ answer = 'B' }; sourceRegionId = '<source-region-id>' },
    @{ blockType = 'solution'; sortOrder = 3; content = @{ text = '解析' }; sourceRegionId = '<source-region-id>' }
  )
  assets = @(
    @{ fileAssetId = '<file-asset-id>'; sourceRegionId = '<source-region-id>'; assetType = 'image'; purpose = 'question_figure'; metadata = @{ label = '题图' } }
  )
  answer = @{ value = 'B' }
  solution = @{ text = '解析' }
} | ConvertTo-Json -Depth 8
Invoke-RestMethod -Method Post -Uri 'http://localhost:5275/questions' -ContentType 'application/json' -Body $question
```

Question source review:

```powershell
Invoke-RestMethod 'http://localhost:5275/questions/<question-id>/sources'
```

If a referenced SourceRegion screenshot is missing, the API returns `409` with
`question_source_screenshot_missing`.

The API reads data, file store, backup, and log roots from the `KqgPaths` configuration section instead of relying on the current working directory.

Database migrations:

```powershell
dotnet tool restore
$env:KQG_CONNECTION_STRING='Host=127.0.0.1;Port=5432;Database=k12_question_graph;Username=postgres;Password=<local-password>'
dotnet tool run dotnet-ef database update --project apps/api/K12QuestionGraph.Api.csproj --startup-project apps/api/K12QuestionGraph.Api.csproj
```

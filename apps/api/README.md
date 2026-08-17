# apps/api

ASP.NET Core API created by `A002`.

Run:

```powershell
$env:KQG_CONNECTION_STRING='Host=127.0.0.1;Port=5432;Database=k12_question_graph;Username=postgres;Password=<local-password>'
$env:AdminInternalGuard__ApiKey='<random-local-admin-key>'
dotnet run --project apps/api
```

除公开的 `/health` 外，动态 API 默认需要认证。本地脚本可使用服务端内部密钥头；浏览器通过 `/auth/session` 建立 HttpOnly cookie，会话身份由服务端配置产生，不能由浏览器自报角色。远程登录必须使用 HTTPS。

```powershell
$headers = @{ 'X-KQG-Admin-Key' = $env:AdminInternalGuard__ApiKey }
```

Health check:

```powershell
Invoke-RestMethod http://localhost:5275/health
Invoke-RestMethod http://localhost:5275/health/details -Headers $headers
Invoke-RestMethod http://localhost:5275/health/db -Headers $headers
Invoke-RestMethod http://localhost:5275/health/ready -Headers $headers
```

Upload smoke:

```powershell
$sample = Resolve-Path 'guangzhou-physics-full-research-package-2016-2025/c003-guangzhou-physics-full-teacher-brief-2016-2025.pdf'
curl.exe -H "X-KQG-Admin-Key: $env:AdminInternalGuard__ApiKey" -F "file=@$sample;type=application/pdf" `
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
上传仅接受 PDF、DOCX、PNG、JPEG、BMP、TIFF；扩展名、MIME 和文件签名/容器结构必须一致，否则返回 `415`。

Import job smoke:

```powershell
$created = curl.exe -s -H "X-KQG-Admin-Key: $env:AdminInternalGuard__ApiKey" -F "file=@$sample;type=application/pdf" http://localhost:5275/imports | ConvertFrom-Json
Invoke-RestMethod -Method Post -Uri "http://localhost:5275/imports/$($created.id)/status" -Headers $headers -ContentType 'application/json' -Body '{"status":"running","lockedBy":"smoke"}'
Invoke-RestMethod -Method Post -Uri "http://localhost:5275/imports/$($created.id)/status" -Headers $headers -ContentType 'application/json' -Body '{"status":"succeeded","lockedBy":"smoke"}'
```

Document worker smoke:

```powershell
$created = curl.exe -s -H "X-KQG-Admin-Key: $env:AdminInternalGuard__ApiKey" -F "file=@$sample;type=application/pdf" http://localhost:5275/imports | ConvertFrom-Json
Invoke-RestMethod -Method Post -Uri "http://localhost:5275/imports/$($created.id)/worker-smoke" -Headers $headers
```

Published Windows Service package note:

- Production `appsettings.json` uses `PythonWorker.DocumentWorkerScript=worker\document\worker.py` (package-local path).
- Development `appsettings.Development.json` overrides it to `..\..\workers\document\worker.py` for repo-local `dotnet run`.

Source preview smoke:

```powershell
$uploaded = curl.exe -s -H "X-KQG-Admin-Key: $env:AdminInternalGuard__ApiKey" -F "file=@$sample;type=application/pdf" -F "sourceType=school_paper" http://localhost:5275/files | ConvertFrom-Json
$screenshot = 'previews/sample/page-1.txt'
New-Item -ItemType Directory -Path 'D:\KQG_Data\file_store\previews\sample' -Force | Out-Null
Set-Content -LiteralPath 'D:\KQG_Data\file_store\previews\sample\page-1.txt' -Value 'preview placeholder' -Encoding UTF8
Invoke-RestMethod -Method Post -Uri "http://localhost:5275/source-documents/$($uploaded.sourceDocument.id)/regions" -Headers $headers -ContentType 'application/json' -Body (@{
  pageNumber = 1
  x = 10
  y = 15
  width = 50
  height = 30
  coordinateUnit = 'percent'
  screenshotRelativePath = $screenshot
  regionType = 'preview'
} | ConvertTo-Json)
Invoke-RestMethod "http://localhost:5275/source-documents/$($uploaded.sourceDocument.id)/preview" -Headers $headers
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
Invoke-RestMethod -Method Post -Uri 'http://localhost:5275/questions' -Headers $headers -ContentType 'application/json' -Body $question
```

Question source review:

```powershell
Invoke-RestMethod 'http://localhost:5275/questions/<question-id>/sources' -Headers $headers
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

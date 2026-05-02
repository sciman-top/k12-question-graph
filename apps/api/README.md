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
curl.exe -F "file=@$sample;type=text/plain" http://localhost:5275/files
```

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

The API reads data, file store, backup, and log roots from the `KqgPaths` configuration section instead of relying on the current working directory.

Database migrations:

```powershell
dotnet tool restore
$env:KQG_CONNECTION_STRING='Host=127.0.0.1;Port=5432;Database=k12_question_graph;Username=postgres;Password=<local-password>'
dotnet tool run dotnet-ef database update --project apps/api/K12QuestionGraph.Api.csproj --startup-project apps/api/K12QuestionGraph.Api.csproj
```

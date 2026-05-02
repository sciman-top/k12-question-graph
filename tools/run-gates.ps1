param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$results = New-Object System.Collections.Generic.List[object]

function Invoke-GateStep([string] $Name, [scriptblock] $Script) {
    $started = Get-Date
    try {
        & $Script
        $results.Add([ordered]@{
            name = $Name
            status = 'pass'
            durationMs = [int]((Get-Date) - $started).TotalMilliseconds
        })
    }
    catch {
        $results.Add([ordered]@{
            name = $Name
            status = 'fail'
            durationMs = [int]((Get-Date) - $started).TotalMilliseconds
            error = $_.Exception.Message
        })
        throw
    }
}

Push-Location $repoRoot
try {
    Invoke-GateStep 'backend build' {
        dotnet build apps\api\K12QuestionGraph.Api.csproj | Write-Host
        if ($LASTEXITCODE -ne 0) { throw "dotnet build failed" }
    }

    Invoke-GateStep 'frontend build' {
        Push-Location apps\web
        try {
            npm run build | Write-Host
            if ($LASTEXITCODE -ne 0) { throw "npm run build failed" }
        }
        finally {
            Pop-Location
        }
    }

    Invoke-GateStep 'frontend lint' {
        Push-Location apps\web
        try {
            npm run lint | Write-Host
            if ($LASTEXITCODE -ne 0) { throw "npm run lint failed" }
        }
        finally {
            Pop-Location
        }
    }

    Invoke-GateStep 'b004 manual review ui contract' {
        $app = Get-Content -LiteralPath 'apps\web\src\App.tsx' -Raw
        foreach ($pattern in @(
            'data-flow="manual-review"',
            'data-action="merge"',
            'data-action="split"',
            'data-action="associate"',
            'data-action="undo"',
            '修订记录'
        )) {
            if (-not $app.Contains($pattern)) {
                throw "missing B004 UI contract marker: $pattern"
            }
        }
    }

    Invoke-GateStep 'b004a failure takeover ui contract' {
        $app = Get-Content -LiteralPath 'apps\web\src\App.tsx' -Raw
        foreach ($pattern in @(
            'data-flow="failure-takeover"',
            'data-action="manual-box"',
            'data-action="takeover-split"',
            'data-action="takeover-merge"',
            'data-action="skip-page"',
            'data-action="rerun-adapter"',
            'adapter_failed'
        )) {
            if (-not $app.Contains($pattern)) {
                throw "missing B004A UI contract marker: $pattern"
            }
        }
    }

    Invoke-GateStep 'worker smoke' {
        $workerDir = Join-Path $FileStoreRoot 'gate'
        New-Item -ItemType Directory -Path $workerDir -Force | Out-Null
        $workerFile = Join-Path $workerDir 'worker-smoke.txt'
        Set-Content -LiteralPath $workerFile -Value 'worker smoke' -Encoding UTF8
        python workers\document\worker.py --job-id gate --relative-path gate/worker-smoke.txt --file-root $FileStoreRoot | Write-Host
        if ($LASTEXITCODE -ne 0) { throw "worker smoke failed" }
    }

    Invoke-GateStep 'b002 adapter contract smoke' {
        $workerDir = Join-Path $FileStoreRoot 'gate'
        New-Item -ItemType Directory -Path $workerDir -Force | Out-Null
        $workerFile = Join-Path $workerDir 'b002-adapter-contract.txt'
        Set-Content -LiteralPath $workerFile -Value 'adapter contract smoke' -Encoding UTF8
        $json = python workers\document\worker.py --job-id b002-gate --relative-path gate/b002-adapter-contract.txt --file-root $FileStoreRoot | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) { throw "b002 adapter contract worker failed" }
        if ($json.documentModel.schemaVersion -ne 'document-model.v0.1') { throw "missing DocumentModel schemaVersion" }
        if ($json.documentModel.pages.Count -lt 1) { throw "missing PageModel" }
        if ($json.documentModel.pages[0].layoutBlocks.Count -lt 1) { throw "missing LayoutBlock" }
        if ($json.adapterDiagnostics.Count -lt 1) { throw "missing AdapterDiagnostic" }
        if ([string]::IsNullOrWhiteSpace($json.adapterDiagnostics[0].inputSha256)) { throw "missing input hash" }
        if ([string]::IsNullOrWhiteSpace($json.adapterDiagnostics[0].outputSha256)) { throw "missing output hash" }
    }

    Invoke-GateStep 'doc schema config csv' {
        python -c "import csv, json, pathlib, yaml; rows=list(csv.DictReader(open('tasks/backlog.csv', encoding='utf-8-sig'))); [json.loads(p.read_text(encoding='utf-8')) for p in pathlib.Path('schemas').rglob('*.json')]; [yaml.safe_load(p.read_text(encoding='utf-8')) for p in pathlib.Path('configs').rglob('*.yaml')]; print('doc gates ok', len(rows))" | Write-Host
        if ($LASTEXITCODE -ne 0) { throw "doc gates failed" }
    }

    Invoke-GateStep 'roadmap dependency guard' {
        .\tools\run-roadmap-guard.ps1 | Write-Host
    }

    Invoke-GateStep 'c002 source material admission guard' {
        .\tools\run-c002-source-material-guard.ps1 | Write-Host
    }

    Invoke-GateStep 'database smoke' {
        $psql = Join-Path $PgBin 'psql.exe'
        & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -c "select count(*) from information_schema.tables where table_schema='public';" | Write-Host
        if ($LASTEXITCODE -ne 0) { throw "database smoke failed" }
    }

    Invoke-GateStep 'c001 knowledge ontology contract' {
        .\tools\run-c001-contract.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
    }

    Invoke-GateStep 'c002 junior physics draft bootstrap guard' {
        .\tools\run-c002-seed-validation.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
    }

    Invoke-GateStep 'b001 duplicate upload smoke' {
        if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
            throw "DatabasePassword or PGPASSWORD is required for API upload smoke"
        }

        $port = 5282
        $apiUrl = "http://127.0.0.1:$port"
        $logOut = Join-Path $repoRoot 'docs\evidence\b001-gate-api.out.log'
        $logErr = Join-Path $repoRoot 'docs\evidence\b001-gate-api.err.log'
        $previousConnectionString = $env:KQG_CONNECTION_STRING
        $env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
        $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\api\K12QuestionGraph.Api.csproj','--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr
        try {
            $ready = $false
            for ($i = 0; $i -lt 30; $i++) {
                try {
                    $health = Invoke-RestMethod -Uri "$apiUrl/health/ready" -TimeoutSec 2
                    if ($health.status -eq 'ok') {
                        $ready = $true
                        break
                    }
                }
                catch {
                    Start-Sleep -Seconds 1
                }
            }
            if (-not $ready) { throw "API did not become ready on $apiUrl" }

            $sample = Join-Path $env:TEMP 'kqg-b001-gate-upload.txt'
            Set-Content -LiteralPath $sample -Value "B001 duplicate upload gate sample $([Guid]::NewGuid())" -Encoding UTF8

            $first = curl.exe -s -F "file=@$sample;filename=physics-paper.docx" -F "sourceType=school_paper" -F "sourceTitle=Gate Source" -F "ownerScope=school" -F "licenseOrPermission=internal_authorized" -F "sharingAllowed=true" -F "containsStudentPii=false" -F "anonymizationStatus=not_applicable" "$apiUrl/files" | ConvertFrom-Json
            $second = curl.exe -s -F "file=@$sample;filename=renamed-paper.pdf" -F "sourceType=unknown" -F "sourceTitle=Unknown Duplicate" -F "ownerScope=teacher_private" -F "licenseOrPermission=unknown" -F "sharingAllowed=true" -F "containsStudentPii=true" -F "anonymizationStatus=none" "$apiUrl/files" | ConvertFrom-Json

            if ($first.isDuplicate) { throw "first upload unexpectedly marked duplicate" }
            if (-not $second.isDuplicate) { throw "second upload was not marked duplicate" }
            if ($first.id -ne $second.id) { throw "duplicate upload returned a different file asset id" }
            if ($second.sourceDocument.sharingAllowed) { throw "unknown PII source remained shareable" }
            if ($second.sourceDocument.externalAiAllowed) { throw "unknown PII source remained external-AI eligible" }

            $psql = Join-Path $PgBin 'psql.exe'
            $rowCount = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -c "select count(*) from source_documents where file_asset_id = '$($first.id)';"
            if ($LASTEXITCODE -ne 0) { throw "source document query failed" }
            if ([int]$rowCount -lt 2) { throw "expected at least two source document rows for duplicate upload" }
        }
        finally {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $env:KQG_CONNECTION_STRING = $previousConnectionString
        }
    }

    Invoke-GateStep 'b003 source preview smoke' {
        if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
            throw "DatabasePassword or PGPASSWORD is required for API source preview smoke"
        }

        $port = 5283
        $apiUrl = "http://127.0.0.1:$port"
        $logOut = Join-Path $repoRoot 'docs\evidence\b003-gate-api.out.log'
        $logErr = Join-Path $repoRoot 'docs\evidence\b003-gate-api.err.log'
        $previousConnectionString = $env:KQG_CONNECTION_STRING
        $env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
        $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\api\K12QuestionGraph.Api.csproj','--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr
        try {
            $ready = $false
            for ($i = 0; $i -lt 30; $i++) {
                try {
                    $health = Invoke-RestMethod -Uri "$apiUrl/health/ready" -TimeoutSec 2
                    if ($health.status -eq 'ok') {
                        $ready = $true
                        break
                    }
                }
                catch {
                    Start-Sleep -Seconds 1
                }
            }
            if (-not $ready) { throw "API did not become ready on $apiUrl" }

            $sample = Join-Path $env:TEMP 'kqg-b003-gate-upload.txt'
            Set-Content -LiteralPath $sample -Value "B003 source preview gate sample $([Guid]::NewGuid())" -Encoding UTF8
            $upload = curl.exe -s -F "file=@$sample;filename=preview-source.txt" -F "sourceType=school_paper" -F "sourceTitle=Preview Source" -F "ownerScope=school" -F "licenseOrPermission=internal_authorized" -F "sharingAllowed=true" -F "containsStudentPii=false" -F "anonymizationStatus=not_applicable" "$apiUrl/files" | ConvertFrom-Json
            $sourceDocumentId = $upload.sourceDocument.id
            if ([string]::IsNullOrWhiteSpace($sourceDocumentId)) { throw "upload did not return sourceDocument.id" }

            $screenshotRelativePath = "previews/$sourceDocumentId/page-1.txt"
            $screenshotPath = Join-Path $FileStoreRoot ($screenshotRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            New-Item -ItemType Directory -Path (Split-Path -Parent $screenshotPath) -Force | Out-Null
            Set-Content -LiteralPath $screenshotPath -Value 'page preview placeholder' -Encoding UTF8

            $body = [ordered]@{
                pageNumber = 1
                x = 10
                y = 15
                width = 50
                height = 30
                coordinateUnit = 'percent'
                screenshotRelativePath = $screenshotRelativePath
                regionType = 'preview'
            } | ConvertTo-Json
            $region = Invoke-RestMethod -Method Post -Uri "$apiUrl/source-documents/$sourceDocumentId/regions" -ContentType 'application/json' -Body $body
            $preview = Invoke-RestMethod -Method Get -Uri "$apiUrl/source-documents/$sourceDocumentId/preview"

            if ($region.pageNumber -ne 1) { throw "region page number mismatch" }
            if ($region.coordinateUnit -ne 'percent') { throw "region coordinate unit mismatch" }
            if ($region.screenshotRelativePath -ne $screenshotRelativePath) { throw "region screenshot path mismatch" }
            if ($preview.pages.Count -lt 1) { throw "preview did not return any page" }
            if ($preview.pages[0].pageNumber -ne 1) { throw "preview page number mismatch" }
            if ($preview.pages[0].regions.Count -lt 1) { throw "preview did not return source region" }
        }
        finally {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $env:KQG_CONNECTION_STRING = $previousConnectionString
        }
    }

    Invoke-GateStep 'b005 save question api smoke' {
        if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
            throw "DatabasePassword or PGPASSWORD is required for API question save smoke"
        }

        $port = 5284
        $apiUrl = "http://127.0.0.1:$port"
        $logOut = Join-Path $repoRoot 'docs\evidence\b005-gate-api.out.log'
        $logErr = Join-Path $repoRoot 'docs\evidence\b005-gate-api.err.log'
        $previousConnectionString = $env:KQG_CONNECTION_STRING
        $env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
        $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\api\K12QuestionGraph.Api.csproj','--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr
        try {
            $ready = $false
            for ($i = 0; $i -lt 30; $i++) {
                try {
                    $health = Invoke-RestMethod -Uri "$apiUrl/health/ready" -TimeoutSec 2
                    if ($health.status -eq 'ok') {
                        $ready = $true
                        break
                    }
                }
                catch {
                    Start-Sleep -Seconds 1
                }
            }
            if (-not $ready) { throw "API did not become ready on $apiUrl" }

            $sample = Join-Path $env:TEMP 'kqg-b005-gate-upload.txt'
            Set-Content -LiteralPath $sample -Value "B005 question save gate sample $([Guid]::NewGuid())" -Encoding UTF8
            $upload = curl.exe -s -F "file=@$sample;filename=question-asset.txt" -F "sourceType=school_paper" -F "sourceTitle=Question Save Source" -F "ownerScope=school" -F "licenseOrPermission=internal_authorized" -F "sharingAllowed=true" -F "containsStudentPii=false" -F "anonymizationStatus=not_applicable" "$apiUrl/files" | ConvertFrom-Json
            $sourceDocumentId = $upload.sourceDocument.id

            $regionBody = [ordered]@{
                pageNumber = 1
                x = 12
                y = 18
                width = 64
                height = 22
                coordinateUnit = 'percent'
                screenshotRelativePath = $null
                regionType = 'question'
            } | ConvertTo-Json
            $region = Invoke-RestMethod -Method Post -Uri "$apiUrl/source-documents/$sourceDocumentId/regions" -ContentType 'application/json' -Body $regionBody

            $questionBody = [ordered]@{
                subject = 'physics'
                stage = 'junior_middle_school'
                grade = 'grade_8'
                questionType = 'single_choice'
                defaultScore = 3
                status = 'draft'
                blocks = @(
                    [ordered]@{ blockType = 'text'; sortOrder = 0; content = [ordered]@{ text = '下列关于力的说法正确的是？' }; sourceRegionId = $region.id },
                    [ordered]@{ blockType = 'option'; sortOrder = 1; content = [ordered]@{ key = 'A'; text = '力可以脱离物体存在' }; sourceRegionId = $region.id },
                    [ordered]@{ blockType = 'formula'; sortOrder = 2; content = [ordered]@{ latex = 'F=ma' }; sourceRegionId = $region.id },
                    [ordered]@{ blockType = 'table'; sortOrder = 3; content = [ordered]@{ rows = @(@('物理量','单位'), @('力','N')) }; sourceRegionId = $region.id },
                    [ordered]@{ blockType = 'answer'; sortOrder = 4; content = [ordered]@{ answer = 'B' }; sourceRegionId = $region.id },
                    [ordered]@{ blockType = 'solution'; sortOrder = 5; content = [ordered]@{ text = '力是物体间的相互作用。' }; sourceRegionId = $region.id }
                )
                assets = @(
                    [ordered]@{ fileAssetId = $upload.id; sourceRegionId = $region.id; assetType = 'image'; purpose = 'question_figure'; metadata = [ordered]@{ label = '题图占位' } }
                )
                answer = [ordered]@{ value = 'B' }
                solution = [ordered]@{ text = '力不能脱离物体存在。' }
            } | ConvertTo-Json -Depth 8

            $created = Invoke-RestMethod -Method Post -Uri "$apiUrl/questions" -ContentType 'application/json' -Body $questionBody
            $loaded = Invoke-RestMethod -Method Get -Uri "$apiUrl/questions/$($created.id)"
            if ($loaded.blocks.Count -lt 6) { throw "question blocks were not saved" }
            if ($loaded.assets.Count -lt 1) { throw "question asset was not saved" }
            if (($loaded.blocks | Where-Object { $_.blockType -eq 'formula' }).Count -lt 1) { throw "formula block missing" }
            if (($loaded.blocks | Where-Object { $_.blockType -eq 'table' }).Count -lt 1) { throw "table block missing" }
            if (($loaded.blocks | Where-Object { $_.sourceRegionId -eq $region.id }).Count -lt 1) { throw "source region link missing" }
            if ($loaded.assets[0].fileAssetId -ne $upload.id) { throw "question asset file link mismatch" }
        }
        finally {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $env:KQG_CONNECTION_STRING = $previousConnectionString
        }
    }

    Invoke-GateStep 'b006 question source review smoke' {
        if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
            throw "DatabasePassword or PGPASSWORD is required for API question source smoke"
        }

        $port = 5285
        $apiUrl = "http://127.0.0.1:$port"
        $logOut = Join-Path $repoRoot 'docs\evidence\b006-gate-api.out.log'
        $logErr = Join-Path $repoRoot 'docs\evidence\b006-gate-api.err.log'
        $previousConnectionString = $env:KQG_CONNECTION_STRING
        $env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
        $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\api\K12QuestionGraph.Api.csproj','--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr
        try {
            $ready = $false
            for ($i = 0; $i -lt 30; $i++) {
                try {
                    $health = Invoke-RestMethod -Uri "$apiUrl/health/ready" -TimeoutSec 2
                    if ($health.status -eq 'ok') {
                        $ready = $true
                        break
                    }
                }
                catch {
                    Start-Sleep -Seconds 1
                }
            }
            if (-not $ready) { throw "API did not become ready on $apiUrl" }

            $sample = Join-Path $env:TEMP 'kqg-b006-gate-upload.txt'
            Set-Content -LiteralPath $sample -Value "B006 source review gate sample $([Guid]::NewGuid())" -Encoding UTF8
            $upload = curl.exe -s -F "file=@$sample;filename=source-review.txt" -F "sourceType=school_paper" -F "sourceTitle=Source Review Paper" -F "ownerScope=school" -F "licenseOrPermission=internal_authorized" -F "sharingAllowed=true" -F "containsStudentPii=false" -F "anonymizationStatus=not_applicable" "$apiUrl/files" | ConvertFrom-Json
            $sourceDocumentId = $upload.sourceDocument.id

            $screenshotRelativePath = "previews/$sourceDocumentId/question-source.txt"
            $screenshotPath = Join-Path $FileStoreRoot ($screenshotRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            New-Item -ItemType Directory -Path (Split-Path -Parent $screenshotPath) -Force | Out-Null
            Set-Content -LiteralPath $screenshotPath -Value 'question source preview placeholder' -Encoding UTF8

            $regionBody = [ordered]@{
                pageNumber = 2
                x = 8
                y = 11
                width = 70
                height = 25
                coordinateUnit = 'percent'
                screenshotRelativePath = $screenshotRelativePath
                regionType = 'question'
            } | ConvertTo-Json
            $region = Invoke-RestMethod -Method Post -Uri "$apiUrl/source-documents/$sourceDocumentId/regions" -ContentType 'application/json' -Body $regionBody

            $questionBody = [ordered]@{
                subject = 'physics'
                stage = 'junior_middle_school'
                questionType = 'short_answer'
                blocks = @(
                    [ordered]@{ blockType = 'text'; sortOrder = 0; content = [ordered]@{ text = '请说明惯性的含义。' }; sourceRegionId = $region.id },
                    [ordered]@{ blockType = 'answer'; sortOrder = 1; content = [ordered]@{ answer = '物体保持原有运动状态的性质。' }; sourceRegionId = $region.id }
                )
                assets = @()
                answer = [ordered]@{ value = '物体保持原有运动状态的性质。' }
                solution = [ordered]@{ text = '惯性是物体的固有属性。' }
            } | ConvertTo-Json -Depth 8
            $created = Invoke-RestMethod -Method Post -Uri "$apiUrl/questions" -ContentType 'application/json' -Body $questionBody
            $sources = Invoke-RestMethod -Method Get -Uri "$apiUrl/questions/$($created.id)/sources"
            if ($sources.sourceRegions.Count -lt 1) { throw "question source regions missing" }
            if ($sources.sourceRegions[0].pageNumber -ne 2) { throw "question source page number mismatch" }
            if ($sources.sourceRegions[0].screenshotRelativePath -ne $screenshotRelativePath) { throw "question source screenshot path mismatch" }

            Remove-Item -LiteralPath $screenshotPath -Force
            try {
                Invoke-RestMethod -Method Get -Uri "$apiUrl/questions/$($created.id)/sources" | Out-Null
                throw "missing screenshot did not fail"
            }
            catch {
                if ($_.Exception.Response.StatusCode.value__ -ne 409) {
                    throw
                }
            }
        }
        finally {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $env:KQG_CONNECTION_STRING = $previousConnectionString
        }
    }

    Invoke-GateStep 'b007 golden import regression' {
        .\tools\run-import-golden.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -FileStoreRoot $FileStoreRoot | Write-Host
    }

    Invoke-GateStep 'b008 p1 proxy scenario' {
        .\tools\run-p1-proxy-scenario.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -FileStoreRoot $FileStoreRoot | Write-Host
    }

    Invoke-GateStep 'backup verify' {
        $backup = .\tools\backup.ps1 -PgBin $PgBin -DatabaseName $DatabaseName -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabaseUser $DatabaseUser | ConvertFrom-Json
        .\tools\verify-backup.ps1 -ManifestPath $backup.manifest | Write-Host
    }

    [ordered]@{
        status = 'pass'
        steps = $results
    } | ConvertTo-Json -Depth 6
}
finally {
    Pop-Location
}

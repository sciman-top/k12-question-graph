param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [int] $Port = 5286
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
$samplesPath = Join-Path $repoRoot 'tests\golden-import\samples.json'
$samples = Get-Content -LiteralPath $samplesPath -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw "DatabasePassword or PGPASSWORD is required for golden import"
}

$apiUrl = "http://127.0.0.1:$Port"
$logOut = Join-Path $repoRoot 'docs\evidence\b007-golden-api.out.log'
$logErr = Join-Path $repoRoot 'docs\evidence\b007-golden-api.err.log'
$previousConnectionString = $env:KQG_CONNECTION_STRING
$env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"

Push-Location $repoRoot
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

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($sample in $samples) {
        $sampleFile = Join-Path $env:TEMP "kqg-golden-$($sample.id).txt"
        Set-Content -LiteralPath $sampleFile -Value $sample.content -Encoding UTF8

        $upload = curl.exe -s -F "file=@$sampleFile;filename=$($sample.id).txt" -F "sourceType=synthetic" -F "sourceTitle=$($sample.title)" -F "ownerScope=public" -F "licenseOrPermission=synthetic_regression" -F "sharingAllowed=true" -F "containsStudentPii=false" -F "anonymizationStatus=synthetic" "$apiUrl/files" | ConvertFrom-Json
        if ([string]::IsNullOrWhiteSpace($upload.sourceDocument.id)) {
            throw "sample $($sample.id) upload did not return source document"
        }

        $screenshotRelativePath = "golden/$($sample.id)/page-1.txt"
        $screenshotPath = Join-Path $FileStoreRoot ($screenshotRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $screenshotPath) -Force | Out-Null
        Set-Content -LiteralPath $screenshotPath -Value "preview for $($sample.id)" -Encoding UTF8

        $regionBody = [ordered]@{
            pageNumber = 1
            x = 5
            y = 8
            width = 80
            height = 28
            coordinateUnit = 'percent'
            screenshotRelativePath = $screenshotRelativePath
            regionType = 'golden_sample'
        } | ConvertTo-Json
        $region = Invoke-RestMethod -Method Post -Uri "$apiUrl/source-documents/$($upload.sourceDocument.id)/regions" -ContentType 'application/json' -Body $regionBody

        $blocks = New-Object System.Collections.Generic.List[object]
        $order = 0
        foreach ($blockType in $sample.blocks) {
            $content = switch ($blockType) {
                'formula' { [ordered]@{ latex = 'F=ma'; note = $sample.id } }
                'image' { [ordered]@{ label = 'synthetic image placeholder'; assetId = $upload.id } }
                'table' { [ordered]@{ rows = @(@('sample','type'), @($sample.id,$sample.questionType)) } }
                'option' { [ordered]@{ key = 'A'; text = 'synthetic option' } }
                'sub_question' { [ordered]@{ label = '1'; text = 'synthetic sub question' } }
                'answer' { [ordered]@{ answer = 'synthetic answer' } }
                'solution' { [ordered]@{ text = 'synthetic solution' } }
                default { [ordered]@{ text = "$($sample.title) stem" } }
            }
            $blocks.Add([ordered]@{
                blockType = $blockType
                sortOrder = $order
                content = $content
                sourceRegionId = $region.id
            })
            $order += 1
        }

        $questionBody = [ordered]@{
            subject = 'physics'
            stage = 'junior_middle_school'
            grade = 'golden'
            questionType = $sample.questionType
            defaultScore = 3
            status = 'draft'
            blocks = $blocks
            assets = @(
                [ordered]@{
                    fileAssetId = $upload.id
                    sourceRegionId = $region.id
                    assetType = $sample.assetType
                    purpose = 'golden_regression'
                    metadata = [ordered]@{ sampleId = $sample.id }
                }
            )
            answer = [ordered]@{ value = 'synthetic answer' }
            solution = [ordered]@{ text = 'synthetic solution' }
        } | ConvertTo-Json -Depth 10

        $question = Invoke-RestMethod -Method Post -Uri "$apiUrl/questions" -ContentType 'application/json' -Body $questionBody
        $sources = Invoke-RestMethod -Method Get -Uri "$apiUrl/questions/$($question.id)/sources"
        if ($question.blocks.Count -lt $sample.blocks.Count) { throw "sample $($sample.id) block count mismatch" }
        if ($question.assets.Count -lt 1) { throw "sample $($sample.id) asset missing" }
        if ($sources.sourceRegions.Count -lt 1) { throw "sample $($sample.id) source review missing" }

        $results.Add([ordered]@{
            id = $sample.id
            questionId = $question.id
            sourceDocumentId = $upload.sourceDocument.id
            sourceRegionId = $region.id
            blockCount = $question.blocks.Count
            assetCount = $question.assets.Count
        })
    }

    [ordered]@{
        status = 'pass'
        sampleCount = $results.Count
        samples = $results
    } | ConvertTo-Json -Depth 6
}
finally {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    $env:KQG_CONNECTION_STRING = $previousConnectionString
    Pop-Location
}

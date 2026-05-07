param(
    [string]$DatabaseHost = '127.0.0.1',
    [int]$DatabasePort = 5432,
    [string]$DatabaseName = 'k12_question_graph',
    [string]$DatabaseUser = 'postgres',
    [string]$DatabasePassword = $env:PGPASSWORD,
    [string]$FileStoreRoot = 'D:\KQG_Data\file_store'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required'
}

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { return $listener.LocalEndpoint.Port } finally { $listener.Stop() }
}

function Wait-ApiReady {
    param([int]$ProcessId, [string]$ApiUrl, [string]$LogErr)
    $deadline = (Get-Date).AddSeconds(45)
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) {
            if (Test-Path -LiteralPath $LogErr) {
                throw "API process exited early: $(Get-Content -LiteralPath $LogErr -Raw)"
            }
            throw 'API process exited early'
        }
        try {
            $health = Invoke-RestMethod -Method Get -Uri "$ApiUrl/health/ready"
            if ($health.status -eq 'ok') { return }
        } catch {}
        Start-Sleep -Milliseconds 500
    }
    throw 'API ready timeout'
}

$port = Get-FreeTcpPort
$apiUrl = "http://127.0.0.1:$port"
$logOut = Join-Path $repoRoot 'docs\evidence\s006c-smoke-api.out.log'
$logErr = Join-Path $repoRoot 'docs\evidence\s006c-smoke-api.err.log'
$previousConnectionString = $env:KQG_CONNECTION_STRING
$env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
$process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\api\K12QuestionGraph.Api.csproj','--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr

try {
    Wait-ApiReady -ProcessId $process.Id -ApiUrl $apiUrl -LogErr $logErr

    $sample = Join-Path $env:TEMP 'kqg-s006c-upload.txt'
    Set-Content -LiteralPath $sample -Value "S006C source review sample $([Guid]::NewGuid())" -Encoding UTF8
    $upload = curl.exe -s -F "file=@$sample;filename=s006c-source.txt" -F "sourceType=school_paper" -F "sourceTitle=S006C Source Review Paper" -F "ownerScope=school" -F "licenseOrPermission=internal_authorized" -F "sharingAllowed=true" -F "containsStudentPii=false" -F "anonymizationStatus=not_applicable" "$apiUrl/files" | ConvertFrom-Json
    $sourceDocumentId = $upload.sourceDocument.id

    $screenshotRelativePath = "previews/$sourceDocumentId/s006c-question-source.txt"
    $screenshotPath = Join-Path $FileStoreRoot ($screenshotRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    New-Item -ItemType Directory -Path (Split-Path -Parent $screenshotPath) -Force | Out-Null
    Set-Content -LiteralPath $screenshotPath -Value 's006c source preview placeholder' -Encoding UTF8

    $regionBody = [ordered]@{
        pageNumber = 3
        x = 6
        y = 10
        width = 74
        height = 20
        coordinateUnit = 'percent'
        screenshotRelativePath = $screenshotRelativePath
        regionType = 'question'
    } | ConvertTo-Json
    $region = Invoke-RestMethod -Method Post -Uri "$apiUrl/source-documents/$sourceDocumentId/regions" -ContentType 'application/json' -Body $regionBody

    $questionWithRegionBody = [ordered]@{
        subject = 'physics'
        stage = 'junior_middle_school'
        questionType = 'short_answer'
        blocks = @(
            [ordered]@{ blockType = 'text'; sortOrder = 0; content = [ordered]@{ text = '说明压强与受力面积的关系。' }; sourceRegionId = $region.id },
            [ordered]@{ blockType = 'answer'; sortOrder = 1; content = [ordered]@{ answer = '受力面积越小压强越大。' }; sourceRegionId = $region.id }
        )
        assets = @()
    } | ConvertTo-Json -Depth 8
    $savedWithRegion = Invoke-RestMethod -Method Post -Uri "$apiUrl/questions" -ContentType 'application/json' -Body $questionWithRegionBody

    $sourcesOk = Invoke-RestMethod -Method Get -Uri "$apiUrl/questions/$($savedWithRegion.id)/sources"
    if ($sourcesOk.sourceRegions.Count -lt 1) { throw 'S006C source review should contain at least one source region' }

    Remove-Item -LiteralPath $screenshotPath -Force
    $missingScreenshotStatus = 0
    try {
        Invoke-RestMethod -Method Get -Uri "$apiUrl/questions/$($savedWithRegion.id)/sources" | Out-Null
        throw 'S006C missing screenshot should fail with 409'
    } catch {
        $missingScreenshotStatus = $_.Exception.Response.StatusCode.value__
        if ($missingScreenshotStatus -ne 409) { throw }
    }

    $questionNoRegionBody = [ordered]@{
        subject = 'physics'
        stage = 'junior_middle_school'
        questionType = 'single_choice'
        blocks = @(
            [ordered]@{ blockType = 'text'; sortOrder = 0; content = [ordered]@{ text = '声音在真空中能传播吗？' }; sourceRegionId = $null }
        )
        assets = @()
    } | ConvertTo-Json -Depth 8
    $savedNoRegion = Invoke-RestMethod -Method Post -Uri "$apiUrl/questions" -ContentType 'application/json' -Body $questionNoRegionBody
    $sourcesNoRegion = Invoke-RestMethod -Method Get -Uri "$apiUrl/questions/$($savedNoRegion.id)/sources"
    if ($sourcesNoRegion.sourceRegions.Count -ne 0) { throw 'S006C no-region case should return empty source regions' }

    $notFoundStatus = 0
    try {
        $fakeQuestionId = [Guid]::NewGuid()
        Invoke-RestMethod -Method Get -Uri "$apiUrl/questions/$fakeQuestionId/sources" | Out-Null
        throw 'S006C not-found case should fail'
    } catch {
        $notFoundStatus = $_.Exception.Response.StatusCode.value__
        if ($notFoundStatus -ne 404) { throw }
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'S006C'
        checkedAt = (Get-Date).ToString('s')
        sourceReview = [ordered]@{
            questionId = $savedWithRegion.id
            sourceRegionCount = $sourcesOk.sourceRegions.Count
        }
        fallbackCases = [ordered]@{
            missingScreenshotStatus = $missingScreenshotStatus
            missingRegionCount = $sourcesNoRegion.sourceRegions.Count
            notFoundStatus = $notFoundStatus
        }
        conclusion = 'source review closure is available after save_question; missing screenshot, missing region, and inaccessible question fallback are explicit'
    }
    $reportPath = Join-Path $repoRoot 'docs\evidence\20260506-s006c-source-review-closure-smoke-report.json'
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    $env:KQG_CONNECTION_STRING = $previousConnectionString
}

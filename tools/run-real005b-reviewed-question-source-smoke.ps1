param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [int] $ApiPort = 0,
    [string] $ReportPath = '',
    [string] $MarkdownReportPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for REAL005B reviewed question source smoke'
}

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = ('docs/evidence/{0}-real005b-reviewed-question-source-smoke.json' -f (Get-Date -Format 'yyyyMMdd'))
}

if ([string]::IsNullOrWhiteSpace($MarkdownReportPath)) {
    $MarkdownReportPath = ('docs/evidence/{0}-real005b-reviewed-question-source-smoke.md' -f (Get-Date -Format 'yyyyMMdd'))
}

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { return $listener.LocalEndpoint.Port } finally { $listener.Stop() }
}

function Wait-ApiReady {
    param([int] $ProcessId, [string] $ApiUrl, [string] $LogErr)
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
        }
        catch {}
        Start-Sleep -Milliseconds 500
    }
    throw 'API ready timeout'
}

function Invoke-ScalarSql([string] $Sql) {
    $psql = 'C:\Program Files\PostgreSQL\17\bin\psql.exe'
    $output = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -F '|' -v ON_ERROR_STOP=1 -c $Sql
    if ($LASTEXITCODE -ne 0) {
        throw "SQL failed: $Sql"
    }
    return (($output | Out-String).Trim())
}

function Invoke-RowSql([string] $Sql) {
    $psql = 'C:\Program Files\PostgreSQL\17\bin\psql.exe'
    $output = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -F '|' -v ON_ERROR_STOP=1 -c $Sql
    if ($LASTEXITCODE -ne 0) {
        throw "SQL failed: $Sql"
    }
    return @((($output | Out-String) -split "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

$requestedApiPort = $ApiPort
if ($ApiPort -le 0) {
    $ApiPort = Get-FreeTcpPort
}
$apiUrl = "http://127.0.0.1:$ApiPort"
$logOut = Join-Path $repoRoot 'docs/evidence/real005b-reviewed-source-smoke-api.out.log'
$logErr = Join-Path $repoRoot 'docs/evidence/real005b-reviewed-source-smoke-api.err.log'
$previousConnectionString = $env:KQG_CONNECTION_STRING
$env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
$process = $null

try {
    Push-Location $repoRoot

    & pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-real005b-source-region-screenshots.ps1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'REAL005B screenshot evidence prerequisite failed'
    }

    & pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-real005b-reviewed-question-materialize.ps1 -Apply | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'REAL005B reviewed question materialize apply failed'
    }

    $process = Start-Process -FilePath dotnet -ArgumentList @(
        'run',
        '--project',
        'apps\api\K12QuestionGraph.Api.csproj',
        '-c',
        'Release',
        '--no-build',
        '--urls',
        $apiUrl
    ) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr

    Wait-ApiReady -ProcessId $process.Id -ApiUrl $apiUrl -LogErr $logErr

    $questionRows = Invoke-RowSql @"
select
  id::text || '|' ||
  coalesce(custom_fields->>'questionNo','') || '|' ||
  coalesce(custom_fields->>'sourceFile','')
from question_items
where coalesce(custom_fields->>'sourceWorkflowKey','') = 'guangzhou_2016_2025_reviewed_question_materialize_v1'
order by (custom_fields->>'questionNo')::int, id::text;
"@

    $samples = @()
    $missing = @()
    foreach ($row in $questionRows) {
        $parts = $row -split '\|', 3
        $questionId = $parts[0]
        $questionNo = [int]$parts[1]
        $sourceFile = $parts[2]

        $question = Invoke-RestMethod -Method Get -Uri "$apiUrl/questions/$questionId" -TimeoutSec 10
        $sources = Invoke-RestMethod -Method Get -Uri "$apiUrl/questions/$questionId/sources" -TimeoutSec 10
        $regions = @($sources.sourceRegions)
        $screenshotCount = @($regions | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.screenshotUrl) }).Count
        $pageScreenshotCount = @($regions | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.pageScreenshotUrl) }).Count
        $status = [string]$question.status

        if ($status -ne 'usable' -or $regions.Count -lt 2 -or $screenshotCount -lt 2 -or $pageScreenshotCount -lt 2) {
            $missing += [pscustomobject]@{
                questionId = $questionId
                questionNo = $questionNo
                sourceFile = $sourceFile
                status = $status
                regionCount = $regions.Count
                screenshotCount = $screenshotCount
                pageScreenshotCount = $pageScreenshotCount
            }
        }

        if ($samples.Count -lt 20) {
            $samples += [pscustomobject]@{
                questionId = $questionId
                questionNo = $questionNo
                sourceFile = $sourceFile
                status = $status
                regionCount = $regions.Count
                screenshotCount = $screenshotCount
                pageScreenshotCount = $pageScreenshotCount
            }
        }
    }

    if ($missing.Count -gt 0) {
        throw "REAL005B reviewed source smoke found missing question source coverage: $($missing | ConvertTo-Json -Compress)"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'REAL005B_REVIEWED_QUESTION_SOURCE_SMOKE'
        checkedAt = (Get-Date).ToString('s')
        requestedApiPort = $requestedApiPort
        resolvedApiPort = $ApiPort
        portFallbackApplied = ($requestedApiPort -ne $ApiPort)
        apiUrl = $apiUrl
        workflowKey = 'guangzhou_2016_2025_reviewed_question_materialize_v1'
        questionCount = $questionRows.Count
        usableQuestionCount = [int](Invoke-ScalarSql "select count(*) from question_items where coalesce(custom_fields->>'sourceWorkflowKey','') = 'guangzhou_2016_2025_reviewed_question_materialize_v1' and status = 'usable';")
        sourceRegionCount = [int](Invoke-ScalarSql "select count(*) from source_regions where region_type in ('real005b_review_question','real005b_review_answer');")
        reviewQueueCount = [int](Invoke-ScalarSql "select count(*) from review_queue_items where review_type = 'real005b_question_materialize';")
        sourceReviewPass = $true
        samples = $samples
        rollback = @(
            "delete from review_queue_items where review_type = 'real005b_question_materialize';",
            "delete from question_assets where question_item_id in (select id from question_items where custom_fields->>'sourceWorkflowKey' = 'guangzhou_2016_2025_reviewed_question_materialize_v1');",
            "delete from question_blocks where question_item_id in (select id from question_items where custom_fields->>'sourceWorkflowKey' = 'guangzhou_2016_2025_reviewed_question_materialize_v1');",
            "delete from source_regions where region_type in ('real005b_review_question','real005b_review_answer');",
            "delete from question_items where custom_fields->>'sourceWorkflowKey' = 'guangzhou_2016_2025_reviewed_question_materialize_v1';"
        )
        boundary = 'Repo-side API smoke only; this proves reviewed real questions are API-visible with source review payload, not onsite/manual closeout.'
    }

    $reportFullPath = Join-Path $repoRoot ($ReportPath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $markdownFullPath = Join-Path $repoRoot ($MarkdownReportPath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8

    @(
        '# REAL005B Reviewed Question Source Smoke',
        '',
        "- status: $($report.status)",
        "- question_count: $($report.questionCount)",
        "- usable_question_count: $($report.usableQuestionCount)",
        "- source_region_count: $($report.sourceRegionCount)",
        "- review_queue_count: $($report.reviewQueueCount)",
        '',
        '## Boundary',
        $report.boundary
    ) | Set-Content -LiteralPath $markdownFullPath -Encoding UTF8

    $report | ConvertTo-Json -Depth 10
}
finally {
    if ($null -ne $process) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    $env:KQG_CONNECTION_STRING = $previousConnectionString
    Pop-Location
}

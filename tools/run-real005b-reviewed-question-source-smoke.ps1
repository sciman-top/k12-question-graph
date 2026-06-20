param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $FileStoreRoot = 'tmp\real005b-runtime\data\file_store',
    [int] $ApiPort = 0,
    [switch] $AllowPartialReport,
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

function Resolve-Real005bSourceFileStoreRoot {
    param([string] $RepoRoot)

    $candidates = @(
        'D:\KQG_Data\file_store'
    )

    $debugBackupRoot = Join-Path $RepoRoot 'tmp\debug-backup'
    if (Test-Path -LiteralPath $debugBackupRoot) {
        $backupRoots = Get-ChildItem -LiteralPath $debugBackupRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
        foreach ($backupRoot in $backupRoots) {
            $candidates += (Join-Path $backupRoot.FullName 'file_store')
        }
    }

    foreach ($candidate in $candidates) {
        $originalRoot = Join-Path $candidate 'original'
        if (Test-Path -LiteralPath $originalRoot) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw 'No REAL005B source file store root with original PDFs was found'
}

function Initialize-Real005bRuntimeRoots {
    param(
        [string] $RepoRoot,
        [string] $RuntimeFileStoreRoot
    )

    $resolvedFileStoreRoot = if ([System.IO.Path]::IsPathRooted($RuntimeFileStoreRoot)) {
        [System.IO.Path]::GetFullPath($RuntimeFileStoreRoot)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $RuntimeFileStoreRoot))
    }

    $runtimeDataRoot = Split-Path -Parent $resolvedFileStoreRoot
    $runtimeRoot = Split-Path -Parent $runtimeDataRoot
    $runtimeBackupRoot = Join-Path $runtimeRoot 'backups'
    $runtimeLogsRoot = Join-Path $runtimeDataRoot 'logs'
    $runtimeCacheRoot = Join-Path $runtimeDataRoot 'cache'
    $sourceFileStoreRoot = Resolve-Real005bSourceFileStoreRoot -RepoRoot $RepoRoot
    $sourceOriginalRoot = Join-Path $sourceFileStoreRoot 'original'
    $runtimeOriginalRoot = Join-Path $resolvedFileStoreRoot 'original'

    foreach ($path in @($runtimeDataRoot, $resolvedFileStoreRoot, $runtimeBackupRoot, $runtimeLogsRoot, $runtimeCacheRoot)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $sourceOriginalRoot)) {
        throw "REAL005B source file store original root missing: $sourceOriginalRoot"
    }

    if (Test-Path -LiteralPath $runtimeOriginalRoot) {
        Remove-Item -LiteralPath $runtimeOriginalRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -ItemType Junction -Path $runtimeOriginalRoot -Target $sourceOriginalRoot | Out-Null

    return [pscustomobject]@{
        RuntimeRoot = $runtimeRoot
        DataRoot = $runtimeDataRoot
        FileStoreRoot = $resolvedFileStoreRoot
        BackupRoot = $runtimeBackupRoot
        LogsRoot = $runtimeLogsRoot
        CacheRoot = $runtimeCacheRoot
        SourceFileStoreRoot = $sourceFileStoreRoot
    }
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
$runtime = Initialize-Real005bRuntimeRoots -RepoRoot $repoRoot -RuntimeFileStoreRoot $FileStoreRoot
$runtimeFileStoreRoot = $runtime.FileStoreRoot
$runtimeDataRoot = $runtime.DataRoot
$runtimeBackupRoot = $runtime.BackupRoot
$runtimeLogsRoot = $runtime.LogsRoot
$runtimeCacheRoot = $runtime.CacheRoot
$previousConnectionString = $env:KQG_CONNECTION_STRING
$previousDataRoot = $env:KqgPaths__DataRoot
$previousFileStoreRoot = $env:KqgPaths__FileStoreRoot
$previousBackupRoot = $env:KqgPaths__BackupRoot
$previousLogsRoot = $env:KqgPaths__LogsRoot
$previousCacheRoot = $env:KqgPaths__CacheRoot
$previousEnvironment = $env:ASPNETCORE_ENVIRONMENT
$previousDocumentWorkerScript = $env:PythonWorker__DocumentWorkerScript
$env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
$env:KqgPaths__DataRoot = $runtimeDataRoot
$env:KqgPaths__FileStoreRoot = $runtimeFileStoreRoot
$env:KqgPaths__BackupRoot = $runtimeBackupRoot
$env:KqgPaths__LogsRoot = $runtimeLogsRoot
$env:KqgPaths__CacheRoot = $runtimeCacheRoot
$env:ASPNETCORE_ENVIRONMENT = 'Development'
$env:PythonWorker__DocumentWorkerScript = '..\..\workers\document\worker.py'
$process = $null

try {
    Push-Location $repoRoot

    if ($AllowPartialReport) {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-real005b-source-region-screenshots.ps1 -FileStoreRoot $runtimeFileStoreRoot -AllowPartialReport | Out-Null
    }
    else {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-real005b-source-region-screenshots.ps1 -FileStoreRoot $runtimeFileStoreRoot | Out-Null
    }
    if ($LASTEXITCODE -ne 0) {
        if (-not $AllowPartialReport) {
            throw 'REAL005B screenshot evidence prerequisite failed'
        }

        $screenshotReportPath = Join-Path $repoRoot ('docs/evidence/{0}-real005b-source-region-screenshots.json' -f (Get-Date -Format 'yyyyMMdd'))
        if (-not (Test-Path -LiteralPath $screenshotReportPath)) {
            throw 'REAL005B screenshot evidence prerequisite failed and no report file was written'
        }

        $screenshotReport = Get-Content -LiteralPath $screenshotReportPath -Raw | ConvertFrom-Json
        if ($screenshotReport.status -ne 'partial') {
            throw "REAL005B screenshot evidence prerequisite failed and status $($screenshotReport.status)"
        }
    }

    if ($AllowPartialReport) {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-real005b-reviewed-question-materialize.ps1 -FileStoreRoot $runtimeFileStoreRoot -Apply -AllowPartialReport | Out-Null
    }
    else {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-real005b-reviewed-question-materialize.ps1 -FileStoreRoot $runtimeFileStoreRoot -Apply | Out-Null
    }
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
        '--no-launch-profile',
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

        try {
            $question = Invoke-RestMethod -Method Get -Uri "$apiUrl/questions/$questionId" -TimeoutSec 10
            $sources = Invoke-RestMethod -Method Get -Uri "$apiUrl/questions/$questionId/sources" -TimeoutSec 10
            $regions = @($sources.sourceRegions)
            $screenshotCount = @($regions | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.screenshotUrl) }).Count
            $pageScreenshotCount = @($regions | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.pageScreenshotUrl) }).Count
            $status = [string]$question.status
        }
        catch {
            if (-not $AllowPartialReport) {
                throw
            }

            $regions = @()
            $screenshotCount = 0
            $pageScreenshotCount = 0
            $status = 'error'
            $missing += [pscustomobject]@{
                questionId = $questionId
                questionNo = $questionNo
                sourceFile = $sourceFile
                status = $status
                regionCount = 0
                screenshotCount = 0
                pageScreenshotCount = 0
                error = $_.Exception.Message
            }
            continue
        }

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

    if ($missing.Count -gt 0 -and -not $AllowPartialReport) {
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
        sourceReviewPass = ($missing.Count -eq 0)
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

    if ($missing.Count -gt 0) {
        $report.status = 'partial'
        $report.sourceReviewPass = $false
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
    $env:KqgPaths__DataRoot = $previousDataRoot
    $env:KqgPaths__FileStoreRoot = $previousFileStoreRoot
    $env:KqgPaths__BackupRoot = $previousBackupRoot
    $env:KqgPaths__LogsRoot = $previousLogsRoot
    $env:KqgPaths__CacheRoot = $previousCacheRoot
    $env:ASPNETCORE_ENVIRONMENT = $previousEnvironment
    $env:PythonWorker__DocumentWorkerScript = $previousDocumentWorkerScript
    Pop-Location
}

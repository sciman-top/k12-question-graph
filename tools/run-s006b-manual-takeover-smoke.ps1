param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [int] $ApiPort = 0,
    [string] $ReportPath = 'docs/evidence/20260506-s006b-manual-takeover-smoke-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for S006B smoke'
}

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return $listener.LocalEndpoint.Port
    }
    finally {
        $listener.Stop()
    }
}

$requestedApiPort = $ApiPort
if ($ApiPort -le 0) {
    $ApiPort = Get-FreeTcpPort
}
$apiUrl = "http://127.0.0.1:$ApiPort"
$logOut = Join-Path $repoRoot 'docs/evidence/s006b-smoke-api.out.log'
$logErr = Join-Path $repoRoot 'docs/evidence/s006b-smoke-api.err.log'
$previousConnectionString = $env:KQG_CONNECTION_STRING
$env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"

$process = $null
try {
    $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\\api\\K12QuestionGraph.Api.csproj','-c','Release','--no-build','--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr

    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
        try {
            $health = Invoke-RestMethod -Uri "$apiUrl/health/ready" -TimeoutSec 2
            if ($health.status -eq 'ok') { $ready = $true; break }
        } catch { Start-Sleep -Milliseconds 500 }
    }
    if (-not $ready) { throw "API did not become ready on $apiUrl" }

    $sourceList = Invoke-RestMethod -Uri "$apiUrl/source-documents" -TimeoutSec 10
    $sourceId = [string]$sourceList.items[0].id
    if ([string]::IsNullOrWhiteSpace($sourceId)) {
        throw 'No source document available for S006B smoke'
    }

    Invoke-RestMethod -Uri "$apiUrl/source-documents/$sourceId/cut-candidates/generate" -Method Post -TimeoutSec 15 | Out-Null
    $candidateList = Invoke-RestMethod -Uri "$apiUrl/source-documents/$sourceId/cut-candidates" -TimeoutSec 10
    $candidateIds = @($candidateList.items | ForEach-Object { [string]$_.id })
    if ($candidateIds.Count -lt 2) {
        $missingRegionCount = 2 - $candidateIds.Count
        for ($regionIndex = 0; $regionIndex -lt $missingRegionCount; $regionIndex++) {
            $regionBody = @{
                pageNumber = 1
                x = 12 + ($regionIndex * 16)
                y = 12 + ($regionIndex * 8)
                width = 40
                height = 20
                coordinateUnit = 'percent'
                regionType = 'preview'
            } | ConvertTo-Json -Depth 4
            Invoke-RestMethod -Uri "$apiUrl/source-documents/$sourceId/regions" -Method Post -ContentType 'application/json' -Body $regionBody -TimeoutSec 15 | Out-Null
        }
        Invoke-RestMethod -Uri "$apiUrl/source-documents/$sourceId/cut-candidates/generate" -Method Post -TimeoutSec 15 | Out-Null
        $candidateList = Invoke-RestMethod -Uri "$apiUrl/source-documents/$sourceId/cut-candidates" -TimeoutSec 10
        $candidateIds = @($candidateList.items | ForEach-Object { [string]$_.id })
    }
    if ($candidateIds.Count -lt 2) {
        throw 'Need at least 2 candidates for merge/split smoke'
    }

    $mergeBody = @{
        action = 'merge'
        sourceDocumentId = $sourceId
        candidateIds = @($candidateIds[0], $candidateIds[1])
        reviewedBy = 's006b_smoke'
        reason = 'smoke_merge'
    } | ConvertTo-Json -Depth 6
    $merge = Invoke-RestMethod -Uri "$apiUrl/review-workbench/actions" -Method Post -ContentType 'application/json' -Body $mergeBody -TimeoutSec 15

    $latestCandidates = Invoke-RestMethod -Uri "$apiUrl/source-documents/$sourceId/cut-candidates" -TimeoutSec 10
    $splitTarget = [string]($latestCandidates.items | Select-Object -First 1).id
    $splitBody = @{
        action = 'split'
        sourceDocumentId = $sourceId
        candidateIds = @($splitTarget)
        reviewedBy = 's006b_smoke'
        reason = 'smoke_split'
    } | ConvertTo-Json -Depth 6
    $split = Invoke-RestMethod -Uri "$apiUrl/review-workbench/actions" -Method Post -ContentType 'application/json' -Body $splitBody -TimeoutSec 15

    $associateTarget = [string](($latestCandidates.items | Select-Object -First 1).id)
    $associateBody = @{
        action = 'associate'
        sourceDocumentId = $sourceId
        candidateIds = @($associateTarget)
        assetLabel = '图 A：滑轮组示意图'
        reviewedBy = 's006b_smoke'
        reason = 'smoke_associate'
    } | ConvertTo-Json -Depth 6
    $associate = Invoke-RestMethod -Uri "$apiUrl/review-workbench/actions" -Method Post -ContentType 'application/json' -Body $associateBody -TimeoutSec 15

    $saveBody = @{
        action = 'save_question'
        sourceDocumentId = $sourceId
        candidateIds = @($associateTarget)
        reviewedBy = 's006b_smoke'
        reason = 'smoke_save_question'
    } | ConvertTo-Json -Depth 6
    $save = Invoke-RestMethod -Uri "$apiUrl/review-workbench/actions" -Method Post -ContentType 'application/json' -Body $saveBody -TimeoutSec 20

    $report = [ordered]@{
        status = 'pass'
        taskId = 'S006B'
        checkedAt = (Get-Date).ToString('s')
        requestedApiPort = $requestedApiPort
        resolvedApiPort = $ApiPort
        portFallbackApplied = ($requestedApiPort -ne $ApiPort)
        sourceDocumentId = $sourceId
        actions = [ordered]@{
            merge = [ordered]@{ touched = @($merge.touchedIds).Count; createdCandidates = @($merge.createdCandidateIds).Count }
            split = [ordered]@{ touched = @($split.touchedIds).Count; createdCandidates = @($split.createdCandidateIds).Count }
            associate = [ordered]@{ touched = @($associate.touchedIds).Count }
            save_question = [ordered]@{ touched = @($save.touchedIds).Count; createdQuestionId = [string]$save.createdQuestionId }
        }
        conclusion = 'manual takeover workbench API supports merge split associate and save question chain'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    if ($process) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    $env:KQG_CONNECTION_STRING = $previousConnectionString
}

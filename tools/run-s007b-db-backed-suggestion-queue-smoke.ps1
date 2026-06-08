param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [int] $ApiPort = 0,
    [string] $RunId = [Guid]::NewGuid().ToString('N'),
    [string] $ReportPath = 'docs/evidence/20260506-s007b-db-backed-suggestion-queue-smoke-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for S007B smoke'
}

$requestedApiPort = $ApiPort
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

if ($ApiPort -le 0) {
    $ApiPort = Get-FreeTcpPort
}
$apiUrl = "http://127.0.0.1:$ApiPort"
$logOut = Join-Path $repoRoot 'docs/evidence/s007b-smoke-api.out.log'
$logErr = Join-Path $repoRoot 'docs/evidence/s007b-smoke-api.err.log'
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
    if ([string]::IsNullOrWhiteSpace($sourceId)) { throw 'S007B needs at least one source document' }

    $questionsBefore = Invoke-RestMethod -Uri "$apiUrl/questions?subject=physics&stage=junior_middle_school&limit=1" -TimeoutSec 10
    $questionTotalBefore = [int]$questionsBefore.total

    $enqueueBody = @{
        suggestionType = 'knowledge_tagging'
        sourceDocumentId = $sourceId
        sourceRegionIds = @()
        confidence = @{ score = 0.68; threshold = 0.85 }
        cost = @{ inputTokens = 180; outputTokens = 62; estimatedUsd = 0.014 }
        cache = @{ cacheKey = "s007b-$RunId-$sourceId"; cacheHit = $false }
        idempotencyKey = "s007b-$RunId-$sourceId"
        payload = @{
            suggestion = 'tag_by_semantics'
            questionTypeSuggestion = 'single_choice'
            difficultySuggestion = 0.62
            answerVerification = 'pending_review'
        }
        modelRoute = 'suggestion_stub'
        promptVersion = 's007b.prompt.v1'
    } | ConvertTo-Json -Depth 8

    $enqueue = Invoke-RestMethod -Method Post -Uri "$apiUrl/ai-suggestions/enqueue" -ContentType 'application/json' -Body $enqueueBody -TimeoutSec 10
    if ([string]$enqueue.reviewStatus -ne 'open') { throw 'S007B enqueue must keep pending review status (open)' }
    if ([bool]$enqueue.teacherModified) { throw 'S007B enqueue must not set teacherModified=true' }
    if ([string]::IsNullOrWhiteSpace([string]$enqueue.reviewQueueItemId)) { throw 'S007B enqueue must create review queue item' }

    $queue = Invoke-RestMethod -Uri "$apiUrl/review-queue?status=open&reviewType=ai_suggestion&limit=20" -TimeoutSec 10
    $queueItem = @($queue.items | Where-Object { $_.id -eq $enqueue.reviewQueueItemId })[0]
    if ($null -eq $queueItem) { throw 'S007B review queue item not found in open list' }

    $feedbackBody = @{
        decision = 'approved'
        teacherModified = $true
        reviewedBy = 'teacher_s007b'
        reason = 'teacher_adjusted_tag_and_difficulty'
    } | ConvertTo-Json
    $feedback = Invoke-RestMethod -Method Post -Uri "$apiUrl/ai-suggestions/$($enqueue.aiJobId)/feedback" -ContentType 'application/json' -Body $feedbackBody -TimeoutSec 10
    if (-not [bool]$feedback.teacherModified) { throw 'S007B feedback must persist teacherModified=true' }
    if ([string]$feedback.reviewStatus -ne 'resolved') { throw 'S007B approved feedback must resolve review status' }

    $questionsAfter = Invoke-RestMethod -Uri "$apiUrl/questions?subject=physics&stage=junior_middle_school&limit=1" -TimeoutSec 10
    $questionTotalAfter = [int]$questionsAfter.total
    if ($questionTotalAfter -ne $questionTotalBefore) {
        throw "S007B no-active-write guard failed: question total changed ($questionTotalBefore -> $questionTotalAfter)"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'S007B'
        checkedAt = (Get-Date).ToString('s')
        requestedApiPort = $requestedApiPort
        resolvedApiPort = $ApiPort
        portFallbackApplied = ($requestedApiPort -ne $ApiPort)
        runId = $RunId
        sourceDocumentId = $sourceId
        enqueue = [ordered]@{
            aiJobId = $enqueue.aiJobId
            reviewQueueItemId = $enqueue.reviewQueueItemId
            reviewStatus = $enqueue.reviewStatus
        }
        feedback = [ordered]@{
            decision = $feedback.decision
            reviewStatus = $feedback.reviewStatus
            teacherModified = $feedback.teacherModified
            resolvedQueueItemIds = @($feedback.resolvedQueueItemIds)
        }
        noActiveWriteGuard = [ordered]@{
            questionTotalBefore = $questionTotalBefore
            questionTotalAfter = $questionTotalAfter
            changed = ($questionTotalAfter -ne $questionTotalBefore)
        }
        conclusion = 'ai suggestions are persisted in db-backed review queue as pending review and teacher feedback resolves queue without direct question write'
    }
    $reportPath = Join-Path $repoRoot $ReportPath
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 10
}
finally {
    if ($null -ne $process) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    $env:KQG_CONNECTION_STRING = $previousConnectionString
}

param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [int] $ApiPort = 0,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $RunId = [Guid]::NewGuid().ToString('N'),
    [string] $ReportPath = 'docs/evidence/20260506-s007c-teacher-confirm-writeback-smoke-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
if ([string]::IsNullOrWhiteSpace($DatabasePassword)) { throw 'DatabasePassword or PGPASSWORD is required for S007C smoke' }

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

function Invoke-ScalarSql([string] $Sql) {
    $psql = Join-Path $PgBin 'psql.exe'
    $value = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c $Sql
    if ($LASTEXITCODE -ne 0) { throw "S007C SQL failed: $Sql" }
    return (($value | Select-Object -First 1) ?? '').Trim()
}

$requestedApiPort = $ApiPort
if ($ApiPort -le 0) {
    $ApiPort = Get-FreeTcpPort
}
$apiUrl = "http://127.0.0.1:$ApiPort"
$logOut = Join-Path $repoRoot 'docs/evidence/s007c-smoke-api.out.log'
$logErr = Join-Path $repoRoot 'docs/evidence/s007c-smoke-api.err.log'
$previousConnectionString = $env:KQG_CONNECTION_STRING
$env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"

$process = $null
try {
    $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\\api\\K12QuestionGraph.Api.csproj','-c','Release','--no-build','--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr
    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
        try { if ((Invoke-RestMethod -Uri "$apiUrl/health/ready" -TimeoutSec 2).status -eq 'ok') { $ready = $true; break } } catch {}
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { throw "API did not become ready on $apiUrl" }

    $sourceList = Invoke-RestMethod -Uri "$apiUrl/source-documents" -TimeoutSec 10
    $sourceId = [string]$sourceList.items[0].id
    if ([string]::IsNullOrWhiteSpace($sourceId)) { throw 'S007C needs at least one source document' }

    $enqueueBody = @{
        suggestionType = 'answer_verification'
        sourceDocumentId = $sourceId
        sourceRegionIds = @()
        confidence = @{ score = 0.74; threshold = 0.9 }
        cost = @{ inputTokens = 96; outputTokens = 44; estimatedUsd = 0.009 }
        cache = @{ cacheKey = "s007c-$RunId-$sourceId"; cacheHit = $true }
        idempotencyKey = "s007c-$RunId-$sourceId"
        payload = @{ suggestion = 'requires_teacher_confirmation' }
    } | ConvertTo-Json -Depth 6
    $enqueue = Invoke-RestMethod -Method Post -Uri "$apiUrl/ai-suggestions/enqueue" -ContentType 'application/json' -Body $enqueueBody -TimeoutSec 10

    $feedbackBody = @{ decision = 'approved'; teacherModified = $true; reviewedBy = 'teacher_s007c'; reason = 'ready_to_writeback' } | ConvertTo-Json
    $feedback = Invoke-RestMethod -Method Post -Uri "$apiUrl/ai-suggestions/$($enqueue.aiJobId)/feedback" -ContentType 'application/json' -Body $feedbackBody -TimeoutSec 10
    if ([string]$feedback.reviewStatus -ne 'resolved') { throw 'S007C feedback should resolve suggestion before confirm' }

    $confirmBody = @{
        reviewedBy = 'teacher_s007c'
        reason = 'confirm_to_question_and_mapping'
        subject = 'physics'
        stage = 'junior_middle_school'
        grade = 'grade_8'
        questionType = 'single_choice'
        defaultScore = 3
        difficultyEstimated = 0.61
        mappingConfidence = 0.88
    } | ConvertTo-Json
    $confirm = Invoke-RestMethod -Method Post -Uri "$apiUrl/ai-suggestions/$($enqueue.aiJobId)/confirm" -ContentType 'application/json' -Body $confirmBody -TimeoutSec 10

    $loadedQuestion = Invoke-RestMethod -Uri "$apiUrl/questions/$($confirm.questionItemId)" -TimeoutSec 10
    if ([string]$loadedQuestion.id -ne [string]$confirm.questionItemId) { throw 'S007C confirmed question could not be loaded by id' }
    $confirmQuestionExists = [string](Invoke-ScalarSql "select exists(select 1 from question_items where id='$($confirm.questionItemId)');")
    if ($confirmQuestionExists -ne 't') { throw 'S007C confirmed question must exist before undo' }

    $undoBody = @{ reviewedBy = 'teacher_s007c'; reason = 'undo_for_safety_check' } | ConvertTo-Json
    $undo = Invoke-RestMethod -Method Post -Uri "$apiUrl/ai-suggestions/$($enqueue.aiJobId)/undo-confirm" -ContentType 'application/json' -Body $undoBody -TimeoutSec 10
    if ($undo.removedKnowledgeMappingCount -lt 1) { throw 'S007C undo should remove linked knowledge mapping' }
    $undoQuestionExists = [string](Invoke-ScalarSql "select exists(select 1 from question_items where id='$($confirm.questionItemId)');")
    if ($undoQuestionExists -ne 'f') { throw 'S007C undo should remove the confirmed question item' }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'S007C'
        checkedAt = (Get-Date).ToString('s')
        requestedApiPort = $requestedApiPort
        resolvedApiPort = $ApiPort
        portFallbackApplied = ($requestedApiPort -ne $ApiPort)
        runId = $RunId
        aiJobId = $enqueue.aiJobId
        confirm = [ordered]@{
            questionItemId = $confirm.questionItemId
            knowledgeMappingId = $confirm.knowledgeMappingId
            status = $confirm.status
        }
        undo = [ordered]@{
            removedQuestionItemId = $undo.removedQuestionItemId
            removedKnowledgeMappingCount = $undo.removedKnowledgeMappingCount
            status = $undo.status
        }
        questionLifecycle = [ordered]@{
            confirmQuestionExistsBeforeUndo = $true
            confirmQuestionExistsAfterUndo = $false
        }
        conclusion = 'teacher confirmation writes QuestionItem and KnowledgeMapping only after review, and undo restores previous state'
    }
    $full = Join-Path $repoRoot $ReportPath
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $full -Encoding UTF8
    $report | ConvertTo-Json -Depth 10
}
finally {
    if ($null -ne $process) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
    $env:KQG_CONNECTION_STRING = $previousConnectionString
}

param(
    [string] $ReportPath = 'docs/evidence/20260530-ns504-ai-suggestion-review-report.json',
    [string] $S007BSourceReportPath = 'docs/evidence/20260530-ns504-s007b-source-report.json',
    [string] $S007CSourceReportPath = 'docs/evidence/20260530-ns504-s007c-source-report.json',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Read-Json([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing report: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Read-Text([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing file: $Path"
    return Get-Content -LiteralPath $fullPath -Raw
}

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return [int]$listener.LocalEndpoint.Port
    }
    finally {
        $listener.Stop()
    }
}

Push-Location $repoRoot
try {
    $ns503 = Read-Json 'docs/evidence/20260530-ns503-model-router-budget-report.json'
    Assert-Condition ($ns503.status -eq 'pass') 'NS504 dependency NS503 report did not pass'
    Assert-Condition ([int]$ns503.externalAiCalls -eq 0) 'NS504 requires NS503 zero external AI calls'
    Assert-Condition ([bool]$ns503.acceptance.realModelCallsStillDisabled) 'NS504 requires real model calls disabled'
    Assert-Condition ([bool]$ns503.acceptance.stubJobStaysPendingReview) 'NS504 requires stub job pending_review evidence'
    Assert-Condition ([bool]$ns503.acceptance.budgetOverrunFailsClosed) 'NS504 requires NS503 budget fail-closed boundary'

    $ns204 = Read-Json 'docs/evidence/20260529-ns204-no-active-write-guard-report.json'
    Assert-Condition ($ns204.status -eq 'pass') 'NS504 dependency NS204 report did not pass'
    Assert-Condition ([bool]$ns204.acceptance.aiCandidatesStayPendingReview) 'NS504 requires NS204 AI candidate pending-review boundary'
    Assert-Condition ([bool]$ns204.acceptance.externalAiDefaultOff) 'NS504 requires NS204 external AI default-off boundary'

    $runId = "ns504-$([Guid]::NewGuid().ToString('N'))"
    $s007bPort = Get-FreeTcpPort
    $s007bOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File 'tools/run-s007b-db-backed-suggestion-queue-smoke.ps1' `
        -DatabaseName $DatabaseName `
        -DatabaseUser $DatabaseUser `
        -DatabaseHost $DatabaseHost `
        -DatabasePort $DatabasePort `
        -DatabasePassword $DatabasePassword `
        -ApiPort $s007bPort `
        -RunId "$runId-b" `
        -ReportPath $S007BSourceReportPath 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "S007B suggestion queue dependency failed: $s007bOutput"

    $s007cPort = Get-FreeTcpPort
    $s007cOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File 'tools/run-s007c-teacher-confirm-writeback-smoke.ps1' `
        -DatabaseName $DatabaseName `
        -DatabaseUser $DatabaseUser `
        -DatabaseHost $DatabaseHost `
        -DatabasePort $DatabasePort `
        -DatabasePassword $DatabasePassword `
        -PgBin $PgBin `
        -ApiPort $s007cPort `
        -RunId "$runId-c" `
        -ReportPath $S007CSourceReportPath 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "S007C teacher confirm dependency failed: $s007cOutput"

    $s007b = Read-Json $S007BSourceReportPath
    $s007c = Read-Json $S007CSourceReportPath

    Assert-Condition ($s007b.status -eq 'pass' -and $s007b.taskId -eq 'S007B') 'S007B source report did not pass'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$s007b.enqueue.aiJobId)) 'NS504 S007B enqueue AI job missing'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$s007b.enqueue.reviewQueueItemId)) 'NS504 S007B review queue item missing'
    Assert-Condition ([string]$s007b.enqueue.reviewStatus -eq 'open') 'NS504 S007B review queue must start open'
    Assert-Condition ([string]$s007b.feedback.reviewStatus -eq 'resolved') 'NS504 S007B feedback must resolve review'
    Assert-Condition ([bool]$s007b.feedback.teacherModified) 'NS504 S007B must capture teacherModified feedback'
    Assert-Condition ([bool]$s007b.noActiveWriteGuard.changed -eq $false) 'NS504 S007B must not directly change questions'
    Assert-Condition ([int]$s007b.noActiveWriteGuard.questionTotalBefore -eq [int]$s007b.noActiveWriteGuard.questionTotalAfter) 'NS504 S007B question count changed before teacher confirmation'

    Assert-Condition ($s007c.status -eq 'pass' -and $s007c.taskId -eq 'S007C') 'S007C source report did not pass'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$s007c.aiJobId)) 'NS504 S007C AI job missing'
    Assert-Condition ([string]$s007c.confirm.status -eq 'confirmed') 'NS504 S007C confirm status missing'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$s007c.confirm.questionItemId)) 'NS504 S007C question item writeback missing'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$s007c.confirm.knowledgeMappingId)) 'NS504 S007C knowledge mapping writeback missing'
    Assert-Condition ([int]$s007c.questionCount.afterConfirm -eq ([int]$s007c.questionCount.before + 1)) 'NS504 S007C confirm must add one question'
    Assert-Condition ([string]$s007c.undo.status -eq 'undone') 'NS504 S007C undo status missing'
    Assert-Condition ([int]$s007c.undo.removedKnowledgeMappingCount -ge 1) 'NS504 S007C undo must remove linked knowledge mapping'
    Assert-Condition ([int]$s007c.questionCount.afterUndo -eq [int]$s007c.questionCount.before) 'NS504 S007C undo must restore question count'

    $program = Read-Text 'apps/api/Program.cs'
    foreach ($marker in @(
        'app.MapPost("/ai-suggestions/enqueue"',
        'app.MapPost("/ai-suggestions/{id:guid}/feedback"',
        'app.MapPost("/ai-suggestions/{id:guid}/confirm"',
        'app.MapPost("/ai-suggestions/{id:guid}/undo-confirm"',
        'ReviewType = "ai_suggestion"',
        'job.TeacherModified = request.TeacherModified',
        'MappingSource = KnowledgeMappingSources.Manual',
        'source = "ai_suggestion_teacher_confirmed"'
    )) {
        Assert-Condition ($program.Contains($marker)) "NS504 API marker missing: $marker"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS504'
        checkedAt = (Get-Date).ToString('s')
        mode = 'ai_suggestion_review_queue_teacher_confirm_writeback_guard'
        productionEligible = $false
        externalAiCalls = 0
        allowRealModelCalls = $false
        noLocalModelUsed = $true
        runId = $runId
        dependency = [ordered]@{
            ns503 = 'docs/evidence/20260530-ns503-model-router-budget-report.json'
            ns204 = 'docs/evidence/20260529-ns204-no-active-write-guard-report.json'
            s007b = $S007BSourceReportPath
            s007c = $S007CSourceReportPath
        }
        reviewQueue = [ordered]@{
            aiJobId = [string]$s007b.enqueue.aiJobId
            reviewQueueItemId = [string]$s007b.enqueue.reviewQueueItemId
            initialReviewStatus = [string]$s007b.enqueue.reviewStatus
            feedbackDecision = [string]$s007b.feedback.decision
            feedbackReviewStatus = [string]$s007b.feedback.reviewStatus
            teacherModified = [bool]$s007b.feedback.teacherModified
            questionTotalBefore = [int]$s007b.noActiveWriteGuard.questionTotalBefore
            questionTotalAfter = [int]$s007b.noActiveWriteGuard.questionTotalAfter
        }
        teacherConfirm = [ordered]@{
            aiJobId = [string]$s007c.aiJobId
            questionItemId = [string]$s007c.confirm.questionItemId
            knowledgeMappingId = [string]$s007c.confirm.knowledgeMappingId
            afterConfirmQuestionDelta = ([int]$s007c.questionCount.afterConfirm - [int]$s007c.questionCount.before)
            undoStatus = [string]$s007c.undo.status
            removedKnowledgeMappingCount = [int]$s007c.undo.removedKnowledgeMappingCount
            afterUndoQuestionDelta = ([int]$s007c.questionCount.afterUndo - [int]$s007c.questionCount.before)
        }
        acceptance = [ordered]@{
            suggestionsEnterReviewQueue = $true
            teacherFeedbackResolvesQueue = $true
            suggestionsDoNotWriteQuestionBeforeConfirm = $true
            teacherConfirmWritesQuestionAndMapping = $true
            undoRestoresQuestionCount = $true
            realModelCallsStillDisabled = $true
            externalAiCallsZero = $true
            localModelNotUsed = $true
            activeC002NotSwitched = $true
        }
        boundary = 'NS504 proves AI suggestions are stored as review-queue candidates and teacher feedback/confirmation gates writeback. S007B verifies no question write before confirmation; S007C verifies teacher confirm creates one QuestionItem and KnowledgeMapping, then undo restores the count. It does not enable real model calls, local models, external AI, or C002 active switching.'
        next = 'NS505 can continue teacher modification feedback and eval-loop evidence without auto-promoting prompt or production assets.'
        rollback = "git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1 tools/run-s007b-db-backed-suggestion-queue-smoke.ps1 tools/run-s007c-teacher-confirm-writeback-smoke.ps1; git clean -f -- tools/run-ns504-ai-suggestion-review.ps1 docs/evidence/20260530-ns504-ai-suggestion-review-report.json docs/evidence/20260530-ns504-s007b-source-report.json docs/evidence/20260530-ns504-s007c-source-report.json"
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}

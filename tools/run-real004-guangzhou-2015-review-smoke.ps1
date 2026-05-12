param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [int] $ApiPort = 5297,
    [string] $ReportPath = 'docs/evidence/20260512-real004-guangzhou-2015-review-smoke-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for REAL004 smoke'
}

$apiUrl = "http://127.0.0.1:$ApiPort"
$logOut = Join-Path $repoRoot 'docs/evidence/real004-review-smoke-api.out.log'
$logErr = Join-Path $repoRoot 'docs/evidence/real004-review-smoke-api.err.log'
$previousConnectionString = $env:KQG_CONNECTION_STRING
$env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"

$process = $null
try {
    Push-Location $repoRoot

    # Ensure the smoke starts from the current REAL001 applied state and from the
    # latest review payload contract, including answer/tag/text preview fields.
    & pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-guangzhou-2015-real-ingest-slice.ps1 `
        -DatabaseName $DatabaseName `
        -DatabaseUser $DatabaseUser `
        -DatabaseHost $DatabaseHost `
        -DatabasePort $DatabasePort `
        -DatabasePassword $DatabasePassword `
        -FileStoreRoot $FileStoreRoot `
        -Apply | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'REAL004 setup failed while applying REAL001 ingest state'
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

    $ready = $false
    for ($i = 0; $i -lt 50; $i++) {
        if ($process.HasExited) {
            throw "API exited before ready on $apiUrl; see $logOut and $logErr"
        }
        try {
            $health = Invoke-RestMethod -Uri "$apiUrl/health/ready" -TimeoutSec 2
            if ($health.status -eq 'ok') {
                $ready = $true
                break
            }
        } catch {
            Start-Sleep -Milliseconds 500
        }
    }
    if (-not $ready) {
        throw "API did not become ready on $apiUrl; see $logOut and $logErr"
    }

    $initialQueue = Invoke-RestMethod -Uri "$apiUrl/review-queue?status=open&reviewType=guangzhou_2015_question_review&limit=50" -TimeoutSec 10
    $initialItems = @($initialQueue.items)
    if ($initialItems.Count -ne 18) {
        throw "REAL004 smoke expects 18 open Guangzhou 2015 review items, got $($initialItems.Count)"
    }

    $first = $initialItems | Sort-Object { [int]$_.payload.questionNo } | Select-Object -First 1
    $second = $initialItems | Sort-Object { [int]$_.payload.questionNo } | Select-Object -Skip 1 -First 1
    foreach ($item in @($first, $second)) {
        if ([string]::IsNullOrWhiteSpace([string]$item.payload.textPreview)) {
            throw "review payload missing textPreview for item $($item.id)"
        }
        if ([string]::IsNullOrWhiteSpace([string]$item.payload.answer)) {
            throw "review payload missing answer for item $($item.id)"
        }
        if ([string]::IsNullOrWhiteSpace([string]$item.payload.primaryKnowledgeLabel)) {
            throw "review payload missing primaryKnowledgeLabel for item $($item.id)"
        }
        if (@($item.payload.knowledgeTags).Count -lt 1) {
            throw "review payload missing knowledgeTags for item $($item.id)"
        }
    }

    $firstSources = Invoke-RestMethod -Uri "$apiUrl/questions/$($first.payload.questionItemId)/sources" -TimeoutSec 10
    if (@($firstSources.sourceRegions).Count -lt 2) {
        throw "REAL004 smoke expected question and answer source regions for question $($first.payload.questionNo)"
    }

    $confirmBody = @{
        reviewedBy = 'teacher-real004-smoke'
        decision = 'resolved'
        reason = 'checked stem answer tags and source regions'
    } | ConvertTo-Json -Depth 4
    $confirmed = Invoke-RestMethod -Method Post -Uri "$apiUrl/review-queue/$($first.id)/resolve" -ContentType 'application/json' -Body $confirmBody -TimeoutSec 10
    if ([string]$confirmed.status -ne 'resolved') {
        throw "REAL004 confirm did not resolve item $($first.id)"
    }
    if ([string]$confirmed.payload.reviewAudit.reviewedBy -ne 'teacher-real004-smoke') {
        throw 'REAL004 confirm did not write review audit'
    }

    $dismissBody = @{
        reviewedBy = 'teacher-real004-smoke'
        decision = 'dismissed'
        reason = 'returned for precise visual crop and tag correction'
    } | ConvertTo-Json -Depth 4
    $dismissed = Invoke-RestMethod -Method Post -Uri "$apiUrl/review-queue/$($second.id)/resolve" -ContentType 'application/json' -Body $dismissBody -TimeoutSec 10
    if ([string]$dismissed.status -ne 'dismissed') {
        throw "REAL004 dismiss did not dismiss item $($second.id)"
    }
    if ([string]$dismissed.payload.reviewAudit.decision -ne 'dismissed') {
        throw 'REAL004 dismiss did not write review audit decision'
    }

    $afterActionQueue = Invoke-RestMethod -Uri "$apiUrl/review-queue?status=open&reviewType=guangzhou_2015_question_review&limit=50" -TimeoutSec 10
    $afterActionOpenCount = @($afterActionQueue.items).Count
    if ($afterActionOpenCount -ne 16) {
        throw "REAL004 expected 16 open review items after confirm+dismiss, got $afterActionOpenCount"
    }

    # Restore the deterministic pending-review baseline for repeatable gates and
    # for the user's next real review pass.
    & pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-guangzhou-2015-real-ingest-slice.ps1 `
        -DatabaseName $DatabaseName `
        -DatabaseUser $DatabaseUser `
        -DatabaseHost $DatabaseHost `
        -DatabasePort $DatabasePort `
        -DatabasePassword $DatabasePassword `
        -FileStoreRoot $FileStoreRoot `
        -Apply | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'REAL004 restore failed while re-applying REAL001 ingest state'
    }

    $restoredQueue = Invoke-RestMethod -Uri "$apiUrl/review-queue?status=open&reviewType=guangzhou_2015_question_review&limit=50" -TimeoutSec 10
    $restoredOpenCount = @($restoredQueue.items).Count
    if ($restoredOpenCount -ne 18) {
        throw "REAL004 restore expected 18 open review items, got $restoredOpenCount"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'REAL004'
        checkedAt = (Get-Date).ToString('s')
        apiUrl = $apiUrl
        workflowKey = 'guangzhou_2015_real_ingest_v1'
        reviewType = 'guangzhou_2015_question_review'
        initialOpenReviewItems = $initialItems.Count
        loadedQuestion = [ordered]@{
            questionNo = [int]$first.payload.questionNo
            questionItemId = [string]$first.payload.questionItemId
            sourceRegionCount = @($firstSources.sourceRegions).Count
            hasTextPreview = -not [string]::IsNullOrWhiteSpace([string]$first.payload.textPreview)
            hasAnswer = -not [string]::IsNullOrWhiteSpace([string]$first.payload.answer)
            hasKnowledgeTags = @($first.payload.knowledgeTags).Count -gt 0
        }
        actions = [ordered]@{
            confirm = [ordered]@{
                itemId = [string]$confirmed.id
                status = [string]$confirmed.status
                auditReviewedBy = [string]$confirmed.payload.reviewAudit.reviewedBy
                auditReason = [string]$confirmed.payload.reviewAudit.reason
            }
            dismiss = [ordered]@{
                itemId = [string]$dismissed.id
                status = [string]$dismissed.status
                auditDecision = [string]$dismissed.payload.reviewAudit.decision
                auditReason = [string]$dismissed.payload.reviewAudit.reason
            }
        }
        afterActionOpenReviewItems = $afterActionOpenCount
        restoredOpenReviewItems = $restoredOpenCount
        verification = [ordered]@{
            canFilterGuangzhou2015Queue = $true
            canLoadQuestionSources = $true
            canConfirmWithAudit = $true
            canReturnWithAudit = $true
            restoredRepeatableBaseline = $true
            externalAiCalls = 0
            realStudentDataUsed = $false
        }
        remainingGaps = @(
            'REAL004 smoke proves confirm and return audit for the first-18 queue, but it does not prove teacher-edited answer/tag revision.',
            'Question source regions are still REAL001 placeholder text regions until REAL002 visual bbox and assets are implemented.',
            'Teacher acceptance remains pending because this smoke uses deterministic local API calls, not a human classroom review session.'
        )
        rollback = [ordered]@{
            restoreCommand = 'pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-guangzhou-2015-real-ingest-slice.ps1 -Apply'
            targetedSql = @(
                "delete from review_queue_items where payload::text like '%guangzhou_2015_real_ingest_v1%';",
                "delete from question_blocks where question_item_id in (select id from question_items where custom_fields->>'sourceWorkflowKey' = 'guangzhou_2015_real_ingest_v1');",
                "delete from cut_candidates where metadata::text like '%guangzhou_2015_real_ingest_v1%' or candidate_payload::text like '%guangzhou_2015_real_ingest_v1%';",
                "delete from question_items where custom_fields->>'sourceWorkflowKey' = 'guangzhou_2015_real_ingest_v1';",
                "delete from source_regions where region_type in ('guangzhou_2015_question','guangzhou_2015_answer');"
            )
        }
    }

    $full = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $full -Encoding UTF8
    $report | ConvertTo-Json -Depth 12
}
finally {
    if ($null -ne $process) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    $env:KQG_CONNECTION_STRING = $previousConnectionString
    Pop-Location
}

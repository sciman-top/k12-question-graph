param(
    [string] $ReportPath = 'docs\evidence\20260727-guangzhou-physics-v2-review-ui-contract.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$app = Get-Content -LiteralPath (Join-Path $repoRoot 'apps\web\src\App.tsx') -Raw
$realExamReview = Get-Content -LiteralPath (Join-Path $repoRoot 'apps\web\src\ui\RealExamReviewWorkbench.tsx') -Raw
$uiSource = $app + "`n" + $realExamReview
$client = Get-Content -LiteralPath (Join-Path $repoRoot 'apps\web\src\api\client.ts') -Raw
$api = Get-Content -LiteralPath (Join-Path $repoRoot 'apps\api\Program.cs') -Raw

function Assert-Contains([string] $Content, [string] $Pattern, [string] $Description) {
    if (-not $Content.Contains($Pattern)) {
        throw "T7 UI contract missing ${Description}: $Pattern"
    }
}

$appMarkers = [ordered]@{
    workflow = 'data-workflow="guangzhou-physics-2015-2025-v2"'
    yearSelector = 'data-action="select-real-guangzhou-review-year"'
    saveRevision = 'data-action="save-real-guangzhou-v2-review-revision"'
    confirm = 'data-action="confirm-real-guangzhou-2015-review-item"'
    dismiss = 'data-action="dismiss-real-guangzhou-2015-review-item"'
    recrop = 'data-action="save-real-guangzhou-v2-recrop"'
    undoRecrop = 'data-action="undo-real-guangzhou-v2-recrop"'
    undoReview = 'data-action="undo-real-guangzhou-v2-review-item"'
    retryMessage = '当前输入仍保留，可修正后重试'
    partialFailureMessage = '题目修订已保存，队列仍可继续处理'
    staleLoadGuard = 'requestId !== realExamLoadRequestRef.current'
    questionIdentityGuard = 'loadedRealExamQuestion.id !== item.payload.questionItemId'
}

foreach ($entry in $appMarkers.GetEnumerator()) {
    Assert-Contains $uiSource $entry.Value $entry.Key
}

$clientMarkers = [ordered]@{
    loadQuestion = 'export async function getQuestion('
    reviseQuestion = 'export async function updateQuestion('
    reviseSource = 'export async function updateSourceRegion('
    reopenReview = 'export async function reopenReviewQueueItem('
}

foreach ($entry in $clientMarkers.GetEnumerator()) {
    Assert-Contains $client $entry.Value $entry.Key
}

foreach ($marker in @(
    'app.MapPatch("/questions/{id:guid}"',
    'app.MapPatch("/source-regions/{id:guid}"',
    'app.MapPost("/review-queue/{id:guid}/resolve"',
    'app.MapPost("/review-queue/{id:guid}/reopen"'
)) {
    Assert-Contains $api $marker 'API route'
}

$report = [ordered]@{
    taskId = 'T7'
    status = 'pass'
    checkedAt = (Get-Date).ToString('o')
    workflow = 'guangzhou-physics-2015-2025-v2'
    uiContracts = @($appMarkers.Keys)
    clientContracts = @($clientMarkers.Keys)
    apiContracts = @('question_patch', 'source_region_patch', 'review_resolve', 'review_reopen')
    browserVerification = [ordered]@{
        status = 'platform_na'
        reason = 'Codex Browser and Chrome plugins block localhost non-root routes with net::ERR_BLOCKED_BY_CLIENT in this host session.'
        alternativeVerification = @(
            'static UI/client/API contract guard',
            'npm test and production build',
            'reversible real API/database workflow smoke'
        )
        evidenceLink = 'docs/evidence/20260727-guangzhou-physics-v2-review-workflow-smoke.json'
        expiresAt = 'next_browser_capability_refresh'
        recoveryCondition = 'Browser plugin can load localhost API/proxy routes and complete click-path assertions.'
    }
    truthBoundary = 'UI contract presence plus API smoke only; no real teacher acceptance or production review decision is recorded.'
}

$absoluteReportPath = Join-Path $repoRoot $ReportPath
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $absoluteReportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 10

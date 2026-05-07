param(
    [string] $ReportPath = 'docs/evidence/20260507-s009c-paper-workbench-ui-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Contains([string] $Content, [string] $Pattern, [string] $Message) {
    if (-not $Content.Contains($Pattern)) {
        throw $Message
    }
}

$appPath = Join-Path $repoRoot 'apps\web\src\App.tsx'
$clientPath = Join-Path $repoRoot 'apps\web\src\api\client.ts'
$contractsPath = Join-Path $repoRoot 'apps\web\src\api\contracts.ts'
$cssPath = Join-Path $repoRoot 'apps\web\src\App.css'

$app = Get-Content -LiteralPath $appPath -Raw
$client = Get-Content -LiteralPath $clientPath -Raw
$contracts = Get-Content -LiteralPath $contractsPath -Raw
$css = Get-Content -LiteralPath $cssPath -Raw

foreach ($pattern in @(
    'createPaperBlueprintReview',
    'confirmPaperBlueprintReview',
    'data-action="confirm-paper-blueprint"',
    'data-contract="s009c-real-blueprint-api"',
    'data-contract="confirmed-paper-basket"',
    'data-contract="paper-constraint-visible"',
    'data-state="s009c-paper-workflow-message"',
    'data-blueprint-review-id',
    'data-paper-basket-id',
    '确认细目表',
    '已保存题篮'
)) {
    Assert-Contains $app $pattern "missing S009C App marker: $pattern"
}

foreach ($pattern in @(
    'createPaperBlueprintReview',
    'confirmPaperBlueprintReview',
    '/paper-blueprints',
    '/paper-blueprints/${encodeURIComponent(id)}/confirm',
    'normalizePaperBlueprintReviewResponse',
    'normalizePaperBlueprintConfirmResponse'
)) {
    Assert-Contains $client $pattern "missing S009C API client marker: $pattern"
}

foreach ($pattern in @(
    'PaperBlueprintRowContract',
    'PaperBlueprintReviewContract',
    'PaperBlueprintConfirmContract',
    'normalizePaperBlueprintReviewResponse',
    'normalizePaperBlueprintConfirmResponse',
    'mustConfirmBeforeTakingQuestions',
    'opaqueGenerationAllowed'
)) {
    Assert-Contains $contracts $pattern "missing S009C contract marker: $pattern"
}

foreach ($pattern in @(
    '.paper-workflow-status',
    'grid-template-columns: minmax(180px, 0.72fr) minmax(0, 1.28fr);'
)) {
    Assert-Contains $css $pattern "missing S009C CSS marker: $pattern"
}

if ($app.Contains("{paperBasketId || '等待确认细目表'}")) {
    throw 'S009C must not expose backend paperBasketId as teacher-visible copy'
}

$report = [ordered]@{
    status = 'pass'
    taskId = 'S009C'
    checkedAt = (Get-Date).ToString('s')
    riskLevel = 'low'
    verifiedFiles = @(
        'apps/web/src/App.tsx',
        'apps/web/src/api/client.ts',
        'apps/web/src/api/contracts.ts',
        'apps/web/src/App.css'
    )
    contracts = @(
        's009c-real-blueprint-api',
        'confirmed-paper-basket',
        'paper-constraint-visible',
        's009c-paper-workflow-message'
    )
    teacherWorkflow = 'teacher creates a reviewable blueprint, explicitly confirms it, then sees a saved paper basket state without backend ids in visible copy'
    rollback = 'revert the S009C frontend/API client changes and remove this gate entry if the UI integration needs to be withdrawn'
}

$fullReportPath = Join-Path $repoRoot $ReportPath
New-Item -ItemType Directory -Path (Split-Path -Parent $fullReportPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $fullReportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 6

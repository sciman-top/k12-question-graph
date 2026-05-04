$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$app = Get-Content -LiteralPath (Join-Path $repoRoot 'apps\web\src\App.tsx') -Raw
$css = Get-Content -LiteralPath (Join-Path $repoRoot 'apps\web\src\App.css') -Raw

foreach ($pattern in @(
    'data-flow="manual-review"',
    'data-contract="review-queue-summary"',
    'data-action="filter-exceptions"',
    'data-action="batch-confirm"',
    'data-action="merge"',
    'data-action="split"',
    'data-action="associate"',
    'data-action="undo"',
    'selectExceptionItems',
    'batchConfirmSelected'
)) {
    if (-not $app.Contains($pattern)) {
        throw "missing I003 review queue marker: $pattern"
    }
}

foreach ($label in @('待确认','已选择','预计处理','只看异常','批量确认')) {
    if (-not $app.Contains($label)) {
        throw "missing I003 teacher-facing label: $label"
    }
}

foreach ($pattern in @('.review-summary', '.review-toolbar', '.segment-row.active')) {
    if (-not $css.Contains($pattern)) {
        throw "missing I003 review queue CSS: $pattern"
    }
}

[ordered]@{
    status = 'pass'
    task = 'I003'
    summaryVisible = $true
    shortcutActions = @('filter-exceptions','merge','split','associate','undo','batch-confirm')
    batchConfirm = $true
} | ConvertTo-Json -Depth 4

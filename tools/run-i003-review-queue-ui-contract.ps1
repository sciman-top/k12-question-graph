$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$app = Get-Content -LiteralPath (Join-Path $repoRoot 'apps\web\src\App.tsx') -Raw
$css = Get-Content -LiteralPath (Join-Path $repoRoot 'apps\web\src\App.css') -Raw

foreach ($pattern in @(
    'data-flow="manual-review"',
    'data-contract="review-queue-summary"',
    'data-contract="real-guangzhou-2015-review-workbench"',
    'data-contract="real-exam-review-summary"',
    'data-contract="real-exam-review-detail"',
    'data-contract="real-exam-teacher-revision"',
    'data-action="filter-exceptions"',
    'data-action="batch-confirm"',
    'data-action="load-real-guangzhou-2015-review-queue"',
    'data-action="load-real-guangzhou-2015-review-item"',
    'data-action="confirm-real-guangzhou-2015-review-item"',
    'data-action="dismiss-real-guangzhou-2015-review-item"',
    'data-action="real-guangzhou-2015-review-note"',
    'data-action="real-guangzhou-2015-revision-stem"',
    'data-action="real-guangzhou-2015-revision-answer"',
    'data-action="real-guangzhou-2015-revision-primary-tag"',
    'data-action="real-guangzhou-2015-revision-tags"',
    'data-action="merge"',
    'data-action="split"',
    'data-action="associate"',
    'data-action="undo"',
    'selectExceptionItems',
    'batchConfirmSelected',
    'getReviewQueueItems',
    'resolveReviewQueueItem'
)) {
    if (-not $app.Contains($pattern)) {
        throw "missing I003 review queue marker: $pattern"
    }
}

foreach ($label in @('待确认','已选择','预计处理','只看异常','批量确认','2015 广州真卷','逐题复核','查询真卷队列','载入当前题','确认当前题','退回当前题','审核说明','题干预览','答案','标签','来源','修订题干','修订答案','修订标签')) {
    if (-not $app.Contains($label)) {
        throw "missing I003 teacher-facing label: $label"
    }
}

foreach ($pattern in @('.review-summary', '.review-toolbar', '.segment-row.active', '.real-exam-review', '.real-exam-detail', '.real-exam-revision', '.real-exam-row.active')) {
    if (-not $css.Contains($pattern)) {
        throw "missing I003 review queue CSS: $pattern"
    }
}

[ordered]@{
    status = 'pass'
    task = 'I003'
    summaryVisible = $true
    realGuangzhou2015QueueVisible = $true
    realGuangzhou2015DetailVisible = $true
    shortcutActions = @('filter-exceptions','merge','split','associate','undo','batch-confirm')
    batchConfirm = $true
} | ConvertTo-Json -Depth 4

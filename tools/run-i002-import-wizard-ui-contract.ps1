$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$app = Get-Content -LiteralPath (Join-Path $repoRoot 'apps\web\src\App.tsx') -Raw
$css = Get-Content -LiteralPath (Join-Path $repoRoot 'apps\web\src\App.css') -Raw

foreach ($pattern in @(
    'data-flow="paper-import-wizard"',
    'data-action="upload-paper"',
    'data-contract={`import-step-${index + 1}`}',
    'data-contract="import-wizard-review"',
    'data-contract="source-review"',
    'data-flow="manual-review"',
    'data-flow="failure-takeover"',
    'data-action="manual-box"',
    'data-action="takeover-split"',
    'data-action="takeover-merge"',
    'data-action="skip-page"',
    'data-action="rerun-adapter"',
    'adapter_failed'
)) {
    if (-not $app.Contains($pattern)) {
        throw "missing I002 import wizard marker: $pattern"
    }
}

foreach ($label in @('上传文件','查看状态','确认异常','回看来源','上传试卷','异常确认与来源回看')) {
    if (-not $app.Contains($label)) {
        throw "missing I002 teacher-facing label: $label"
    }
}

foreach ($pattern in @(
    '.workspace.teacher-view-import .status-panel',
    '.workspace.teacher-view-import .review-panel',
    '.import-wizard',
    '.import-step',
    '.upload-dropzone'
)) {
    if (-not $css.Contains($pattern)) {
        throw "missing I002 import wizard CSS: $pattern"
    }
}

[ordered]@{
    status = 'pass'
    task = 'I002'
    wizardSteps = @('upload','job_status','exception_review','source_review')
    failureTakeover = $true
    sameTeacherView = 'import'
} | ConvertTo-Json -Depth 4

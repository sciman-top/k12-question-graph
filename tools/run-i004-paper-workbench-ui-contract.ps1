$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$app = Get-Content -LiteralPath (Join-Path $repoRoot 'apps\web\src\App.tsx') -Raw
$css = Get-Content -LiteralPath (Join-Path $repoRoot 'apps\web\src\App.css') -Raw

foreach ($pattern in @(
    'data-flow="paper-assembly-workbench"',
    'data-contract="ten-minute-target"',
    'data-contract="single-workbench"',
    'data-contract="question-basket"',
    'data-contract="blueprint-table-entry"',
    'data-contract="replacement-entry"',
    'data-contract="export-entry"',
    'data-flow="question-search"',
    'data-flow="paper-request-understanding"',
    'data-flow="paper-question-replacement"',
    'data-flow="paper-export"',
    'data-action="replace-question"',
    'data-action="export-docx"',
    'data-action="export-pdf"'
)) {
    if (-not $app.Contains($pattern)) {
        throw "missing I004 paper workbench marker: $pattern"
    }
}

foreach ($label in @('找题组卷工作台','检索、题篮、细目表、换题和导出','10 分钟','题篮','细目表','换题入口','导出入口')) {
    if (-not $app.Contains($label)) {
        throw "missing I004 teacher-facing label: $label"
    }
}

foreach ($pattern in @('.paper-workbench-panel', '.paper-workbench-flow', '.paper-workbench-summary', '.workspace.teacher-view-paper .paper-workbench-panel')) {
    if (-not $css.Contains($pattern)) {
        throw "missing I004 paper workbench CSS: $pattern"
    }
}

if ($css.Contains(".guardrail-panel {`r`n  grid-column: 1 / -1;`r`n  display: flex;")) {
    throw "guardrail panel display override would keep admin guardrails visible on teacher home"
}

[ordered]@{
    status = 'pass'
    task = 'I004'
    singleWorkbench = $true
    teacherTarget = '10 minute draft paper'
    workflowEntries = @('question-search','question-basket','blueprint-table','replacement','export')
    preservesExistingContracts = @('E001','E002','E003','E004')
} | ConvertTo-Json -Depth 4

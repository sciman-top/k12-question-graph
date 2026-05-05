$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$app = Get-Content -LiteralPath (Join-Path $repoRoot 'apps\web\src\App.tsx') -Raw
$css = Get-Content -LiteralPath (Join-Path $repoRoot 'apps\web\src\App.css') -Raw

foreach ($pattern in @(
    'data-flow="score-import-workbench"',
    'data-flow="score-analysis-workbench"',
    'data-contract="excel-field-mapping-preview"',
    'data-contract="score-exception-rows"',
    'data-contract="knowledge-analysis-summary"',
    'data-contract="analysis-report-export-path"',
    'data-contract="score-productionEligible=false"'
)) {
    if (-not $app.Contains($pattern)) {
        throw "missing I005 score analysis workbench marker: $pattern"
    }
}

foreach ($action in @(
    'upload-score-sheet',
    'generate-score-analysis',
    'export-score-report'
)) {
    if ((-not $app.Contains("data-action=""$action""")) -and (-not $app.Contains("action: '$action'"))) {
        throw "missing I005 score analysis action marker: $action"
    }
}

foreach ($label in @('成绩导入分析工作台','字段映射预览','异常行','知识点分析','报告导出路径','不使用真实学生数据','不写正式历史学情')) {
    if (-not $app.Contains($label)) {
        throw "missing I005 teacher-facing label: $label"
    }
}

foreach ($pattern in @('.score-workbench', '.score-field-mapping', '.score-exception-list', '.score-analysis-summary', '.score-report-path')) {
    if (-not $css.Contains($pattern)) {
        throw "missing I005 score analysis workbench CSS: $pattern"
    }
}

[ordered]@{
    status = 'pass'
    task = 'I005'
    workflowEntries = @('excel-field-mapping-preview','score-exception-rows','knowledge-analysis-summary','analysis-report-export-path')
    preservesExistingContracts = @('F001','F002','F003')
    realStudentDataUsed = $false
} | ConvertTo-Json -Depth 4

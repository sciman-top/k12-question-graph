$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$appPath = Join-Path $repoRoot 'apps\web\src\App.tsx'
$cssPath = Join-Path $repoRoot 'apps\web\src\App.css'

$app = Get-Content -LiteralPath $appPath -Raw
$css = Get-Content -LiteralPath $cssPath -Raw

foreach ($pattern in @(
    'data-flow="teacher-home"',
    'data-contract="four-default-actions"',
    'data-action="teacher-entry"',
    'data-view={action.view}',
    "type TeacherView = 'import' | 'paper' | 'scores' | 'analysis'",
    "useState<TeacherView>('import')",
    'data-flow="score-import-workbench"',
    'data-flow="teacher-analysis-workbench"'
)) {
    if (-not $app.Contains($pattern)) {
        throw "missing I001 teacher home marker: $pattern"
    }
}

foreach ($view in @("'import' as TeacherView", "'paper' as TeacherView", "'scores' as TeacherView", "'analysis' as TeacherView")) {
    if (-not $app.Contains($view)) {
        throw "missing I001 teacher action view: $view"
    }
}

foreach ($pattern in @(
    '.workspace.teacher-view-import .review-panel',
    '.workspace.teacher-view-paper .question-panel',
    '.workspace.teacher-view-scores .score-panel',
    '.workspace.teacher-view-analysis .analysis-panel',
    '.source-material-panel',
    '.activation-panel',
    '.storage-panel',
    '.guardrail-panel'
)) {
    if (-not $css.Contains($pattern)) {
        throw "missing I001 teacher home CSS guard: $pattern"
    }
}

if ($app.Contains('普通教师默认入口保持 4 个，高级配置后置。')) {
    throw "I001 should replace technical homepage copy with teacher-facing copy"
}

[ordered]@{
    status = 'pass'
    task = 'I001'
    defaultEntryCount = 4
    defaultView = 'import'
    adminPanelsHiddenByDefault = $true
    teacherViews = @('import','paper','scores','analysis')
} | ConvertTo-Json -Depth 4

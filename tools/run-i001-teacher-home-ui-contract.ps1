$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$appPath = Join-Path $repoRoot 'apps\web\src\App.tsx'
$cssPath = Join-Path $repoRoot 'apps\web\src\App.css'
$adminPanelsPath = Join-Path $repoRoot 'apps\web\src\ui\AdminGovernancePanels.tsx'

$app = Get-Content -LiteralPath $appPath -Raw
$css = Get-Content -LiteralPath $cssPath -Raw
$adminPanels = Get-Content -LiteralPath $adminPanelsPath -Raw
$uiSource = $app + "`n" + $adminPanels

$mainMatch = [regex]::Match($app, '<main\s+className=\{`workspace teacher-view-\$\{activeTeacherView\}`\}[\s\S]*?</main>')
if (-not $mainMatch.Success) {
    throw "missing I001 teacher workspace shell"
}
$teacherWorkspace = $mainMatch.Value

$analysisMatch = [regex]::Match($app, '<section\s+className="analysis-panel"[\s\S]*?</section>')
if (-not $analysisMatch.Success) {
    throw "missing I001 analysis panel section"
}
$teacherAnalysis = $analysisMatch.Value

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

foreach ($pattern in @(
    'className="admin-knowledge-panel"',
    'data-flow="admin-knowledge-governance"',
    'data-contract="advanced-admin-only"'
)) {
    if (-not $uiSource.Contains($pattern)) {
        throw "missing I001 admin boundary marker: $pattern"
    }
}

if ($app.Contains('className="admin-knowledge-panel"')) {
    throw "I001 teacher shell must not inline admin knowledge panel"
}

if ($teacherWorkspace.Contains('<AdminGovernancePanels />')) {
    throw "I001 teacher workspace must not mount admin governance panels"
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
    '.admin-knowledge-panel',
    '.source-material-panel',
    '.activation-panel',
    '.storage-panel',
    '.guardrail-panel',
    '.admin-workspace'
)) {
    if (-not $css.Contains($pattern)) {
        throw "missing I001 teacher home CSS guard: $pattern"
    }
}

if (-not $app.Contains('data-shell="admin-governance-staging"')) {
    throw "I001 must keep admin governance mounted outside the teacher workspace shell"
}

if ($app.Contains('普通教师默认入口保持 4 个，高级配置后置。')) {
    throw "I001 should replace technical homepage copy with teacher-facing copy"
}

foreach ($leak in @(
    'data-flow="c002r-teacher-revision-ux"',
    'data-flow="c002h-mapping-review-workbench-ui"',
    'revision-intake-panel',
    'mapping-review-panel',
    'candidate 版本',
    'active switch',
    'rollback snapshot',
    'migration'
)) {
    if ($teacherAnalysis.Contains($leak)) {
        throw "I001 teacher analysis view leaks advanced governance content: $leak"
    }
}

[ordered]@{
    status = 'pass'
    task = 'I001'
    defaultEntryCount = 4
    defaultView = 'import'
    adminPanelsHiddenByDefault = $true
    adminGovernanceMovedOutOfTeacherAnalysis = $true
    teacherViews = @('import','paper','scores','analysis')
} | ConvertTo-Json -Depth 4

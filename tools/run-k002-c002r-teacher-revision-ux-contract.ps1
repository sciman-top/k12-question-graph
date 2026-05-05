param(
    [string] $ReportPath = 'docs\evidence\k002-c002r-teacher-revision-ux-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$appPath = Join-Path $repoRoot 'apps\web\src\App.tsx'
$adminPanelsPath = Join-Path $repoRoot 'apps\web\src\ui\AdminGovernancePanels.tsx'
$app = Get-Content -LiteralPath $appPath -Raw
$adminPanels = Get-Content -LiteralPath $adminPanelsPath -Raw
$uiSource = $app + "`n" + $adminPanels
$css = Get-Content -LiteralPath (Join-Path $repoRoot 'apps\web\src\App.css') -Raw
$resolvedReportPath = Join-Path $repoRoot $ReportPath
$dependencyReportPath = 'tmp\k002-c002r-versioned-revision-dependency-report.json'

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

$c002rReportRaw = & (Join-Path $PSScriptRoot 'run-c002r-versioned-revision-contract.ps1') -ReportPath $dependencyReportPath
$c002rReport = $c002rReportRaw | ConvertFrom-Json
Assert-Condition ($c002rReport.status -eq 'pass') 'C002R dependency report must pass'
Assert-Condition ($c002rReport.teacherCanApplyActive -eq $false) 'teacher must not apply active in C002R dependency'

foreach ($pattern in @(
    'data-flow="c002r-teacher-revision-ux"',
    'data-contract="teacher-revision-low-friction"',
    'data-contract="teacher-required-fields"',
    'data-contract="system-generated-candidate-impact"',
    'data-contract="no-teacher-active-switch"',
    'data-contract="candidate-pending-review-only"',
    'data-active-version="junior-physics-guangzhou-source-derived-v1"'
)) {
    Assert-Condition ($uiSource.Contains($pattern)) "missing K002 UI marker: $pattern"
}

foreach ($action in @(
    'submit-c002r-teacher-revision',
    'preview-c002r-impact',
    'open-c002r-review-status'
)) {
    Assert-Condition (
        $uiSource.Contains("data-action=""$action""") -or
        $uiSource.Contains("action: '$action'")
    ) "missing K002 UI action: $action"
}

foreach ($label in @(
    '知识体系修订',
    '只提交 4 项信息',
    '修订原因',
    '来源证据',
    '影响范围',
    '紧急程度',
    'candidate 版本',
    '映射建议',
    '影响报告',
    '回滚快照',
    '不会直接修改当前正式知识体系'
)) {
    Assert-Condition ($uiSource.Contains($label)) "missing K002 teacher-facing label: $label"
}

foreach ($forbidden in @(
    'data-action="apply-c002r-active"',
    'data-action="run-c002r-migration"',
    'data-action="edit-active-c002"',
    'ApplyC002RActive',
    'EditActiveC002'
)) {
    Assert-Condition (-not $uiSource.Contains($forbidden)) "teacher revision UX must not expose high-risk action: $forbidden"
}

foreach ($technicalText in @(
    'importKey',
    'migration',
    'rollback snapshot',
    'active switch'
)) {
    Assert-Condition ($uiSource.Contains($technicalText)) "missing hidden technical boundary text: $technicalText"
}

foreach ($pattern in @(
    '.revision-intake-panel',
    '.revision-intake-grid',
    '.revision-output-grid',
    '.revision-actions',
    '@media (max-width: 900px)'
)) {
    Assert-Condition ($css.Contains($pattern)) "missing K002 style marker: $pattern"
}

$report = [ordered]@{
    status = 'pass'
    task = 'K002'
    mode = 'ui_contract'
    checkedAt = (Get-Date).ToUniversalTime().ToString('o')
    activeKnowledgeVersion = 'junior-physics-guangzhou-source-derived-v1'
    requiredTeacherFields = @('changeSummary', 'sourceEvidence', 'affectedScope', 'urgency')
    teacherVisibleLabels = @('修订原因', '来源证据', '影响范围', '紧急程度')
    systemGeneratedOutputs = @('candidateVersion', 'mappingSuggestions', 'impactReport', 'rollbackSnapshot')
    teacherCanApplyActive = $false
    noActiveWrite = $true
    productionEligible = $false
    dependency = [ordered]@{
        c002rContractStatus = [string]$c002rReport.status
        c002rPlanId = [string]$c002rReport.planId
        c002rReport = $dependencyReportPath.Replace('\', '/')
    }
    evidence = [ordered]@{
        ui = @('apps/web/src/App.tsx', 'apps/web/src/ui/AdminGovernancePanels.tsx')
        style = 'apps/web/src/App.css'
        report = $ReportPath.Replace('\', '/')
    }
    rollback = [ordered]@{
        code = 'git revert this K002 commit'
        data = 'no database or active asset mutation; remove only generated K002 evidence report if needed'
    }
}

New-Item -ItemType Directory -Path (Split-Path -Parent $resolvedReportPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedReportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8

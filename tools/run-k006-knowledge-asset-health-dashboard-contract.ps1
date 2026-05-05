param(
    [string] $ReportPath = 'docs\evidence\k006-knowledge-asset-health-dashboard-report.json'
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

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

foreach ($pattern in @(
    'data-flow="knowledge-asset-health-dashboard"',
    'data-contract="admin-health-summary"',
    'data-contract="active-version"',
    'data-contract="evidence-updated-at"',
    'data-contract="active-candidate-pending-summary"',
    'data-contract="evidence-summary"',
    'data-contract="admin-readonly-actions"',
    'data-contract="no-active-write"',
    'data-health-key={card.key}',
    'active',
    'candidate',
    'pending mappings',
    'migrations',
    'blockers',
    'docs/evidence/c002t-active-switch-report.json',
    'docs/evidence/k001-active-c002-production-query-report.json',
    'docs/evidence/k005-c002-second-revision-drill-report.json',
    '管理员查看 active、candidate、映射、迁移、阻断项和证据摘要',
    '只读健康面板'
)) {
    Assert-Condition ($uiSource.Contains($pattern)) "missing K006 UI marker: $pattern"
}

foreach ($action in @(
    'data-action="open-knowledge-health-evidence"',
    'data-action="open-pending-mapping-review"',
    'data-action="open-migration-history"',
    'data-action="open-blocker-report"'
)) {
    Assert-Condition ($uiSource.Contains($action)) "missing K006 readonly action: $action"
}

foreach ($forbidden in @(
    'data-action="apply-knowledge-active"',
    'data-action="run-knowledge-migration"',
    'data-action="apply-c002r-revision"',
    'data-action="switch-active-version"',
    'ApplyKnowledgeActive',
    'RunKnowledgeMigration'
)) {
    Assert-Condition (-not $uiSource.Contains($forbidden)) "K006 health dashboard must not expose mutation action: $forbidden"
}

foreach ($pattern in @(
    '.knowledge-health-panel',
    '.knowledge-health-grid',
    '.knowledge-health-card',
    '.knowledge-health-evidence',
    '.knowledge-evidence-list',
    '.knowledge-evidence-row',
    '.knowledge-health-actions',
    '@media (max-width: 900px)'
)) {
    Assert-Condition ($css.Contains($pattern)) "missing K006 style marker: $pattern"
}

$report = [ordered]@{
    status = 'pass'
    task = 'K006'
    mode = 'ui_contract'
    checkedAt = (Get-Date).ToUniversalTime().ToString('o')
    dashboard = 'knowledge-asset-health-dashboard'
    coveredStatusFields = @('active', 'candidate', 'pending_mappings', 'migrations', 'blockers')
    evidenceSummaries = @(
        'docs/evidence/c002t-active-switch-report.json',
        'docs/evidence/k001-active-c002-production-query-report.json',
        'docs/evidence/k005-c002-second-revision-drill-report.json'
    )
    readonlyActions = @(
        'open-knowledge-health-evidence',
        'open-pending-mapping-review',
        'open-migration-history',
        'open-blocker-report'
    )
    activeWriteAllowed = $false
    migrationApplyAllowed = $false
    teacherFacingTechnicalBurden = $false
    evidence = [ordered]@{
        ui = @('apps/web/src/App.tsx', 'apps/web/src/ui/AdminGovernancePanels.tsx')
        style = 'apps/web/src/App.css'
        report = $ReportPath.Replace('\', '/')
    }
    rollback = [ordered]@{
        code = 'git revert this K006 commit'
        data = 'no database, active asset, migration, or production history write is performed by this UI contract'
    }
}

New-Item -ItemType Directory -Path (Split-Path -Parent $resolvedReportPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedReportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8

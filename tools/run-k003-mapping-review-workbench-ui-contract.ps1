param(
    [string] $ReportPath = 'docs\evidence\k003-mapping-review-workbench-ui-report.json'
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

$c002hRaw = & (Join-Path $PSScriptRoot 'run-c002h-mapping-review-workbench-contract.ps1')
$c002h = $c002hRaw | ConvertFrom-Json
Assert-Condition ($c002h.status -eq 'pass') 'C002H dependency contract must pass'
Assert-Condition ($c002h.manualReview -ge 2) 'C002H dependency must include manual review items'
Assert-Condition ($c002h.undoRequiredBeforeApply -eq $true) 'C002H dependency must require undo before apply'

foreach ($pattern in @(
    'data-flow="c002h-mapping-review-workbench-ui"',
    'data-contract="complex-mapping-review"',
    'data-contract="side-by-side-review"',
    'data-contract="old-new-asset-compare"',
    'data-contract="manual-review-actions"',
    'data-contract="review-history-and-audit"',
    'data-contract="batch-approve-one-to-one-only"',
    'data-contract="no-direct-active-apply"',
    'data-view="old_asset"',
    'data-view="new_asset"',
    'data-view="mapping_edges"',
    'data-view="source_evidence"',
    'data-view="impact_preview"',
    'data-view="rollback_preview"'
)) {
    Assert-Condition ($uiSource.Contains($pattern)) "missing K003 UI marker: $pattern"
}

foreach ($pattern in @(
    'data-filter="pending_review"',
    'data-filter="low_confidence"',
    'data-filter="high_impact"',
    'data-filter="many_to_many"',
    'data-mapping-type={item.mappingType}',
    "mappingType: 'split'",
    "mappingType: 'merge'",
    "mappingType: 'deprecated'",
    "cardinality: 'one_to_many'",
    "cardinality: 'many_to_many'",
    "risk: 'high'"
)) {
    Assert-Condition ($uiSource.Contains($pattern)) "missing K003 filter or mapping marker: $pattern"
}

foreach ($action in @(
    'data-action="approve-mapping"',
    'data-action="change-mapping-target"',
    'data-action="split-mapping"',
    'data-action="merge-mapping"',
    'data-action="undo-mapping-review"'
)) {
    Assert-Condition ($uiSource.Contains($action)) "missing K003 review action: $action"
}

foreach ($label in @(
    '映射审核',
    '高影响映射并排审核',
    'split、merge、deprecated 必须逐项给出审核理由',
    '旧对象',
    '新对象',
    '来源证据已绑定',
    '审核记录包含 reviewer、decision、reviewReason、beforeSnapshot 和 afterSnapshot',
    '批量确认只允许低风险一对一',
    '不直接应用到 active'
)) {
    Assert-Condition ($uiSource.Contains($label)) "missing K003 teacher-facing label: $label"
}

foreach ($forbidden in @(
    'data-action="batch-approve-high-risk"',
    'data-action="apply-mapping-active"',
    'data-action="run-mapping-migration"',
    'ApplyMappingActive'
)) {
    Assert-Condition (-not $uiSource.Contains($forbidden)) "mapping review UI must not expose high-risk action: $forbidden"
}

foreach ($pattern in @(
    '.mapping-review-panel',
    '.mapping-review-grid',
    '.mapping-review-card',
    '.mapping-compare',
    '.mapping-evidence-row',
    '.mapping-review-actions',
    '.mapping-review-audit',
    '@media (max-width: 900px)'
)) {
    Assert-Condition ($css.Contains($pattern)) "missing K003 style marker: $pattern"
}

$report = [ordered]@{
    status = 'pass'
    task = 'K003'
    mode = 'ui_contract'
    checkedAt = (Get-Date).ToUniversalTime().ToString('o')
    dependency = [ordered]@{
        c002hStatus = [string]$c002h.status
        c002hPlanId = [string]$c002h.planId
        c002hManualReview = [int]$c002h.manualReview
        c002hCoveredCardinalities = @($c002h.coveredCardinalities)
    }
    coveredMappingTypes = @('split', 'merge', 'deprecated')
    sideBySideViews = @('old_asset', 'new_asset', 'mapping_edges', 'source_evidence', 'impact_preview', 'rollback_preview')
    highRiskBulkApproveAllowed = $false
    directActiveApplyAllowed = $false
    undoRequiredBeforeApply = $true
    evidence = [ordered]@{
        ui = @('apps/web/src/App.tsx', 'apps/web/src/ui/AdminGovernancePanels.tsx')
        style = 'apps/web/src/App.css'
        report = $ReportPath.Replace('\', '/')
    }
    rollback = [ordered]@{
        code = 'git revert this K003 commit'
        data = 'no database or active asset mutation; remove only generated K003 evidence report if needed'
    }
}

New-Item -ItemType Directory -Path (Split-Path -Parent $resolvedReportPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedReportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8

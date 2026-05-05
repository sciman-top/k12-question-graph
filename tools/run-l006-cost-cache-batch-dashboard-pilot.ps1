param(
    [string] $AdminPanelPath = 'apps\web\src\ui\AdminGovernancePanels.tsx',
    [string] $L006EvidencePath = 'docs\evidence\20260505-l006-cost-cache-batch-dashboard-pilot.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

$adminPanel = Get-Content -LiteralPath (Join-Path $repoRoot $AdminPanelPath) -Raw
foreach ($pattern in @(
    'data-flow="admin-storage-dashboard"',
    'data-contract="cache-cleanup-configured-root"',
    'cache-cleanup-dry-run',
    'open-knowledge-health-evidence'
)) {
    Assert-True ($adminPanel.Contains($pattern)) "L006 admin dashboard missing marker: $pattern"
}

Assert-True ((Test-Path -LiteralPath (Join-Path $repoRoot 'tools\run-d002-ai-job-cost-contract.ps1'))) 'L006 requires D002 cost contract entrypoint'

$evidence = Get-Content -LiteralPath (Join-Path $repoRoot $L006EvidencePath) -Raw
foreach ($keyword in @(
    '任务成本',
    'cache hit',
    '模型路由',
    '异常失败原因',
    '管理员可见'
)) {
    Assert-True ($evidence.Contains($keyword)) "L006 evidence missing keyword: $keyword"
}

[ordered]@{
    status = 'pass'
    taskId = 'L006'
    adminPanelPath = $AdminPanelPath
    l006EvidencePath = $L006EvidencePath
    d002ContractEntrypoint = 'tools/run-d002-ai-job-cost-contract.ps1'
    checkedAt = (Get-Date).ToString('s')
} | ConvertTo-Json

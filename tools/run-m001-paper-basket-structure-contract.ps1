param(
    [string] $AppPath = 'apps\web\src\App.tsx',
    [string] $K001ReportPath = 'docs\evidence\k001-active-c002-production-query-report.json',
    [string] $M001EvidencePath = 'docs\evidence\20260505-m001-paper-basket-structure-contract.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

$app = Get-Content -LiteralPath (Join-Path $repoRoot $AppPath) -Raw
foreach ($marker in @(
    'data-flow="paper-assembly-workbench"',
    'question-basket',
    '题篮',
    '细目表',
    '换题',
    '导出'
)) {
    Assert-True ($app.Contains($marker)) "M001 UI marker missing: $marker"
}

Assert-True ((Test-Path -LiteralPath (Join-Path $repoRoot 'tools\run-e002-paper-request-contract.ps1'))) 'M001 requires E002 API contract entrypoint'
Assert-True ((Test-Path -LiteralPath (Join-Path $repoRoot 'tools\run-e003-question-replacement-contract.ps1'))) 'M001 requires E003 API contract entrypoint'

$k001 = Get-Content -LiteralPath (Join-Path $repoRoot $K001ReportPath) -Raw | ConvertFrom-Json
Assert-True ($k001.status -eq 'pass') 'M001 requires K001 production query contract pass'
Assert-True (-not [string]::IsNullOrWhiteSpace([string]$k001.activeKnowledgeVersion)) 'M001 requires active knowledge version reference'

$evidence = Get-Content -LiteralPath (Join-Path $repoRoot $M001EvidencePath) -Raw
foreach ($keyword in @(
    '题篮',
    '试卷结构',
    '分值',
    '题号',
    '小问',
    '版本引用可保存和复现'
)) {
    Assert-True ($evidence.Contains($keyword)) "M001 evidence missing keyword: $keyword"
}

[ordered]@{
    status = 'pass'
    taskId = 'M001'
    appPath = $AppPath
    k001ReportPath = $K001ReportPath
    m001EvidencePath = $M001EvidencePath
    activeKnowledgeVersion = [string]$k001.activeKnowledgeVersion
    checkedAt = (Get-Date).ToString('s')
} | ConvertTo-Json

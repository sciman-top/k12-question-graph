param(
    [string] $K001ReportPath = 'docs\evidence\k001-active-c002-production-query-report.json',
    [string] $C002OReportPath = 'docs\evidence\c002o-candidate-extraction-eval-report.json',
    [string] $L004EvidencePath = 'docs\evidence\20260505-l004-knowledge-tagging-suggestion-pilot.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

$k001 = Get-Content -LiteralPath (Join-Path $repoRoot $K001ReportPath) -Raw | ConvertFrom-Json
Assert-True ($k001.status -eq 'pass') 'L004 requires K001 production query contract pass'
Assert-True (-not [string]::IsNullOrWhiteSpace([string]$k001.activeKnowledgeVersion)) 'L004 requires active knowledge version reference'

$c002o = Get-Content -LiteralPath (Join-Path $repoRoot $C002OReportPath) -Raw | ConvertFrom-Json
Assert-True ($c002o.status -eq 'pass') 'L004 requires C002O eval report pass'
Assert-True ($c002o.productionEligible -eq $false) 'L004 suggestion output must remain non-production'
Assert-True (@($c002o.cases).Count -ge 1) 'L004 requires at least one C002O case'

$evidence = Get-Content -LiteralPath (Join-Path $repoRoot $L004EvidencePath) -Raw
foreach ($keyword in @(
    'AI 标注只作为建议',
    '绑定 active 知识版本',
    '人工修改生成 FeedbackEvent',
    'pending_review',
    '未进入 active'
)) {
    Assert-True ($evidence.Contains($keyword)) "L004 evidence missing keyword: $keyword"
}

[ordered]@{
    status = 'pass'
    taskId = 'L004'
    k001ReportPath = $K001ReportPath
    c002oReportPath = $C002OReportPath
    l004EvidencePath = $L004EvidencePath
    activeKnowledgeVersion = [string]$k001.activeKnowledgeVersion
    c002oCaseCount = @($c002o.cases).Count
    checkedAt = (Get-Date).ToString('s')
} | ConvertTo-Json

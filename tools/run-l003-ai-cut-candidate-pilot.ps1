param(
    [string] $ImportAccuracyReportPath = 'docs\evidence\j006-import-accuracy-workload-report.json',
    [string] $L001EvidencePath = 'docs\evidence\20260505-l001-real-model-admission-card.md',
    [string] $L003EvidencePath = 'docs\evidence\20260505-l003-ai-cut-candidate-pilot.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

$j006 = Get-Content -LiteralPath (Join-Path $repoRoot $ImportAccuracyReportPath) -Raw | ConvertFrom-Json
Assert-True ($j006.status -eq 'pass') 'L003 requires J006 accuracy/workload baseline pass'
Assert-True ($j006.externalAiCalls -eq 0) 'L003 baseline requires external AI calls = 0 before pilot'
Assert-True ($j006.accuracy.automatedCutCaseCount -eq 0) 'L003 baseline requires no automated cut production claim'
Assert-True ($j006.teacherWorkload.manualReviewRequired -eq $true) 'L003 baseline requires manual review path'

$l001 = Get-Content -LiteralPath (Join-Path $repoRoot $L001EvidencePath) -Raw
Assert-True (($l001.Contains('no active write')) -or ($l001.Contains('noActiveWrite=true'))) 'L003 requires L001 no active write boundary'

$evidence = Get-Content -LiteralPath (Join-Path $repoRoot $L003EvidencePath) -Raw
foreach ($keyword in @(
    '只产候选',
    '低置信度进入确认队列',
    '原文件可接管',
    'pending_review',
    '未进入 active'
)) {
    Assert-True ($evidence.Contains($keyword)) "L003 evidence missing keyword: $keyword"
}

[ordered]@{
    status = 'pass'
    taskId = 'L003'
    importAccuracyReportPath = $ImportAccuracyReportPath
    l001EvidencePath = $L001EvidencePath
    l003EvidencePath = $L003EvidencePath
    externalAiCalls = $j006.externalAiCalls
    automatedCutCaseCount = $j006.accuracy.automatedCutCaseCount
    manualReviewRequired = $j006.teacherWorkload.manualReviewRequired
    checkedAt = (Get-Date).ToString('s')
} | ConvertTo-Json

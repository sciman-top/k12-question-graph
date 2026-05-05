param(
    [string] $D003SuitePath = 'configs\ai-evals\d003-structured-output-evals.sample.json',
    [string] $L005EvidencePath = 'docs\evidence\20260505-l005-answer-verification-quality-pilot.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

$d003 = Get-Content -LiteralPath (Join-Path $repoRoot $D003SuitePath) -Raw | ConvertFrom-Json
Assert-True ($d003.mode -eq 'draft_test') 'L005 requires D003 draft_test mode'
Assert-True ($d003.allowRealModelCalls -eq $false) 'L005 requires no real model calls in D003 baseline'

$answerCase = @($d003.cases | Where-Object { $_.taskType -eq 'answer_verification' })
Assert-True ($answerCase.Count -ge 1) 'L005 requires answer_verification case in D003 suite'
Assert-True ([string]$answerCase[0].expectedReviewStatus -eq 'pending_review') 'L005 answer verification must stay pending_review'

$evidence = Get-Content -LiteralPath (Join-Path $repoRoot $L005EvidencePath) -Raw
foreach ($keyword in @(
    '保留来源',
    '置信度',
    '不自动覆盖教师答案',
    'pending_review',
    '未进入 active'
)) {
    Assert-True ($evidence.Contains($keyword)) "L005 evidence missing keyword: $keyword"
}

[ordered]@{
    status = 'pass'
    taskId = 'L005'
    d003SuitePath = $D003SuitePath
    l005EvidencePath = $L005EvidencePath
    answerVerificationCaseId = [string]$answerCase[0].caseId
    reviewStatus = [string]$answerCase[0].expectedReviewStatus
    checkedAt = (Get-Date).ToString('s')
} | ConvertTo-Json

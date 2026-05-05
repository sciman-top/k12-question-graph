param(
    [string] $DryRunReportPath = 'docs\evidence\c002q-ai-extract-dry-run-report.json',
    [string] $ReadinessReportPath = 'docs\evidence\c002q0-outer-ai-readiness-report.json',
    [string] $HumanReviewEvidencePath = 'docs\evidence\20260505-l002-real-ai-extract-human-review.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

$dryRun = Get-Content -LiteralPath (Join-Path $repoRoot $DryRunReportPath) -Raw | ConvertFrom-Json
Assert-True ($dryRun.status -eq 'pass') 'L002 requires passing C002Q dry-run report'
Assert-True ($dryRun.sample.cacheHitChunks -ge 1) 'L002 requires cache-hit sample chunks'
Assert-True ($dryRun.sample.sourceDocuments -le 4) 'L002 sample sourceDocuments exceeds guard'
Assert-True ($dryRun.sample.chunksTotal -le 32) 'L002 sample chunks exceed guard'
Assert-True ($dryRun.reviewStatus -eq 'pending_review') 'L002 outputs must remain pending_review'
Assert-True ($dryRun.productionEligible -eq $false) 'L002 outputs must remain non-production'
Assert-True ($dryRun.overwritesExistingC002K -eq $false) 'L002 must not overwrite C002K'

$readiness = Get-Content -LiteralPath (Join-Path $repoRoot $ReadinessReportPath) -Raw | ConvertFrom-Json
Assert-True ($readiness.status -eq 'pass') 'L002 requires passing C002Q0 readiness report'
Assert-True ($readiness.noActiveWrite -eq $true) 'L002 requires no active write'
Assert-True ($readiness.humanReviewRequired -eq $true) 'L002 requires human review boundary'

$humanReview = Get-Content -LiteralPath (Join-Path $repoRoot $HumanReviewEvidencePath) -Raw
foreach ($keyword in @(
    'candidate/pending_review',
    '不覆盖 C002K',
    '人工复核结论',
    '下一步',
    '未进入 active'
)) {
    Assert-True ($humanReview.Contains($keyword)) "L002 human review evidence missing keyword: $keyword"
}

[ordered]@{
    status = 'pass'
    taskId = 'L002'
    dryRunReportPath = $DryRunReportPath
    readinessReportPath = $ReadinessReportPath
    humanReviewEvidencePath = $HumanReviewEvidencePath
    sourceDocuments = $dryRun.sample.sourceDocuments
    chunksTotal = $dryRun.sample.chunksTotal
    cacheHitChunks = $dryRun.sample.cacheHitChunks
    noActiveWrite = $readiness.noActiveWrite
    humanReviewRequired = $readiness.humanReviewRequired
    checkedAt = (Get-Date).ToString('s')
} | ConvertTo-Json

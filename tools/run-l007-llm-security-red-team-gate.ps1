param(
    [string] $GateDocPath = 'docs\98_L007_LlmSecurityRedTeamGate.md',
    [string] $ReadinessReportPath = 'docs\evidence\c002q0-outer-ai-readiness-report.json',
    [string] $DryRunReportPath = 'docs\evidence\c002q-ai-extract-dry-run-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

$gateDoc = Get-Content -LiteralPath (Join-Path $repoRoot $GateDocPath) -Raw
foreach ($keyword in @(
    'prompt injection',
    'sensitive information disclosure',
    'insecure output handling',
    'supply chain',
    'vector or embedding weakness',
    'excessive agency',
    'OWASP LLM Top 10',
    'NIST AI RMF',
    'noActiveWrite',
    'pending_review'
)) {
    Assert-True ($gateDoc.Contains($keyword)) "L007 gate doc missing keyword: $keyword"
}

$readiness = Get-Content -LiteralPath (Join-Path $repoRoot $ReadinessReportPath) -Raw | ConvertFrom-Json
Assert-True ($readiness.status -eq 'pass') 'C002Q0 readiness must pass before L007'
Assert-True ($readiness.allowProjectRuntimeRealModelCalls -eq $false) 'runtime real model calls must remain disabled in L007 gate'
Assert-True ($readiness.noActiveWrite -eq $true) 'L007 requires no active write guard'
Assert-True ($readiness.humanReviewRequired -eq $true) 'L007 requires human review guard'

$dryRun = Get-Content -LiteralPath (Join-Path $repoRoot $DryRunReportPath) -Raw | ConvertFrom-Json
Assert-True ($dryRun.status -eq 'pass') 'C002Q dry-run report must pass before L007'
Assert-True ($dryRun.allowRealModelCalls -eq $false) 'L007 baseline requires dry-run without real model calls'
Assert-True ($dryRun.externalAiCalls -eq 0) 'L007 baseline requires zero external AI calls in dry-run'
Assert-True ($dryRun.noActiveWrite -eq $true) 'L007 baseline requires no active write in dry-run'
Assert-True ($dryRun.reviewStatus -eq 'pending_review') 'L007 baseline requires pending_review output'

[ordered]@{
    status = 'pass'
    taskId = 'L007'
    gateDocPath = $GateDocPath
    readinessReportPath = $ReadinessReportPath
    dryRunReportPath = $DryRunReportPath
    owaspNistChecklist = 'locked'
    noActiveWrite = $readiness.noActiveWrite
    humanReviewRequired = $readiness.humanReviewRequired
    dryRunExternalAiCalls = $dryRun.externalAiCalls
    checkedAt = (Get-Date).ToString('s')
} | ConvertTo-Json

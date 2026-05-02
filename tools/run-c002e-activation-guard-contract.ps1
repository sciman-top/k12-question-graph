param(
    [string] $ActivationPlanPath = 'configs\domain-assets\c002e-activation-guard.sample.json',
    [string] $AdmissionPlanPath = 'configs\domain-assets\c002d-source-derived-admission.sample.json',
    [string] $ReplacementPlanPath = 'configs\domain-assets\c002b-draft-formal-mapping.sample.json',
    [string] $ImpactPlanPath = 'configs\domain-assets\c002c-migration-impact.sample.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$activationPlan = Get-Content -LiteralPath (Resolve-Path -LiteralPath (Join-Path $repoRoot $ActivationPlanPath)) -Raw | ConvertFrom-Json
$admissionPlan = Get-Content -LiteralPath (Resolve-Path -LiteralPath (Join-Path $repoRoot $AdmissionPlanPath)) -Raw | ConvertFrom-Json
$replacementPlan = Get-Content -LiteralPath (Resolve-Path -LiteralPath (Join-Path $repoRoot $ReplacementPlanPath)) -Raw | ConvertFrom-Json
$impactPlan = Get-Content -LiteralPath (Resolve-Path -LiteralPath (Join-Path $repoRoot $ImpactPlanPath)) -Raw | ConvertFrom-Json

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

Assert-Condition ($activationPlan.schemaVersion -eq 'source-derived-ontology-activation-guard.v0.1') "unexpected C002E schemaVersion"
Assert-Condition ($activationPlan.mode -eq 'dry_run') "C002E activation guard must stay dry_run"
Assert-Condition ($activationPlan.admissionPlanId -eq $admissionPlan.planId) "C002E admissionPlanId mismatch"
Assert-Condition ($activationPlan.replacementPlanId -eq $replacementPlan.planId) "C002E replacementPlanId mismatch"
Assert-Condition ($activationPlan.impactPlanId -eq $impactPlan.planId) "C002E impactPlanId mismatch"
Assert-Condition ($activationPlan.targetStatus -eq 'active') "C002E must guard active transition"
Assert-Condition ($activationPlan.activationAllowed -eq $false) "C002E sample must block activation while review is pending"

$candidateAssets = @($admissionPlan.candidateAssets)
$pendingCandidateReviews = @($candidateAssets | Where-Object reviewStatus -ne 'approved')
Assert-Condition ($pendingCandidateReviews.Count -gt 0) "C002E sample must include pending candidate reviews"
Assert-Condition ($candidateAssets.Count -eq [int]$activationPlan.dryRunEvidence.candidateAssets) "candidateAssets evidence mismatch"

$pendingReviewMappings = @($replacementPlan.mappings | Where-Object expectedDecision -eq 'pending_review')
Assert-Condition ($pendingReviewMappings.Count -eq [int]$activationPlan.dryRunEvidence.pendingReviewMappings) "pendingReviewMappings evidence mismatch"

$pendingReviewImpacts = 0
$frozenHistoricalReports = 0
$autoApplyImpacts = 0
foreach ($impact in @($impactPlan.impacts)) {
    if ($impact.mappingDecision -eq 'pending_review') {
        $pendingReviewImpacts += [int]$impact.affectedCount
    }
    if ($impact.impactType -eq 'analysis_metric' -and $impact.action -eq 'freeze_historical_snapshot') {
        $frozenHistoricalReports += [int]$impact.affectedCount
    }
    if ($impact.mappingDecision -eq 'auto_apply') {
        $autoApplyImpacts += [int]$impact.affectedCount
    }
}
Assert-Condition ($pendingReviewImpacts -eq [int]$activationPlan.dryRunEvidence.pendingReviewImpacts) "pendingReviewImpacts evidence mismatch"
Assert-Condition ($frozenHistoricalReports -eq [int]$activationPlan.dryRunEvidence.frozenHistoricalReports) "frozenHistoricalReports evidence mismatch"
Assert-Condition ($autoApplyImpacts -eq [int]$activationPlan.dryRunEvidence.autoApplyImpacts) "autoApplyImpacts evidence mismatch"
Assert-Condition ($activationPlan.dryRunEvidence.rollbackSnapshotRequired -eq $true) "rollback snapshot must be required"

$blockers = @($activationPlan.blockers)
foreach ($requiredBlocker in @('teacher_review_pending','pending_review_mappings','historical_analysis_frozen_not_approved')) {
    $blocker = $blockers | Where-Object blockerId -eq $requiredBlocker
    Assert-Condition (@($blocker).Count -eq 1) "missing required activation blocker: $requiredBlocker"
    Assert-Condition ([string]$blocker[0].severity -eq 'hard') "activation blocker must be hard: $requiredBlocker"
}

Assert-Condition ([int]$activationPlan.requiredBeforeActivation.pendingReviewMappings -eq 0) "activation requires zero pendingReviewMappings"
Assert-Condition ([int]$activationPlan.requiredBeforeActivation.pendingReviewImpacts -eq 0) "activation requires zero pendingReviewImpacts"
Assert-Condition ($activationPlan.requiredBeforeActivation.rollbackSnapshotReady -eq $true) "activation requires rollbackSnapshotReady"
Assert-Condition ($activationPlan.requiredBeforeActivation.sourceEvidenceComplete -eq $true) "activation requires sourceEvidenceComplete"

[ordered]@{
    status = 'pass'
    planId = [string]$activationPlan.planId
    mode = [string]$activationPlan.mode
    activationAllowed = [bool]$activationPlan.activationAllowed
    blockers = @($blockers | ForEach-Object { $_.blockerId })
    candidateAssets = $candidateAssets.Count
    pendingCandidateReviews = $pendingCandidateReviews.Count
    pendingReviewMappings = $pendingReviewMappings.Count
    pendingReviewImpacts = $pendingReviewImpacts
    frozenHistoricalReports = $frozenHistoricalReports
    rollbackSnapshotRequired = [bool]$activationPlan.dryRunEvidence.rollbackSnapshotRequired
} | ConvertTo-Json -Depth 8

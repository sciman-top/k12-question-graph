param(
    [string] $ImpactPlanPath = 'configs\domain-assets\c002c-migration-impact.sample.json',
    [string] $ReplacementPlanPath = 'configs\domain-assets\c002b-draft-formal-mapping.sample.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$impactPlan = Get-Content -LiteralPath (Resolve-Path -LiteralPath (Join-Path $repoRoot $ImpactPlanPath)) -Raw | ConvertFrom-Json
$replacementPlan = Get-Content -LiteralPath (Resolve-Path -LiteralPath (Join-Path $repoRoot $ReplacementPlanPath)) -Raw | ConvertFrom-Json

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

Assert-Condition ($impactPlan.schemaVersion -eq 'domain-asset-migration-impact.v0.1') "unexpected C002C schemaVersion"
Assert-Condition ($impactPlan.mode -eq 'dry_run') "C002C impact contract must stay dry_run"
Assert-Condition ($impactPlan.replacementPlanId -eq $replacementPlan.planId) "C002C replacementPlanId mismatch"
Assert-Condition ($impactPlan.rollback.snapshotRequired -eq $true) "C002C rollback snapshot is required"
Assert-Condition ($impactPlan.autoApplyPolicy.requireRollbackSnapshot -eq $true) "C002C auto apply must require rollback snapshot"
Assert-Condition ($impactPlan.autoApplyPolicy.forbidHistoricalAnalysisRewrite -eq $true) "C002C must forbid historical analysis rewrite"

$mappingDecisionBySource = @{}
foreach ($mapping in @($replacementPlan.mappings)) {
    $decision = [string]$mapping.expectedDecision
    if (-not $mappingDecisionBySource.ContainsKey($mapping.sourceStableId)) {
        $mappingDecisionBySource[$mapping.sourceStableId] = New-Object System.Collections.Generic.List[string]
    }
    $mappingDecisionBySource[$mapping.sourceStableId].Add($decision)
}

$allowedImpactTypes = @(
    'question_primary_knowledge',
    'question_secondary_knowledge',
    'tag_binding',
    'search_index',
    'assembly_constraint',
    'analysis_metric',
    'fixture_expected_mapping'
)
$autoActions = @('update_binding','rebuild_derived_index','update_fixture_expectation')
$manualActions = @('hold_for_review','freeze_historical_snapshot')

$impacts = @($impactPlan.impacts)
Assert-Condition ($impacts.Count -gt 0) "C002C impacts are empty"

$seenImpactTypes = New-Object System.Collections.Generic.HashSet[string]
$autoApplyCount = 0
$pendingReviewCount = 0
$frozenHistoricalReports = 0

foreach ($impact in $impacts) {
    $impactType = [string]$impact.impactType
    $assetStableId = [string]$impact.assetStableId
    $decision = [string]$impact.mappingDecision
    $action = [string]$impact.action
    $affectedCount = [int]$impact.affectedCount
    $requiresReview = [bool]$impact.requiresReview

    Assert-Condition ($allowedImpactTypes -contains $impactType) "invalid impactType: $impactType"
    Assert-Condition ($mappingDecisionBySource.ContainsKey($assetStableId)) "impact asset has no replacement mapping: $assetStableId"
    Assert-Condition ($mappingDecisionBySource[$assetStableId] -contains $decision) "impact decision does not match replacement plan: $assetStableId $decision"
    Assert-Condition ($affectedCount -ge 0) "affectedCount must be non-negative"
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($impact.rollbackKey)) "rollbackKey is required"
    [void]$seenImpactTypes.Add($impactType)

    if ($decision -eq 'auto_apply') {
        Assert-Condition ($requiresReview -eq $false) "auto_apply impact cannot require review: $assetStableId"
        Assert-Condition ($autoActions -contains $action) "auto_apply impact has invalid action: $action"
        Assert-Condition ($impactType -ne 'analysis_metric') "analysis metrics must not be auto-applied"
        $autoApplyCount += $affectedCount
    }
    elseif ($decision -eq 'pending_review') {
        Assert-Condition ($requiresReview -eq $true) "pending_review impact must require review: $assetStableId"
        Assert-Condition ($manualActions -contains $action) "pending_review impact has invalid action: $action"
        $pendingReviewCount += $affectedCount
        if ($impactType -eq 'analysis_metric') {
            Assert-Condition ($action -eq 'freeze_historical_snapshot') "analysis metrics must freeze historical snapshots"
            $frozenHistoricalReports += $affectedCount
        }
    }
    else {
        throw "invalid mappingDecision: $decision"
    }
}

foreach ($requiredImpactType in $allowedImpactTypes) {
    Assert-Condition ($seenImpactTypes.Contains($requiredImpactType)) "C002C sample must cover impact type: $requiredImpactType"
}

Assert-Condition ($autoApplyCount -eq [int]$impactPlan.summary.autoApplyCount) "autoApplyCount summary mismatch"
Assert-Condition ($pendingReviewCount -eq [int]$impactPlan.summary.pendingReviewCount) "pendingReviewCount summary mismatch"
Assert-Condition ($frozenHistoricalReports -eq [int]$impactPlan.summary.frozenHistoricalReports) "frozenHistoricalReports summary mismatch"
Assert-Condition ($impactPlan.summary.rollbackSnapshotRequired -eq $true) "summary rollbackSnapshotRequired must be true"

[ordered]@{
    status = 'pass'
    planId = [string]$impactPlan.planId
    mode = [string]$impactPlan.mode
    replacementPlanId = [string]$impactPlan.replacementPlanId
    impacts = $impacts.Count
    coveredImpactTypes = @($seenImpactTypes | Sort-Object)
    autoApplyCount = $autoApplyCount
    pendingReviewCount = $pendingReviewCount
    frozenHistoricalReports = $frozenHistoricalReports
    rollbackSnapshotRequired = [bool]$impactPlan.summary.rollbackSnapshotRequired
} | ConvertTo-Json -Depth 8

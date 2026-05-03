param(
    [string] $PlanPath = 'configs\domain-assets\c002h-mapping-review-workbench.sample.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$resolvedPlanPath = (Resolve-Path -LiteralPath (Join-Path $repoRoot $PlanPath)).Path
$plan = Get-Content -LiteralPath $resolvedPlanPath -Raw | ConvertFrom-Json

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

$allowedCardinalities = @('one_to_one','one_to_many','many_to_one','many_to_many')
$manualCardinalities = @('one_to_many','many_to_one','many_to_many')
$requiredFilters = @('pending_review','low_confidence','high_impact','one_to_many','many_to_one','many_to_many')
$requiredViews = @('old_asset','new_asset','mapping_edges','source_evidence','impact_preview','rollback_preview','review_history')
$requiredKeyboardActions = @('approve','reject','skip','change_target','split','merge','create_group','undo')
$requiredAuditFields = @('reviewerId','decision','reviewReason','decidedAt','beforeSnapshot','afterSnapshot')

Assert-Condition ($plan.schemaVersion -eq 'domain-asset-mapping-review-workbench.v0.1') "unexpected C002H schemaVersion"
Assert-Condition ($plan.mode -eq 'dry_run') "C002H workbench contract must stay dry_run"
Assert-Condition (-not [string]::IsNullOrWhiteSpace($plan.sourceReplacementPlanId)) "sourceReplacementPlanId is required"

$workbench = $plan.workbench
foreach ($filter in $requiredFilters) {
    Assert-Condition (@($workbench.requiredFilters) -contains $filter) "missing workbench filter: $filter"
}
foreach ($view in $requiredViews) {
    Assert-Condition (@($workbench.requiredViews) -contains $view) "missing workbench view: $view"
}
foreach ($action in $requiredKeyboardActions) {
    Assert-Condition (@($workbench.keyboardActions) -contains $action) "missing keyboard action: $action"
}

$reviewItems = @($plan.reviewItems)
Assert-Condition ($reviewItems.Count -gt 0) "reviewItems must not be empty"

$seenCardinalities = New-Object System.Collections.Generic.HashSet[string]
$manualReviewCount = 0
$autoEligibleCount = 0

foreach ($item in $reviewItems) {
    $cardinality = [string]$item.cardinality
    $riskLevel = [string]$item.riskLevel
    $confidence = [decimal]$item.confidence
    $sourceIds = @($item.sourceStableIds)
    $targetIds = @($item.targetStableIds)
    $impact = $item.impactPreview
    $rollback = $item.rollbackPreview

    Assert-Condition (-not [string]::IsNullOrWhiteSpace($item.reviewItemId)) "reviewItemId is required"
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($item.mappingGroupId)) "mappingGroupId is required"
    Assert-Condition ($allowedCardinalities -contains $cardinality) "invalid cardinality: $cardinality"
    Assert-Condition (@('low','medium','high') -contains $riskLevel) "invalid riskLevel: $riskLevel"
    Assert-Condition ($confidence -ge 0 -and $confidence -le 1) "confidence must be between 0 and 1"
    Assert-Condition ($sourceIds.Count -gt 0) "sourceStableIds must not be empty"
    Assert-Condition ($targetIds.Count -gt 0) "targetStableIds must not be empty"
    Assert-Condition ($rollback.snapshotRequired -eq $true) "rollback snapshot is required for every review item"
    Assert-Condition ($null -ne $impact.questionBindings) "impactPreview.questionBindings is required"
    Assert-Condition ($null -ne $impact.analysisReports) "impactPreview.analysisReports is required"
    Assert-Condition ($null -ne $impact.requiresManualConfirmation) "impactPreview.requiresManualConfirmation is required"
    Assert-Condition (@($item.allowedActions) -contains 'undo') "undo must be available for review item: $($item.reviewItemId)"
    [void]$seenCardinalities.Add($cardinality)

    if ($manualCardinalities -contains $cardinality -or $riskLevel -eq 'high' -or $confidence -lt 0.85) {
        Assert-Condition ($item.requiresHumanDecision -eq $true) "complex/high-risk mapping must require human decision: $($item.reviewItemId)"
        Assert-Condition ($item.requiresReviewReason -eq $true) "complex/high-risk mapping must require review reason: $($item.reviewItemId)"
        Assert-Condition ([int]$impact.requiresManualConfirmation -gt 0) "complex mapping must expose manual confirmation count: $($item.reviewItemId)"
        $manualReviewCount++
    }
    else {
        Assert-Condition ($cardinality -eq 'one_to_one') "only one_to_one can be auto eligible: $($item.reviewItemId)"
        Assert-Condition ([int]$impact.requiresManualConfirmation -eq 0) "auto eligible item must not require manual confirmations: $($item.reviewItemId)"
        $autoEligibleCount++
    }
}

foreach ($requiredCardinality in @('one_to_one','one_to_many','many_to_many')) {
    Assert-Condition ($seenCardinalities.Contains($requiredCardinality)) "C002H sample must cover cardinality: $requiredCardinality"
}

$bulkApprove = @($plan.bulkActions | Where-Object action -eq 'batch_approve') | Select-Object -First 1
Assert-Condition ($null -ne $bulkApprove) "batch_approve bulk action is required"
Assert-Condition ([string]$bulkApprove.allowedWhen -match 'one_to_one') "batch_approve must be limited to one_to_one low-risk items"

foreach ($field in $requiredAuditFields) {
    Assert-Condition (@($plan.audit.requiredFields) -contains $field) "missing audit field: $field"
}
Assert-Condition ($plan.audit.undoRequiredBeforeApply -eq $true) "undoRequiredBeforeApply must be true"

[ordered]@{
    status = 'pass'
    planId = [string]$plan.planId
    mode = [string]$plan.mode
    reviewItems = $reviewItems.Count
    manualReview = $manualReviewCount
    autoEligible = $autoEligibleCount
    coveredCardinalities = @($seenCardinalities | Sort-Object)
    requiredFilters = @($workbench.requiredFilters).Count
    requiredViews = @($workbench.requiredViews).Count
    undoRequiredBeforeApply = [bool]$plan.audit.undoRequiredBeforeApply
} | ConvertTo-Json -Depth 8

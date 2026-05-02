param(
    [string] $PlanPath = 'configs\domain-assets\c002b-draft-formal-mapping.sample.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$resolvedPlanPath = (Resolve-Path -LiteralPath (Join-Path $repoRoot $PlanPath)).Path
$plan = Get-Content -LiteralPath $resolvedPlanPath -Raw | ConvertFrom-Json

$allowedMappingTypes = @('equivalent','split','merge','broader','narrower','renamed','deprecated')
$allowedImpactLevels = @('low','medium','high')
$autoEligibleTypes = @('equivalent','renamed')
$manualTypes = @('split','merge','broader','narrower','deprecated')

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

Assert-Condition ($plan.schemaVersion -eq 'domain-asset-replacement-plan.v0.1') "unexpected C002B schemaVersion"
Assert-Condition ($plan.mode -eq 'dry_run') "C002B replacement contract must stay dry_run"
Assert-Condition ($plan.assetType -eq 'knowledge_node') "C002B sample must validate knowledge_node assets first"
Assert-Condition ($plan.rollback.snapshotRequired -eq $true) "C002B migration must require rollback snapshot"

$assets = @($plan.assets)
$mappings = @($plan.mappings)
Assert-Condition ($assets.Count -gt 0) "C002B assets are empty"
Assert-Condition ($mappings.Count -gt 0) "C002B mappings are empty"

$assetByStableId = @{}
foreach ($asset in $assets) {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($asset.stableId)) "asset stableId is required"
    Assert-Condition (-not $assetByStableId.ContainsKey($asset.stableId)) "duplicate asset stableId: $($asset.stableId)"
    Assert-Condition (@('draft','candidate','reviewed','active','deprecated','merged','superseded') -contains [string]$asset.status) "invalid asset status: $($asset.status)"
    Assert-Condition (@('bootstrap','source_derived','school_approved','policy') -contains [string]$asset.authority) "invalid asset authority: $($asset.authority)"
    $assetByStableId[$asset.stableId] = $asset
}

$decisions = New-Object System.Collections.Generic.List[object]
$seenTypes = New-Object System.Collections.Generic.HashSet[string]
foreach ($mapping in $mappings) {
    $mappingType = [string]$mapping.mappingType
    $impactLevel = [string]$mapping.impactLevel
    $confidence = [decimal]$mapping.confidence

    Assert-Condition ($assetByStableId.ContainsKey($mapping.sourceStableId)) "mapping source asset missing: $($mapping.sourceStableId)"
    Assert-Condition ($assetByStableId.ContainsKey($mapping.targetStableId)) "mapping target asset missing: $($mapping.targetStableId)"
    Assert-Condition ($allowedMappingTypes -contains $mappingType) "invalid mappingType: $mappingType"
    Assert-Condition ($allowedImpactLevels -contains $impactLevel) "invalid impactLevel: $impactLevel"
    Assert-Condition ($confidence -ge 0 -and $confidence -le 1) "confidence must be between 0 and 1"
    Assert-Condition ($mapping.reversible -eq $true) "C002B dry-run mappings must be reversible"
    [void]$seenTypes.Add($mappingType)

    $decision = if (
        ($autoEligibleTypes -contains $mappingType) -and
        $confidence -ge 0.95 -and
        $impactLevel -eq 'low'
    ) {
        'auto_apply'
    }
    else {
        'pending_review'
    }

    Assert-Condition ($decision -eq [string]$mapping.expectedDecision) "unexpected decision for $($mapping.sourceStableId) -> $($mapping.targetStableId): expected $($mapping.expectedDecision), got $decision"

    if ($manualTypes -contains $mappingType) {
        Assert-Condition ($decision -eq 'pending_review') "manual mapping type must stay pending_review: $mappingType"
    }

    $decisions.Add([ordered]@{
        sourceStableId = [string]$mapping.sourceStableId
        targetStableId = [string]$mapping.targetStableId
        mappingType = $mappingType
        confidence = $confidence
        impactLevel = $impactLevel
        decision = $decision
        reviewStatus = if ($decision -eq 'auto_apply') { 'auto_applied' } else { 'pending_review' }
    })
}

foreach ($requiredType in @('equivalent','split','narrower','renamed','deprecated')) {
    Assert-Condition ($seenTypes.Contains($requiredType)) "C002B sample must cover mapping type: $requiredType"
}

$autoApply = @($decisions | Where-Object decision -eq 'auto_apply')
$pendingReview = @($decisions | Where-Object decision -eq 'pending_review')
Assert-Condition ($autoApply.Count -gt 0) "C002B sample must include auto_apply mappings"
Assert-Condition ($pendingReview.Count -gt 0) "C002B sample must include pending_review mappings"

$impact = $plan.impact
$impactKeys = @('questionBindings','tagBindings','assemblyConstraints','analysisReports','fixtures')
foreach ($key in $impactKeys) {
    Assert-Condition ($null -ne $impact.$key) "missing impact key: $key"
    Assert-Condition ([int]$impact.$key -ge 0) "impact key must be non-negative: $key"
}

[ordered]@{
    status = 'pass'
    planId = [string]$plan.planId
    mode = [string]$plan.mode
    assets = $assets.Count
    mappings = $mappings.Count
    autoApply = $autoApply.Count
    pendingReview = $pendingReview.Count
    coveredMappingTypes = @($seenTypes | Sort-Object)
    impact = [ordered]@{
        questionBindings = [int]$impact.questionBindings
        tagBindings = [int]$impact.tagBindings
        assemblyConstraints = [int]$impact.assemblyConstraints
        analysisReports = [int]$impact.analysisReports
        fixtures = [int]$impact.fixtures
    }
    rollbackSnapshotRequired = [bool]$plan.rollback.snapshotRequired
} | ConvertTo-Json -Depth 8

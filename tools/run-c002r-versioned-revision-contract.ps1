param(
    [string] $RevisionPlanPath = 'configs\domain-assets\c002r-versioned-revision.sample.json',
    [string] $ReportPath = 'docs\evidence\c002r-versioned-revision-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$resolvedPlanPath = (Resolve-Path -LiteralPath (Join-Path $repoRoot $RevisionPlanPath)).Path
$plan = Get-Content -LiteralPath $resolvedPlanPath -Raw | ConvertFrom-Json
$resolvedReportPath = Join-Path $repoRoot $ReportPath

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

$requiredChangeSources = @('new_textbook','new_curriculum_standard','exam_trend','teacher_correction')
$requiredTeacherFields = @('changeSummary','sourceEvidence','affectedScope','urgency')
$requiredMappingTypes = @('equivalent','split','merge','broader','narrower','renamed','deprecated')
$complexMappingTypes = @('split','merge','broader','narrower','deprecated')
$requiredImpactTypes = @('question_binding','paper_blueprint','search_index','analysis_metric','export_template','score_import_template')
$requiredRollbackSteps = @('restore_active_version','restore_mapping_edges','restore_impact_targets','verify_historical_analysis')

Assert-Condition ($plan.schemaVersion -eq 'domain-asset-versioned-revision.v0.1') "unexpected C002R schemaVersion"
Assert-Condition ($plan.mode -eq 'dry_run') "C002R revision contract must stay dry_run"
Assert-Condition ($plan.noActiveWrite -eq $true) "C002R must not write active assets directly"
Assert-Condition ($plan.activeBaseline.status -eq 'active') "C002R must start from an active baseline"
Assert-Condition (-not [string]::IsNullOrWhiteSpace($plan.activeBaseline.activeImportKey)) "activeImportKey is required"
Assert-Condition ($plan.activeBaseline.activeAssetCount -gt 0) "activeAssetCount must be positive"

foreach ($source in $requiredChangeSources) {
    Assert-Condition (@($plan.teacherRevisionIntake.allowedChangeSources) -contains $source) "missing allowed change source: $source"
}
foreach ($field in $requiredTeacherFields) {
    Assert-Condition (@($plan.teacherRevisionIntake.requiredFields) -contains $field) "missing teacher intake field: $field"
}
Assert-Condition ($plan.teacherRevisionIntake.hideTechnicalFieldsFromTeacher -eq $true) "teacher intake must hide technical fields"

$candidate = $plan.candidateVersion
Assert-Condition ($candidate.status -eq 'candidate') "revision must create candidate version"
Assert-Condition ($candidate.productionEligible -eq $false) "candidate revision must not be production eligible"
Assert-Condition ($candidate.noInPlaceActiveEdit -eq $true) "active version must not be edited in place"
Assert-Condition (-not [string]::IsNullOrWhiteSpace($candidate.basedOnActiveVersion)) "basedOnActiveVersion is required"
Assert-Condition (@($candidate.requiredEvidenceFields).Count -ge 3) "candidate evidence fields are insufficient"

$seenMappingTypes = New-Object System.Collections.Generic.HashSet[string]
$manualReviewMappings = 0
$autoSuggestMappings = 0
foreach ($mapping in @($plan.mappingPlan.mappings)) {
    $mappingType = [string]$mapping.mappingType
    $confidence = [decimal]$mapping.confidence
    Assert-Condition ($requiredMappingTypes -contains $mappingType) "invalid mappingType: $mappingType"
    Assert-Condition ($confidence -ge 0 -and $confidence -le 1) "mapping confidence must be between 0 and 1"
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($mapping.fromStableId)) "mapping fromStableId is required"
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($mapping.toStableId)) "mapping toStableId is required"
    Assert-Condition ($mapping.noDirectActiveApply -eq $true) "mapping must not directly apply to active: $($mapping.mappingId)"
    [void]$seenMappingTypes.Add($mappingType)

    if ($complexMappingTypes -contains $mappingType -or $confidence -lt 0.85 -or [string]$mapping.impactLevel -eq 'high') {
        Assert-Condition ($mapping.requiresHumanReview -eq $true) "complex or high-risk mapping must require human review: $($mapping.mappingId)"
        Assert-Condition ($mapping.requiresReviewReason -eq $true) "complex or high-risk mapping must require review reason: $($mapping.mappingId)"
        $manualReviewMappings++
    }
    else {
        Assert-Condition ($mappingType -in @('equivalent','renamed')) "only equivalent/renamed mappings can be auto-suggested: $($mapping.mappingId)"
        Assert-Condition ($mapping.requiresHumanReview -eq $false) "low-risk mapping should stay auto-suggest only: $($mapping.mappingId)"
        $autoSuggestMappings++
    }
}
foreach ($mappingType in $requiredMappingTypes) {
    Assert-Condition ($seenMappingTypes.Contains($mappingType)) "C002R sample must cover mapping type: $mappingType"
}

$seenImpactTypes = New-Object System.Collections.Generic.HashSet[string]
$frozenHistoricalAnalysis = 0
foreach ($impact in @($plan.impactReport.impacts)) {
    $impactType = [string]$impact.impactType
    Assert-Condition ($requiredImpactTypes -contains $impactType) "invalid impactType: $impactType"
    Assert-Condition ($impact.affectedCount -ge 0) "affectedCount must be non-negative"
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($impact.rollbackKey)) "rollbackKey is required"
    Assert-Condition ($impact.requiresRollbackSnapshot -eq $true) "every impact must require rollback snapshot"
    [void]$seenImpactTypes.Add($impactType)
    if ($impactType -eq 'analysis_metric') {
        Assert-Condition ($impact.action -eq 'freeze_historical_snapshot') "analysis_metric must freeze historical snapshots"
        Assert-Condition ($impact.requiresHumanReview -eq $true) "analysis_metric must require human review"
        $frozenHistoricalAnalysis += [int]$impact.affectedCount
    }
}
foreach ($impactType in $requiredImpactTypes) {
    Assert-Condition ($seenImpactTypes.Contains($impactType)) "C002R sample must cover impact type: $impactType"
}

Assert-Condition ($plan.reviewWorkflow.initialStatus -eq 'pending_review') "revision review must start pending_review"
Assert-Condition ($plan.reviewWorkflow.requiresReviewReason -eq $true) "review reason is required"
Assert-Condition ($plan.reviewWorkflow.requiresRollbackSnapshotBeforeApproval -eq $true) "rollback snapshot is required before approval"
Assert-Condition ($plan.reviewWorkflow.activeSwitchRole -eq 'administrator') "active switch must stay administrator-only"
Assert-Condition ($plan.reviewWorkflow.teacherCanApplyActive -eq $false) "teacher must not apply active switch"

foreach ($step in $requiredRollbackSteps) {
    Assert-Condition (@($plan.rollbackDrill.requiredSteps) -contains $step) "missing rollback step: $step"
}
Assert-Condition ($plan.rollbackDrill.verifyAfterRollback -eq $true) "rollback drill must verify after rollback"

$report = [ordered]@{
    status = 'pass'
    planId = [string]$plan.planId
    mode = [string]$plan.mode
    checkedAt = (Get-Date).ToUniversalTime().ToString('o')
    task = 'C002R'
    activeImportKey = [string]$plan.activeBaseline.activeImportKey
    activeAssetCount = [int]$plan.activeBaseline.activeAssetCount
    mappingTypes = @($seenMappingTypes | Sort-Object)
    mappings = @($plan.mappingPlan.mappings).Count
    manualReviewMappings = $manualReviewMappings
    autoSuggestMappings = $autoSuggestMappings
    impactTypes = @($seenImpactTypes | Sort-Object)
    impacts = @($plan.impactReport.impacts).Count
    frozenHistoricalAnalysis = $frozenHistoricalAnalysis
    teacherCanApplyActive = [bool]$plan.reviewWorkflow.teacherCanApplyActive
    rollbackSteps = @($plan.rollbackDrill.requiredSteps).Count
    evidence = [ordered]@{
        revisionPlan = [System.IO.Path]::GetRelativePath($repoRoot, $resolvedPlanPath).Replace('\', '/')
        report = [System.IO.Path]::GetRelativePath($repoRoot, $resolvedReportPath).Replace('\', '/')
    }
}

New-Item -ItemType Directory -Path (Split-Path -Parent $resolvedReportPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedReportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8

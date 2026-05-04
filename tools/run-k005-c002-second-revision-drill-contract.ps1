param(
    [string] $DrillPath = 'configs\domain-assets\k005-c002-second-revision-drill.sample.json',
    [string] $ReportPath = 'docs\evidence\k005-c002-second-revision-drill-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$resolvedDrillPath = (Resolve-Path -LiteralPath (Join-Path $repoRoot $DrillPath)).Path
$resolvedReportPath = Join-Path $repoRoot $ReportPath
$dependencyReportRelativePath = 'tmp\k005-c002r-versioned-revision-dependency-report.json'
$dependencyReportPath = Join-Path $repoRoot $dependencyReportRelativePath

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

$c002rReportRaw = & (Join-Path $PSScriptRoot 'run-c002r-versioned-revision-contract.ps1') -ReportPath $dependencyReportRelativePath
$c002rReport = $c002rReportRaw | ConvertFrom-Json
Assert-Condition ($c002rReport.status -eq 'pass') 'C002R dependency report must pass before K005'
Assert-Condition ($c002rReport.teacherCanApplyActive -eq $false) 'C002R dependency must keep teacher active switch blocked'

$drill = Get-Content -LiteralPath $resolvedDrillPath -Raw | ConvertFrom-Json

Assert-Condition ($drill.schemaVersion -eq 'c002-second-revision-drill.v0.1') 'unexpected K005 schemaVersion'
Assert-Condition ($drill.taskId -eq 'K005') 'unexpected taskId'
Assert-Condition ($drill.mode -eq 'dry_run') 'K005 must stay dry_run'
Assert-Condition ($drill.noActiveWrite -eq $true) 'K005 must not write active assets'
Assert-Condition ($drill.realTeacherDataUsed -eq $false) 'K005 must not use real teacher data'
Assert-Condition ($drill.activeBaseline.status -eq 'active') 'K005 must start from active baseline'
Assert-Condition ($drill.activeBaseline.preserveOldActive -eq $true) 'old active must be preserved'
Assert-Condition ($drill.teacherReviewSample.hideTechnicalFieldsFromTeacher -eq $true) 'teacher-facing sample must hide technical fields'

$candidate = $drill.lifecycle.candidate
Assert-Condition ($candidate.status -eq 'candidate') 'K005 candidate phase is required'
Assert-Condition ($candidate.productionEligible -eq $false) 'K005 candidate must not be production eligible'
Assert-Condition ($candidate.noInPlaceActiveEdit -eq $true) 'K005 must not edit active in place'
Assert-Condition ($candidate.assetDelta.added -ge 0 -and $candidate.assetDelta.updated -ge 0 -and $candidate.assetDelta.deprecated -ge 0) 'asset delta must be non-negative'
foreach ($field in @('sourceEvidence','teacherChangeReason','mappingReviewDecision','rollbackSnapshotKey')) {
    Assert-Condition (@($candidate.requiredEvidenceFields) -contains $field) "candidate missing evidence field: $field"
}

$reviewed = $drill.lifecycle.reviewed
Assert-Condition ($reviewed.status -eq 'reviewed') 'K005 reviewed phase is required'
Assert-Condition ($reviewed.reviewDecision -eq 'approved_for_active_dry_run') 'K005 review must approve only active dry-run'
Assert-Condition ($reviewed.reviewReasonRequired -eq $true) 'K005 review reason is required'
Assert-Condition (-not [string]::IsNullOrWhiteSpace($reviewed.reviewReason)) 'K005 review reason text is required'
Assert-Condition ($reviewed.manualReviewItemCount -gt 0) 'K005 must contain manual review items'
Assert-Condition ($reviewed.unresolvedBlockerCount -eq 0) 'K005 active dry-run must have no unresolved blockers'

$activeDryRun = $drill.lifecycle.activeDryRun
Assert-Condition ($activeDryRun.status -eq 'active_dry_run_pass') 'K005 active dry-run must pass'
Assert-Condition ($activeDryRun.apply -eq $false) 'K005 active dry-run must not apply'
Assert-Condition ($activeDryRun.adminOnly -eq $true) 'K005 active dry-run must stay administrator-only'
Assert-Condition ($activeDryRun.teacherCanApplyActive -eq $false) 'teacher must not apply K005 active switch'
Assert-Condition ($activeDryRun.oldActivePreserved -eq $true) 'K005 must preserve old active'
Assert-Condition ($activeDryRun.noProductionHistoryRewrite -eq $true) 'K005 must not rewrite production history'
Assert-Condition (@($activeDryRun.blockers).Count -eq 0) 'K005 active dry-run blockers must be empty'

$requiredMappingTypes = @('broader','split','deprecated')
$seenMappingTypes = New-Object System.Collections.Generic.HashSet[string]
$manualReviewMappings = 0
foreach ($mapping in @($drill.mappingPlan.mappings)) {
    $mappingType = [string]$mapping.mappingType
    Assert-Condition ($requiredMappingTypes -contains $mappingType) "unexpected K005 mapping type: $mappingType"
    Assert-Condition ($mapping.noDirectActiveApply -eq $true) "mapping must not directly apply active: $($mapping.mappingId)"
    Assert-Condition ($mapping.requiresHumanReview -eq $true) "K005 mapping must require human review: $($mapping.mappingId)"
    Assert-Condition ($mapping.requiresReviewReason -eq $true) "K005 mapping must require review reason: $($mapping.mappingId)"
    Assert-Condition ([decimal]$mapping.confidence -ge 0 -and [decimal]$mapping.confidence -le 1) "mapping confidence out of range: $($mapping.mappingId)"
    [void]$seenMappingTypes.Add($mappingType)
    $manualReviewMappings++
}
foreach ($mappingType in $requiredMappingTypes) {
    Assert-Condition ($seenMappingTypes.Contains($mappingType)) "K005 missing mapping type: $mappingType"
}

$requiredImpactTypes = @('question_binding','paper_blueprint','analysis_metric')
$seenImpactTypes = New-Object System.Collections.Generic.HashSet[string]
foreach ($impact in @($drill.impactReport.impacts)) {
    $impactType = [string]$impact.impactType
    Assert-Condition ($requiredImpactTypes -contains $impactType) "unexpected K005 impact type: $impactType"
    Assert-Condition ($impact.requiresRollbackSnapshot -eq $true) "impact requires rollback snapshot: $impactType"
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($impact.rollbackKey)) "impact rollbackKey required: $impactType"
    if ($impactType -eq 'analysis_metric') {
        Assert-Condition ($impact.action -eq 'freeze_historical_snapshot') 'K005 analysis metric must freeze historical snapshot'
    }
    [void]$seenImpactTypes.Add($impactType)
}
foreach ($impactType in $requiredImpactTypes) {
    Assert-Condition ($seenImpactTypes.Contains($impactType)) "K005 missing impact type: $impactType"
}

$rollback = $drill.rollbackSnapshot
Assert-Condition (-not [string]::IsNullOrWhiteSpace($rollback.snapshotKey)) 'rollback snapshot key required'
Assert-Condition ($rollback.requiredBeforeReviewed -eq $true) 'rollback snapshot must be required before reviewed'
Assert-Condition ($rollback.requiredBeforeActiveDryRun -eq $true) 'rollback snapshot must be required before active dry-run'
Assert-Condition ($rollback.verifyAfterRollback -eq $true) 'rollback snapshot verification required'
foreach ($item in @('active_version_pointer','mapping_edges','impact_targets','historical_analysis_snapshots')) {
    Assert-Condition (@($rollback.includes) -contains $item) "rollback snapshot missing: $item"
}

$report = [ordered]@{
    status = 'pass'
    task = 'K005'
    batchId = [string]$drill.batchId
    mode = [string]$drill.mode
    checkedAt = (Get-Date).ToUniversalTime().ToString('o')
    lifecycle = @('candidate','reviewed','active_dry_run')
    activeDryRunStatus = [string]$activeDryRun.status
    noActiveWrite = [bool]$drill.noActiveWrite
    realTeacherDataUsed = [bool]$drill.realTeacherDataUsed
    realStudentDataUsed = $false
    oldActivePreserved = [bool]$activeDryRun.oldActivePreserved
    noProductionHistoryRewrite = [bool]$activeDryRun.noProductionHistoryRewrite
    teacherCanApplyActive = [bool]$activeDryRun.teacherCanApplyActive
    manualReviewMappings = $manualReviewMappings
    mappingTypes = @($seenMappingTypes | Sort-Object)
    impactTypes = @($seenImpactTypes | Sort-Object)
    rollbackSnapshotKey = [string]$rollback.snapshotKey
    dependency = [ordered]@{
        c002rStatus = [string]$c002rReport.status
        c002rPlanId = [string]$c002rReport.planId
        c002rReport = [System.IO.Path]::GetRelativePath($repoRoot, $dependencyReportPath).Replace('\', '/')
    }
    evidence = [ordered]@{
        drill = [System.IO.Path]::GetRelativePath($repoRoot, $resolvedDrillPath).Replace('\', '/')
        report = [System.IO.Path]::GetRelativePath($repoRoot, $resolvedReportPath).Replace('\', '/')
    }
    rollback = [ordered]@{
        code = 'git revert this K005 commit'
        data = 'no database, active asset, or production history write is performed by this dry-run contract'
    }
}

New-Item -ItemType Directory -Path (Split-Path -Parent $resolvedReportPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedReportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8

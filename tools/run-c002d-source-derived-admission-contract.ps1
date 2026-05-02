param(
    [string] $AdmissionPlanPath = 'configs\domain-assets\c002d-source-derived-admission.sample.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$admissionPlan = Get-Content -LiteralPath (Resolve-Path -LiteralPath (Join-Path $repoRoot $AdmissionPlanPath)) -Raw | ConvertFrom-Json

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

Assert-Condition ($admissionPlan.schemaVersion -eq 'source-derived-ontology-admission.v0.1') "unexpected C002D schemaVersion"
Assert-Condition ($admissionPlan.mode -eq 'dry_run') "C002D admission contract must stay dry_run"
Assert-Condition ($admissionPlan.subject -eq 'physics') "C002D subject must be physics"
Assert-Condition ($admissionPlan.stage -eq 'junior_middle_school') "C002D stage must be junior_middle_school"
Assert-Condition ($admissionPlan.activationStatus -eq 'candidate') "C002D must create candidate assets only"
Assert-Condition ($admissionPlan.guards.forbidActiveStatus -eq $true) "C002D must forbid active status"
Assert-Condition ($admissionPlan.guards.requireTeacherReviewBeforeActivation -eq $true) "C002D must require teacher review before activation"

$manifestPath = Resolve-Path -LiteralPath (Join-Path $repoRoot ([string]$admissionPlan.sourceManifest))
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

& (Join-Path $repoRoot 'tools\run-c002-source-material-guard.ps1') -ManifestPath ([string]$admissionPlan.sourceManifest) | Write-Host

$materials = @($manifest.materials)
$materialById = @{}
foreach ($material in $materials) {
    Assert-Condition (-not $materialById.ContainsKey($material.materialId)) "duplicate materialId: $($material.materialId)"
    Assert-Condition ($material.localPath -notmatch '(?i)D:/CODE|D:\\CODE|configs/|docs/|sources/') "material localPath must stay outside repo: $($material.materialId)"
    Assert-Condition (-not ($material.containsStudentPii -and $material.anonymizationStatus -notin @('anonymized','synthetic'))) "material contains unhandled PII: $($material.materialId)"
    Assert-Condition ($material.mayUseForKnowledgeExtraction -eq $true) "material not approved for extraction: $($material.materialId)"
    $materialById[$material.materialId] = $material
}

foreach ($requiredType in @($admissionPlan.minimumSourceTypes)) {
    Assert-Condition (@($materials | Where-Object sourceType -eq $requiredType).Count -gt 0) "missing required source type: $requiredType"
}

$candidateAssets = @($admissionPlan.candidateAssets)
Assert-Condition ($candidateAssets.Count -gt 0) "C002D candidateAssets are empty"
$candidateIds = New-Object System.Collections.Generic.HashSet[string]
$evidenceMaterialTypes = New-Object System.Collections.Generic.HashSet[string]
foreach ($candidate in $candidateAssets) {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($candidate.stableId)) "candidate stableId is required"
    Assert-Condition ($candidateIds.Add([string]$candidate.stableId)) "duplicate candidate stableId: $($candidate.stableId)"
    Assert-Condition ($candidate.assetType -eq 'knowledge_node') "C002D candidate assetType must be knowledge_node"
    Assert-Condition ($candidate.status -eq 'candidate') "C002D candidate cannot be active: $($candidate.stableId)"
    Assert-Condition ($candidate.authority -eq 'source_derived') "C002D candidate must be source_derived: $($candidate.stableId)"
    Assert-Condition ($candidate.reviewStatus -eq 'pending_review') "C002D candidate must remain pending_review: $($candidate.stableId)"
    Assert-Condition ([int]$candidate.level -ge 1 -and [int]$candidate.level -le 5) "candidate level must be L1-L5: $($candidate.stableId)"

    $evidence = @($candidate.sourceEvidence)
    Assert-Condition ($evidence.Count -gt 0) "candidate sourceEvidence is required: $($candidate.stableId)"
    foreach ($item in $evidence) {
        Assert-Condition ($materialById.ContainsKey($item.materialId)) "candidate references unknown materialId: $($item.materialId)"
        Assert-Condition (-not [string]::IsNullOrWhiteSpace($item.evidenceType)) "candidate evidenceType is required: $($candidate.stableId)"
        $sourceType = [string]$materialById[$item.materialId].sourceType
        [void]$evidenceMaterialTypes.Add($sourceType)
    }
}

foreach ($requiredType in @($admissionPlan.minimumSourceTypes)) {
    Assert-Condition ($evidenceMaterialTypes.Contains($requiredType)) "candidate evidence does not cover required source type: $requiredType"
}

foreach ($outputPath in @($admissionPlan.outputs.replacementPlan, $admissionPlan.outputs.impactPlan)) {
    Assert-Condition (Test-Path -LiteralPath (Join-Path $repoRoot ([string]$outputPath))) "C002D output plan missing: $outputPath"
}

[ordered]@{
    status = 'pass'
    planId = [string]$admissionPlan.planId
    mode = [string]$admissionPlan.mode
    sourceManifest = [string]$admissionPlan.sourceManifest
    materials = $materials.Count
    candidateAssets = $candidateAssets.Count
    evidenceSourceTypes = @($evidenceMaterialTypes | Sort-Object)
    activationStatus = [string]$admissionPlan.activationStatus
    activeForbidden = [bool]$admissionPlan.guards.forbidActiveStatus
    teacherReviewRequired = [bool]$admissionPlan.guards.requireTeacherReviewBeforeActivation
} | ConvertTo-Json -Depth 8

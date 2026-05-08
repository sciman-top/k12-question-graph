param(
    [string] $ManifestPath = 'tests/e2e/s012a-proxy-fixture-pack.json',
    [string] $ReportPath = 'docs/evidence/20260508-s012a-e2e-proxy-fixture-pack-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$manifestFullPath = Join-Path $repoRoot $ManifestPath
$reportFullPath = Join-Path $repoRoot $ReportPath

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Resolve-RepoPath([string] $Path) {
    return Join-Path $repoRoot $Path
}

Assert-True (Test-Path -LiteralPath $manifestFullPath) "S012A fixture manifest missing: $ManifestPath"
$manifest = Get-Content -Raw -LiteralPath $manifestFullPath | ConvertFrom-Json -Depth 20

Assert-True ([string]$manifest.schemaVersion -eq 's012a-e2e-proxy-fixture-pack.v1') "unexpected S012A schemaVersion: $($manifest.schemaVersion)"
Assert-True ([string]$manifest.taskId -eq 'S012A') 'S012A manifest taskId mismatch'
Assert-True (-not [bool]$manifest.productionEligible) 'S012A proxy pack must not be production eligible'
Assert-True (-not [bool]$manifest.realStudentDataUsed) 'S012A proxy pack must not use real student data'
Assert-True (-not [bool]$manifest.containsStudentPii) 'S012A proxy pack must not contain student PII'
Assert-True ([string]$manifest.authorization.status -eq 'synthetic_or_anonymized_only') 'S012A authorization must be synthetic_or_anonymized_only'

$requiredSteps = @('import','cut','review','tagging','save','paper','export','score','analysis')
$materials = @($manifest.materials)
Assert-True ($materials.Count -ge $requiredSteps.Count) 'S012A must include at least one material per expected workflow step'

$coveredSteps = @{}
$materialSummaries = New-Object System.Collections.Generic.List[object]
foreach ($row in $materials) {
    $step = [string]$row.workflowStep
    Assert-True ($requiredSteps -contains $step) "S012A material has unexpected workflowStep: $step"
    $coveredSteps[$step] = $true

    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$row.materialId)) "S012A material missing materialId for $step"
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$row.localPath)) "S012A material missing localPath for $step"
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$row.expectedPath)) "S012A material missing expectedPath for $step"
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$row.evidenceCommand)) "S012A material missing evidenceCommand for $step"
    Assert-True (-not [bool]$row.containsStudentPii) "S012A material contains PII: $($row.materialId)"
    Assert-True ([string]$row.anonymizationStatus -in @('synthetic','anonymized')) "S012A material must be synthetic or anonymized: $($row.materialId)"
    Assert-True ([string]$row.licenseOrPermission -in @('synthetic_local_regression','internal_authorized')) "S012A material lacks allowed permission: $($row.materialId)"

    $localPath = Resolve-RepoPath ([string]$row.localPath)
    Assert-True (Test-Path -LiteralPath $localPath) "S012A localPath missing for $($row.materialId): $($row.localPath)"

    $evidenceCommand = [string]$row.evidenceCommand
    if ($evidenceCommand -match '^tools/') {
        $commandPath = Resolve-RepoPath $evidenceCommand
        Assert-True (Test-Path -LiteralPath $commandPath) "S012A evidence command missing for $($row.materialId): $evidenceCommand"
    }

    $materialSummaries.Add([ordered]@{
        materialId = $row.materialId
        workflowStep = $step
        sourceType = $row.sourceType
        localPath = $row.localPath
        expectedPath = $row.expectedPath
        evidenceCommand = $row.evidenceCommand
    })
}

foreach ($step in $requiredSteps) {
    Assert-True ($coveredSteps.ContainsKey($step)) "S012A missing workflow step: $step"
}

Assert-True ([bool]$manifest.s012bAdmission.requiresAuthorizedOrAnonymizedReplacement) 'S012B admission must require authorized/anonymized replacement'
Assert-True ([bool]$manifest.s012bAdmission.requiresElapsedTimeCapture) 'S012B admission must require elapsed time capture'
Assert-True ([bool]$manifest.s012bAdmission.requiresRollbackEvidence) 'S012B admission must require rollback evidence'
Assert-True ([bool]$manifest.s012bAdmission.requiresBackupRestoreEvidence) 'S012B admission must require backup restore evidence'
Assert-True ([bool]$manifest.s012bAdmission.blocksLivePilot) 'S012A must keep live pilot blocked'

$report = [ordered]@{
    status = 'pass'
    taskId = 'S012A'
    checkedAt = (Get-Date).ToString('s')
    manifestPath = $ManifestPath
    mode = $manifest.mode
    productionEligible = [bool]$manifest.productionEligible
    realStudentDataUsed = [bool]$manifest.realStudentDataUsed
    containsStudentPii = [bool]$manifest.containsStudentPii
    materialCount = $materials.Count
    coveredWorkflowSteps = $requiredSteps
    materials = $materialSummaries
    s012bAdmission = $manifest.s012bAdmission
    conclusion = 'S012A fixture pack covers import cut review tagging save paper export score and analysis with synthetic/anonymized-only inputs and deterministic evidence commands; it does not execute the non-site E2E rehearsal.'
    rollback = 'remove tests/e2e/s012a-proxy-fixture-pack.json, tools/run-s012a-e2e-proxy-fixture-pack.ps1, this evidence report, and revert the S012A task status change'
}

New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
$report | ConvertTo-Json -Depth 12

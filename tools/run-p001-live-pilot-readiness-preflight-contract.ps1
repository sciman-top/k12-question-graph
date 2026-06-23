param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $LiveCloseoutPlanPath = 'tasks/live-pilot-closeout-plan.csv',
    [string] $ChecklistPath = 'docs/templates/p001-live-pilot-release-checklist.md',
    [string] $IsolatedMachineEvidenceTemplatePath = 'docs/templates/p001-isolated-machine-evidence-template.json',
    [string] $EvidencePath = 'docs/evidence/20260518-p001-live-pilot-readiness-preflight.md',
    [string] $ReportPath = '',
    [string] $HostCapabilityReportPath = 'docs/evidence/host-capability-diagnostic-report.json',
    [string] $WorkerProfileReportPath = 'docs/evidence/worker-profile-diagnostic-report.json',
    [string] $TechnologyRefreshReportPath = 'docs/evidence/technology-refresh-report.json',
    [string] $REAL005ReportPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Resolve-InRepoPath([string]$RelativePath) {
    return Join-Path $repoRoot $RelativePath
}

function Read-JsonFile([string]$RelativePath) {
    $fullPath = Resolve-InRepoPath $RelativePath
    Assert-True (Test-Path -LiteralPath $fullPath) "JSON evidence missing: $RelativePath"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Resolve-LatestReal005ReportPath([string]$PreferredPath) {
    if (-not [string]::IsNullOrWhiteSpace($PreferredPath)) {
        return $PreferredPath
    }

    $evidenceRoot = Resolve-InRepoPath 'docs/evidence'
    Assert-True (Test-Path -LiteralPath $evidenceRoot) 'missing docs/evidence directory'
    $latest = @(
        Get-ChildItem -LiteralPath $evidenceRoot -Filter '*-real005-guangzhou-2015-2025-closure-standard-report.json' -File |
            Sort-Object Name -Descending |
            Select-Object -First 1
    )
    Assert-True ($latest.Count -eq 1) 'missing REAL005 closure standard report under docs/evidence'
    return [System.IO.Path]::GetRelativePath($repoRoot, $latest[0].FullName).Replace('\', '/')
}

function Resolve-LatestEvidencePath([string]$Filter, [string]$Label) {
    $evidenceRoot = Resolve-InRepoPath 'docs/evidence'
    Assert-True (Test-Path -LiteralPath $evidenceRoot) 'missing docs/evidence directory'
    $latest = @(
        Get-ChildItem -LiteralPath $evidenceRoot -Filter $Filter -File |
            Sort-Object Name -Descending |
            Select-Object -First 1
    )
    Assert-True ($latest.Count -eq 1) "missing $Label under docs/evidence"
    return [System.IO.Path]::GetRelativePath($repoRoot, $latest[0].FullName).Replace('\', '/')
}

function Write-ContentIfChanged([string]$Path, [string]$Content) {
    if (Test-Path -LiteralPath $Path) {
        $existing = Get-Content -LiteralPath $Path -Raw
        if ($existing -eq $Content) { return }
    }
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = ('docs/evidence/{0}-p001-live-pilot-readiness-preflight-report.json' -f (Get-Date -Format 'yyyyMMdd'))
}

$backlogFullPath = Resolve-InRepoPath $BacklogPath
$liveCloseoutPlanFullPath = Resolve-InRepoPath $LiveCloseoutPlanPath
$checklistFullPath = Resolve-InRepoPath $ChecklistPath
$isolatedMachineEvidenceTemplateFullPath = Resolve-InRepoPath $IsolatedMachineEvidenceTemplatePath
$evidenceFullPath = Resolve-InRepoPath $EvidencePath
$reportFullPath = Resolve-InRepoPath $ReportPath

Assert-True (Test-Path -LiteralPath $backlogFullPath) "P001 backlog file missing: $BacklogPath"
Assert-True (Test-Path -LiteralPath $liveCloseoutPlanFullPath) "live closeout plan missing: $LiveCloseoutPlanPath"
Assert-True (Test-Path -LiteralPath $checklistFullPath) "P001 checklist missing: $ChecklistPath"
Assert-True (Test-Path -LiteralPath $isolatedMachineEvidenceTemplateFullPath) "P001 isolated-machine evidence template missing: $IsolatedMachineEvidenceTemplatePath"
Assert-True (Test-Path -LiteralPath $evidenceFullPath) "P001 evidence markdown missing: $EvidencePath"

$rows = Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8
$closeoutRows = @(Import-Csv -LiteralPath $liveCloseoutPlanFullPath -Encoding UTF8)
$REAL005ReportPath = Resolve-LatestReal005ReportPath $REAL005ReportPath
$byId = @{}
foreach ($row in $rows) {
    $byId[$row.id] = $row
}

Assert-True ($closeoutRows.Count -eq 26) "live closeout plan row count drift: expected 26 actual $($closeoutRows.Count)"

$p001NextCloseout = @($closeoutRows | Where-Object { [string] $_.parent_id -eq 'P001' -and [string] $_.status -ne '已完成' } | Select-Object -First 1)
$real005NextCloseout = @($closeoutRows | Where-Object { [string] $_.parent_id -eq 'REAL005' -and [string] $_.status -ne '已完成' } | Select-Object -First 1)
Assert-True ($p001NextCloseout.Count -eq 1) 'live closeout plan must expose next P001 slice'
Assert-True ([string] $p001NextCloseout[0].id -eq 'P001A') 'next P001 closeout slice must remain P001A before isolated-machine run'
Assert-True ($real005NextCloseout.Count -le 1) 'live closeout plan can expose at most one next REAL005 slice'

foreach ($requiredTaskId in @('S012', 'O004B', 'O006', 'O007', 'O008', 'REAL001', 'REAL002', 'REAL003', 'REAL004', 'REAL005', 'REAL006', 'REAL007', 'REAL008', 'REAL009', 'REAL010', 'REAL011', 'REAL012', 'P001')) {
    Assert-True ($byId.ContainsKey($requiredTaskId)) "P001 prerequisite task missing: $requiredTaskId"
}

$p001 = $byId['P001']

$dependencies = @($p001.depends_on -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($required in @('S012', 'O004B', 'O006', 'O007', 'O008', 'REAL012')) {
    Assert-True ($dependencies -contains $required) "P001 depends_on must include $required"
}

Assert-True ($p001.status -eq '待办') 'P001 must remain todo until isolated-machine rehearsal is executed with live evidence'

$requiredCompleted = @('S012', 'O004B', 'O006', 'O007', 'O008', 'REAL001', 'REAL002', 'REAL003', 'REAL004', 'REAL005', 'REAL006', 'REAL007', 'REAL008', 'REAL009', 'REAL010', 'REAL011', 'REAL012')
foreach ($required in $requiredCompleted) {
    Assert-True ($byId[$required].status -eq '已完成') "$required must be completed before P001 preflight can pass"
}

$realEvidencePaths = [ordered]@{
    REAL001 = Resolve-LatestEvidencePath '*-guangzhou-2015-real-ingest-slice-report.json' 'REAL001 report'
    REAL002 = 'docs/evidence/20260512-guangzhou-2015-visual-region-slice-report.json'
    REAL003 = 'docs/evidence/20260514-real003-guangzhou-physics-year-batch-ingest-report.json'
    REAL004 = 'docs/evidence/20260512-real004-guangzhou-2015-review-smoke-report.json'
    REAL005 = $REAL005ReportPath
    REAL006 = 'docs/evidence/20260512-real004-guangzhou-2015-review-smoke-report.json'
    REAL007 = 'docs/evidence/20260516-real007-guangzhou-2015-layout-quality-report.json'
    REAL008 = 'docs/evidence/20260518-real008-question-asset-smoke-report.json'
    REAL009 = 'docs/evidence/20260518-real009-table-structure-smoke-report.json'
    REAL010 = 'docs/evidence/20260518-real010-formula-fidelity-smoke-report.json'
    REAL011 = 'docs/evidence/20260518-real011-question-edit-smoke-report.json'
    REAL012 = 'docs/evidence/20260518-real012-production-flow-quality-report.json'
}

$realEvidenceStatus = [ordered]@{}
foreach ($entry in $realEvidencePaths.GetEnumerator()) {
    $json = Read-JsonFile $entry.Value
    $realEvidenceStatus[$entry.Key] = [ordered]@{
        path = $entry.Value
        status = [string]$json.status
    }
}

$real005Report = Read-JsonFile $realEvidencePaths['REAL005']
$real012Report = Read-JsonFile $realEvidencePaths['REAL012']
Assert-True ($real005Report.status -eq 'pass') 'REAL005 report must pass before P001 preflight'
Assert-True ($real005Report.closureStatus -eq 'not_closed') 'REAL005 full closure must remain not_closed before live pilot'
Assert-True (-not [bool]$real005Report.fullClosureAllowed) 'REAL005 full closure must not be allowed before live pilot'
Assert-True ($null -ne $real005Report.sliceCoverage) 'P001 preflight requires REAL005 sliceCoverage'
Assert-True ($null -ne $real005Report.sliceCoverage.REAL005A) 'P001 preflight requires REAL005A slice coverage'
Assert-True ($null -ne $real005Report.sliceCoverage.REAL005B) 'P001 preflight requires REAL005B slice coverage'
Assert-True ($null -ne $real005Report.sliceCoverage.REAL005C) 'P001 preflight requires REAL005C slice coverage'
Assert-True ($null -ne $real005Report.sliceCoverage.REAL005D) 'P001 preflight requires REAL005D slice coverage'
$real005AStatus = [string]$real005Report.sliceCoverage.REAL005A.status
$real005BStatus = [string]$real005Report.sliceCoverage.REAL005B.status
$real005CStatus = [string]$real005Report.sliceCoverage.REAL005C.status
$real005DStatus = [string]$real005Report.sliceCoverage.REAL005D.status
if ($real005AStatus -ne 'pass') {
    Assert-True ($real005AStatus -in @('blocked', 'partial')) 'P001 preflight requires REAL005A to be pass, blocked, or partial while full closure is open'
}
$expectedReal005NextOpen = if ($real005AStatus -ne 'pass') {
    'REAL005A'
}
elseif ($real005BStatus -ne 'pass') {
    'REAL005B'
}
elseif ($real005CStatus -ne 'pass') {
    'REAL005C'
}
elseif ($real005DStatus -ne 'pass') {
    'REAL005D'
}
else {
    'none'
}
$real005NextOpenId = if ($real005NextCloseout.Count -eq 1) { [string] $real005NextCloseout[0].id } else { 'none' }
Assert-True ($real005NextOpenId -eq $expectedReal005NextOpen) "P001 preflight requires REAL005 next open slice to match current closure evidence: expected $expectedReal005NextOpen actual $real005NextOpenId"
$real005NextSliceCoverage = $null
if ($expectedReal005NextOpen -eq 'none') {
    Assert-True ($real005DStatus -eq 'pass') 'P001 preflight requires REAL005D to pass once repo-side truthful wording is refreshed'
    Assert-True (@($real005Report.sliceCoverage.REAL005D.blockers).Count -eq 0) 'P001 preflight requires REAL005D blockers to be empty once repo-side closeout is complete'
}
else {
    if ($real005AStatus -ne 'pass') {
        Assert-True ($real005NextOpenId -eq 'REAL005A') 'P001 preflight requires REAL005A to remain next open until RG001/RG002 pass'
    }
    $real005NextSliceCoverage = $real005Report.sliceCoverage.PSObject.Properties[$real005NextOpenId].Value
    Assert-True ($null -ne $real005NextSliceCoverage) "P001 preflight requires REAL005 slice coverage for next open slice: $real005NextOpenId"
    Assert-True ([string]$real005NextSliceCoverage.status -ne 'pass') "P001 preflight requires current REAL005 boundary slice to remain open while live pilot is preflight-only: $real005NextOpenId"
    Assert-True (@($real005NextSliceCoverage.blockers).Count -ge 1) "P001 preflight requires current REAL005 boundary blockers while live pilot is preflight-only: $real005NextOpenId"
}
Assert-True ($real012Report.status -eq 'pass') 'REAL012 report must pass before P001 preflight'
Assert-True (@($real012Report.searchProbe.selectedQuestionNos).Count -ge 3) 'REAL012 must prove ordered real-question search sample'
Assert-True ([int]$real012Report.searchProbe.hasImageCount -ge 3) 'REAL012 must prove image-backed real question cards'
Assert-True ([int]$real012Report.paperBasket.itemCount -ge 3) 'REAL012 must prove reviewed real questions enter a paper basket'
Assert-True ($real012Report.exportPreflight.status -eq 'ready_for_review') 'REAL012 must prove export preflight is ready for reviewed real samples'
Assert-True ($real012Report.artifact.status -eq 'pass') 'REAL012 must prove Word/PDF draft artifacts'
Assert-True ($real012Report.analysis.status -eq 'ready') 'REAL012 must prove analysis report readiness'
Assert-True ($real012Report.analysis.allowAiDraftText -eq $false) 'REAL012 must keep AI draft text disabled for this real sample'
Assert-True ($real012Report.analysis.writesProductionHistory -eq $false) 'REAL012 must not write formal history during P001 preflight'
Assert-True ($real012Report.qualityReport.closureStatus -eq 'not_closed') 'REAL012 quality report must keep full paper closure not_closed when gaps remain'
Assert-True ($real012Report.real005ClosureStatus -eq 'not_closed') 'REAL005 full closure must remain not_closed before live pilot'

$hostReport = Read-JsonFile $HostCapabilityReportPath
Assert-True ($hostReport.schemaVersion -eq 'host-capability-diagnostic.v1') 'host capability diagnostic schema mismatch'
Assert-True ($hostReport.mode -eq 'read_only') 'host capability diagnostic must be read_only'
Assert-True ([bool]$hostReport.guardrail.noInstallPerformed) 'host capability diagnostic must not install dependencies'
Assert-True ([bool]$hostReport.guardrail.noNetworkRequired) 'host capability diagnostic must not require network'
Assert-True (-not [bool]$hostReport.guardrail.productionDefaultChanged) 'host capability diagnostic must not change production defaults'
Assert-True (-not [bool]$hostReport.guardrail.localAiDefaultChanged) 'host capability diagnostic must not change local AI defaults'
Assert-True (-not [bool]$hostReport.guardrail.modelWeightsDownloaded) 'host capability diagnostic must not download model weights'
Assert-True ([bool]$hostReport.recommendedProfiles.aiLocalModelProfile.requiresEvalBeforeDefault) 'aiLocalModelProfile must require eval before default'
Assert-True ([bool]$hostReport.recommendedProfiles.aiLocalModelProfile.noActiveWrite) 'aiLocalModelProfile must forbid active writes'

$workerReport = Read-JsonFile $WorkerProfileReportPath
Assert-True ($workerReport.schemaVersion -eq 'worker-profile-diagnostic.v1') 'worker profile diagnostic schema mismatch'
Assert-True ($workerReport.mode -eq 'read_only') 'worker profile diagnostic must be read_only'
Assert-True ([bool]$workerReport.guardrail.noInstallPerformed) 'worker profile diagnostic must not install dependencies'
Assert-True (-not [bool]$workerReport.guardrail.productionDefaultChanged) 'worker profile diagnostic must not change production default'
Assert-True (@('direct_venv_lite','uv_venv_lite','conda_paddle_cpu','wsl_or_docker_heavy') -contains [string]$workerReport.recommendation.recommendedDefaultProfile) 'unexpected worker profile recommendation'

$technologyReport = Read-JsonFile $TechnologyRefreshReportPath
Assert-True ($technologyReport.status -eq 'pass') 'technology refresh report must pass'
Assert-True ($technologyReport.mode -eq 'report_only') 'technology refresh must remain report_only'
Assert-True ([bool]$technologyReport.boundaries.noInstall) 'technology refresh must not install'
Assert-True ([bool]$technologyReport.boundaries.noDownload) 'technology refresh must not download'
Assert-True ([bool]$technologyReport.boundaries.noDefaultRouteChange) 'technology refresh must not change default routes'
Assert-True ([bool]$technologyReport.boundaries.noRealMaterialProcessing) 'technology refresh must not process real material'
Assert-True ([bool]$technologyReport.boundaries.noProductionWrite) 'technology refresh must not write production config'

$isolatedMachineEvidenceTemplate = Get-Content -LiteralPath $isolatedMachineEvidenceTemplateFullPath -Raw | ConvertFrom-Json
foreach ($requiredField in @('execution', 'anchors', 'referenceContext', 'impactedSurfaceIds', 'referencesReviewed', 'adoptionDecision', 'installInit', 'backupRestore', 'roleAudit', 'teacherEntrySmokes', 'siteSpecific', 'na', 'signoff')) {
    Assert-True ($isolatedMachineEvidenceTemplate.PSObject.Properties.Name -contains $requiredField) "P001 isolated-machine evidence template missing field: $requiredField"
}
Assert-True (@($isolatedMachineEvidenceTemplate.impactedSurfaceIds).Count -ge 1) 'P001 isolated-machine evidence template must include impactedSurfaceIds'
Assert-True (@($isolatedMachineEvidenceTemplate.referencesReviewed).Count -ge 1) 'P001 isolated-machine evidence template must include referencesReviewed'
foreach ($requiredReferenceContextField in @('referenceBasisPolicy', 'referenceRequirements', 'referenceModuleMap', 'guardEvidence')) {
    Assert-True ($isolatedMachineEvidenceTemplate.referenceContext.PSObject.Properties.Name -contains $requiredReferenceContextField) "P001 referenceContext missing field: $requiredReferenceContextField"
    Assert-True (-not [string]::IsNullOrWhiteSpace([string] $isolatedMachineEvidenceTemplate.referenceContext.$requiredReferenceContextField)) "P001 referenceContext field is blank: $requiredReferenceContextField"
}
foreach ($requiredAdoptionField in @('summary', 'adopted', 'rejected', 'followUpEvidence')) {
    Assert-True ($isolatedMachineEvidenceTemplate.adoptionDecision.PSObject.Properties.Name -contains $requiredAdoptionField) "P001 adoptionDecision missing field: $requiredAdoptionField"
}

$checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
foreach ($keyword in @('隔离机器', '安装向导', '备份', '恢复', '权限审计', '教师入口 smoke', 'REAL001-REAL012', 'quality report', 'release checklist', 'evidence', 'p001-isolated-machine-evidence-template.md')) {
    Assert-True ($checklistText.Contains($keyword)) "P001 checklist missing keyword: $keyword"
}

$isolatedMachineEvidenceTemplateText = Get-Content -LiteralPath $isolatedMachineEvidenceTemplateFullPath -Raw
foreach ($keyword in @('p001-isolated-machine-evidence.v1', 'docs/evidence/<date>-p001-live-pilot-readiness-preflight-report.json', 'docs/evidence/attachments/<date>-p001-isolated-machine/', 'operatorSignoff', 'platformNa', 'gateNa', 'referenceContext', 'referencesReviewed')) {
    Assert-True ($isolatedMachineEvidenceTemplateText.Contains($keyword)) "P001 isolated-machine evidence template missing keyword: $keyword"
}

$evidenceText = Get-Content -LiteralPath $evidenceFullPath -Raw
foreach ($keyword in @('preflight', 'P001', 'REAL012', 'not_closed', 'host capability', 'worker profile', 'technology refresh', 'platform_na', 'gate_na', '隔离机器', '下一步')) {
    Assert-True ($evidenceText.Contains($keyword)) "P001 evidence missing keyword: $keyword"
}

$report = [ordered]@{
    status = 'pass'
    taskId = 'P001'
    mode = 'preflight_only'
    p001Status = $p001.status
    liveCloseoutPlanPath = $LiveCloseoutPlanPath
    dependencies = $dependencies
    prerequisites = [ordered]@{
        S012 = $byId['S012'].status
        O004B = $byId['O004B'].status
        O006 = $byId['O006'].status
        O007 = $byId['O007'].status
        O008 = $byId['O008'].status
        REAL012 = $byId['REAL012'].status
    }
    realEvidence = $realEvidenceStatus
    real012Probe = [ordered]@{
        selectedQuestionNos = @($real012Report.searchProbe.selectedQuestionNos)
        hasImageCount = [int]$real012Report.searchProbe.hasImageCount
        paperBasketItemCount = [int]$real012Report.paperBasket.itemCount
        exportPreflightStatus = [string]$real012Report.exportPreflight.status
        artifactStatus = [string]$real012Report.artifact.status
        analysisStatus = [string]$real012Report.analysis.status
        qualityClosureStatus = [string]$real012Report.qualityReport.closureStatus
        real005ClosureStatus = [string]$real012Report.real005ClosureStatus
        gaps = @($real012Report.qualityReport.gaps)
    }
    diagnostics = [ordered]@{
        hostCapability = [ordered]@{
            path = $HostCapabilityReportPath
            mode = [string]$hostReport.mode
            profileSet = [string]$hostReport.bestConfiguration.profileSet
            aiLocalModelProfile = [string]$hostReport.recommendedProfiles.aiLocalModelProfile.recommended
            noInstallPerformed = [bool]$hostReport.guardrail.noInstallPerformed
            productionDefaultChanged = [bool]$hostReport.guardrail.productionDefaultChanged
        }
        workerProfile = [ordered]@{
            path = $WorkerProfileReportPath
            mode = [string]$workerReport.mode
            recommendedDefaultProfile = [string]$workerReport.recommendation.recommendedDefaultProfile
            noInstallPerformed = [bool]$workerReport.guardrail.noInstallPerformed
        }
        technologyRefresh = [ordered]@{
            path = $TechnologyRefreshReportPath
            mode = [string]$technologyReport.mode
            noInstall = [bool]$technologyReport.boundaries.noInstall
            noDownload = [bool]$technologyReport.boundaries.noDownload
            noDefaultRouteChange = [bool]$technologyReport.boundaries.noDefaultRouteChange
        }
    }
    checklistPath = $ChecklistPath
    isolatedMachineEvidenceTemplatePath = $IsolatedMachineEvidenceTemplatePath
    evidencePath = $EvidencePath
    reportPath = $ReportPath
    closeoutPlan = [ordered]@{
        rowCount = $closeoutRows.Count
        nextOpenP001 = [string] $p001NextCloseout[0].id
        nextOpenREAL005 = $real005NextOpenId
        real005ReportPath = $REAL005ReportPath
        real005NextSliceStatus = if ($null -eq $real005NextSliceCoverage) { 'none' } else { [string]$real005NextSliceCoverage.status }
    }
    readyForIsolatedMachineRun = $true
    p001CanClose = $false
    blockers = @(
        'isolated_machine_install_wizard_not_executed',
        'isolated_machine_backup_restore_not_executed',
        'isolated_machine_role_audit_not_executed',
        'isolated_machine_four_teacher_entry_smoke_not_executed'
    )
    boundary = 'REAL001-REAL012 and read-only diagnostics are ready, but isolated-machine live rehearsal is not executed in this contract; keep P001 as todo until site-run evidence is complete, and keep REAL005 not_closed while onsite/manual closure remains open'
    checkedAt = (Get-Date).ToString('s')
}

$reportJson = $report | ConvertTo-Json -Depth 12
Write-ContentIfChanged -Path $reportFullPath -Content $reportJson
$report | ConvertTo-Json -Depth 12

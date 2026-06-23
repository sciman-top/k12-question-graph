param(
    [string] $ReportPath = '',
    [string] $NS903ReportPath = '',
    [string] $P001ReportPath = '',
    [string] $ChecklistPath = 'docs/templates/p001-live-pilot-release-checklist.md',
    [string] $IsolatedMachineEvidenceTemplatePath = 'docs/templates/p001-isolated-machine-evidence-template.md',
    [string] $P001EvidenceMarkdownPath = 'docs/evidence/20260518-p001-live-pilot-readiness-preflight.md',
    [string] $NS803ReportPath = '',
    [string] $NS804ReportPath = '',
    [string] $NS805ReportPath = '',
    [string] $NS806ReportPath = '',
    [string] $NS901ReportPath = '',
    [string] $NS906ReportPath = '',
    [string] $REAL005ReportPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Resolve-InRepoPath([string] $RelativePath) {
    return Join-Path $repoRoot $RelativePath
}

function Read-Json([string] $Path) {
    $fullPath = Resolve-InRepoPath $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing report: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Resolve-LatestReal005ReportPath([string] $PreferredPath) {
    if (-not [string]::IsNullOrWhiteSpace($PreferredPath)) {
        return $PreferredPath
    }

    $evidenceRoot = Resolve-InRepoPath 'docs/evidence'
    Assert-Condition (Test-Path -LiteralPath $evidenceRoot) 'missing docs/evidence directory'
    $latest = @(
        Get-ChildItem -LiteralPath $evidenceRoot -Filter '*-real005-guangzhou-2015-2025-closure-standard-report.json' -File |
            Sort-Object Name -Descending |
            Select-Object -First 1
    )
    Assert-Condition ($latest.Count -eq 1) 'missing REAL005 closure standard report under docs/evidence'
    return [System.IO.Path]::GetRelativePath($repoRoot, $latest[0].FullName).Replace('\', '/')
}

function Resolve-LatestEvidencePath([string] $Filter) {
    $evidenceRoot = Resolve-InRepoPath 'docs/evidence'
    Assert-Condition (Test-Path -LiteralPath $evidenceRoot) 'missing docs/evidence directory'
    $latest = @(
        Get-ChildItem -LiteralPath $evidenceRoot -Filter $Filter -File |
            Sort-Object Name -Descending |
            Select-Object -First 1
    )
    Assert-Condition ($latest.Count -eq 1) "missing evidence matching filter: $Filter"
    return [System.IO.Path]::GetRelativePath($repoRoot, $latest[0].FullName).Replace('\', '/')
}

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = ('docs/evidence/{0}-ns904-p001-readiness.json' -f (Get-Date -Format 'yyyyMMdd'))
}
if ([string]::IsNullOrWhiteSpace($NS903ReportPath)) {
    $NS903ReportPath = Resolve-LatestEvidencePath '*-ns903-completion-dashboard.json'
}
if ([string]::IsNullOrWhiteSpace($P001ReportPath)) {
    $P001ReportPath = Resolve-LatestEvidencePath '*-p001-live-pilot-readiness-preflight-report.json'
}
if ([string]::IsNullOrWhiteSpace($NS803ReportPath)) {
    $NS803ReportPath = Resolve-LatestEvidencePath '*-ns803-installer-host.json'
}
if ([string]::IsNullOrWhiteSpace($NS804ReportPath)) {
    $NS804ReportPath = Resolve-LatestEvidencePath '*-ns804-windows-service.json'
}
if ([string]::IsNullOrWhiteSpace($NS805ReportPath)) {
    $NS805ReportPath = Resolve-LatestEvidencePath '*-ns805-health-dashboard.json'
}
if ([string]::IsNullOrWhiteSpace($NS806ReportPath)) {
    $NS806ReportPath = Resolve-LatestEvidencePath '*-ns806-upgrade-bundle.json'
}
if ([string]::IsNullOrWhiteSpace($NS901ReportPath)) {
    $NS901ReportPath = Resolve-LatestEvidencePath '*-ns901-non-site-scenario-pack.json'
}
if ([string]::IsNullOrWhiteSpace($NS906ReportPath)) {
    $NS906ReportPath = Resolve-LatestEvidencePath '*-ns906-visual-surrogate-review-report.json'
}

function Assert-TextContains([string] $Text, [string[]] $Needles, [string] $Label) {
    foreach ($needle in $Needles) {
        Assert-Condition ($Text.Contains($needle)) "$Label missing keyword: $needle"
    }
}

function Assert-ItemsContain([string[]] $Actual, [string[]] $Required, [string] $Label) {
    foreach ($item in $Required) {
        Assert-Condition ($Actual -contains $item) "$Label missing item: $item"
    }
}

Push-Location $repoRoot
try {
    $REAL005ReportPath = Resolve-LatestReal005ReportPath $REAL005ReportPath
    $ns903 = Read-Json $NS903ReportPath
    $p001 = Read-Json $P001ReportPath
    $ns803 = Read-Json $NS803ReportPath
    $ns804 = Read-Json $NS804ReportPath
    $ns805 = Read-Json $NS805ReportPath
    $ns806 = Read-Json $NS806ReportPath
    $ns901 = Read-Json $NS901ReportPath
    $ns906 = Read-Json $NS906ReportPath
    $real005 = Read-Json $REAL005ReportPath

    foreach ($dependency in @(
        @{ name = 'NS903'; report = $ns903 },
        @{ name = 'P001'; report = $p001 },
        @{ name = 'NS803'; report = $ns803 },
        @{ name = 'NS804'; report = $ns804 },
        @{ name = 'NS805'; report = $ns805 },
        @{ name = 'NS806'; report = $ns806 },
        @{ name = 'NS901'; report = $ns901 },
        @{ name = 'NS906'; report = $ns906 },
        @{ name = 'REAL005'; report = $real005 }
    )) {
        Assert-Condition ($dependency.report.status -eq 'pass') "NS904 dependency $($dependency.name) did not pass"
    }

    Assert-Condition (-not [bool]$ns903.productionEligible) 'NS904 must inherit NS903 non-production boundary'
    Assert-Condition (-not [bool]$ns903.nonSiteValidated) 'NS904 must keep non_site_validated false'
    Assert-Condition ([int]$ns903.dashboard.releaseReadyCount -eq 0) 'NS904 must keep release_ready count at zero'
    Assert-Condition (-not [bool]$ns903.blockers.p001CanClose) 'NS904 must keep P001 blocked in NS903'
    Assert-Condition ($ns903.blockers.real005ClosureStatus -eq 'not_closed') 'NS904 must keep REAL005 not_closed through NS903'

    Assert-Condition ($p001.mode -eq 'preflight_only') 'NS904 requires P001 preflight-only evidence'
    Assert-Condition ($p001.p001Status -eq '待办') 'NS904 must not close P001'
    Assert-Condition ([bool]$p001.readyForIsolatedMachineRun) 'NS904 requires P001 to be ready for isolated-machine run'
    Assert-Condition (-not [bool]$p001.p001CanClose) 'NS904 must keep p001CanClose=false'
    Assert-ItemsContain @($p001.blockers | ForEach-Object { [string]$_ }) @(
        'isolated_machine_install_wizard_not_executed',
        'isolated_machine_backup_restore_not_executed',
        'isolated_machine_role_audit_not_executed',
        'isolated_machine_four_teacher_entry_smoke_not_executed'
    ) 'P001 blockers'

    Assert-Condition ($ns803.installer.configMode -eq 'draft_test') 'NS904 requires draft/test installer config'
    Assert-Condition ([bool]$ns803.acceptance.ns802RestoreEvidencePassed) 'NS904 requires NS803 restore prerequisite evidence'
    Assert-Condition ([bool]$ns803.acceptance.pgpassDryRunPassed) 'NS904 requires pgpass dry-run evidence'
    Assert-Condition ([bool]$ns803.acceptance.noDependencyInstall) 'NS904 must not install dependencies through NS803'
    Assert-Condition ([bool]$ns803.acceptance.noActiveWrite) 'NS904 must not active-write through NS803'

    Assert-Condition ([bool]$ns804.acceptance.explicitContentRootSmokePassed) 'NS904 requires NS804 contentRoot smoke'
    Assert-Condition ([bool]$ns804.acceptance.healthReadinessPassed) 'NS904 requires NS804 health/readiness evidence'
    Assert-Condition ([bool]$ns804.acceptance.noWindowsServiceInstalled) 'NS904 must not install a Windows Service'

    Assert-Condition ([bool]$ns805.acceptance.fileStoreCapacityVisible) 'NS904 requires file-store capacity visibility'
    Assert-Condition ([bool]$ns805.acceptance.backupManifestVisible) 'NS904 requires backup manifest visibility'
    Assert-Condition ([bool]$ns805.acceptance.restoreHealthVisible) 'NS904 requires restore health visibility'
    Assert-Condition ([bool]$ns805.acceptance.noProductionDataDelete) 'NS904 must not delete production data through NS805'

    Assert-Condition ([bool]$ns806.acceptance.efBundleExists) 'NS904 requires EF bundle evidence'
    Assert-Condition ([bool]$ns806.acceptance.restoreDrillAfterBundle) 'NS904 requires post-bundle restore drill'
    Assert-Condition ([bool]$ns806.acceptance.noSourceOrSdkRequiredAtExecution) 'NS904 requires source/SDK-free migration execution evidence'

    Assert-Condition (-not [bool]$ns901.productionEligible) 'NS904 must inherit NS901 non-production boundary'
    Assert-Condition (-not [bool]$ns901.nonSiteValidated) 'NS904 must not claim non_site_validated'
    Assert-Condition ([bool]$ns901.acceptance.backupRestoreCovered) 'NS904 requires NS901 backup/restore scenario coverage'
    Assert-Condition ([bool]$ns901.acceptance.rollbackCommandRecorded) 'NS904 requires rollback command evidence'
    Assert-Condition (-not [bool]$ns901.realStudentDataUsed) 'NS904 must not use real student data'

    Assert-Condition (-not [bool]$ns906.productionEligible) 'NS904 must inherit NS906 non-production boundary'
    Assert-Condition ([int]@($ns906.workflowCoverage.missing).Count -eq 0) 'NS904 requires NS906 workflow coverage to have no missing steps'
    Assert-ItemsContain @($ns906.aiVisionBoundary.cannotReplace | ForEach-Object { [string]$_ }) @(
        '真实教师偏好',
        '学校隔离机',
        '打印机',
        '权限域',
        '真实网络',
        '最终发布裁决'
    ) 'NS906 cannotReplace boundary'

    Assert-Condition ($real005.closureStatus -eq 'not_closed') 'NS904 must keep REAL005 closureStatus not_closed'
    Assert-Condition (-not [bool]$real005.fullClosureAllowed) 'NS904 must not allow REAL005 full closure'
    Assert-Condition ($null -ne $real005.sliceCoverage) 'NS904 requires REAL005 sliceCoverage'
    Assert-Condition ($null -ne $real005.sliceCoverage.REAL005A) 'NS904 requires REAL005A slice coverage'
    Assert-Condition ($null -ne $real005.sliceCoverage.REAL005B) 'NS904 requires REAL005B slice coverage'
    Assert-Condition ($null -ne $real005.sliceCoverage.REAL005C) 'NS904 requires REAL005C slice coverage'
    Assert-Condition ($null -ne $real005.sliceCoverage.REAL005D) 'NS904 requires REAL005D slice coverage'
    $real005AStatus = [string]$real005.sliceCoverage.REAL005A.status
    $real005BStatus = [string]$real005.sliceCoverage.REAL005B.status
    $real005CStatus = [string]$real005.sliceCoverage.REAL005C.status
    $real005DStatus = [string]$real005.sliceCoverage.REAL005D.status
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
    Assert-Condition ($real005AStatus -eq 'pass') 'NS904 requires REAL005A to pass after RG001/RG002 source and adapter evidence is complete'
    $real005CurrentBoundarySlice = $null
    if ($expectedReal005NextOpen -eq 'none') {
        Assert-Condition ($real005DStatus -eq 'pass') 'NS904 requires REAL005D to pass once repo-side truthful wording is refreshed'
        Assert-Condition (@($real005.sliceCoverage.REAL005D.blockers).Count -eq 0) 'NS904 requires REAL005D blockers to be empty once repo-side closeout is complete'
    }
    else {
        $real005CurrentBoundarySlice = $real005.sliceCoverage.PSObject.Properties[$expectedReal005NextOpen].Value
        Assert-Condition ($null -ne $real005CurrentBoundarySlice) "NS904 requires REAL005 current boundary slice: $expectedReal005NextOpen"
        Assert-Condition ([string]$real005CurrentBoundarySlice.status -ne 'pass') "NS904 requires current REAL005 boundary slice to remain open while P001 is still preflight-only: $expectedReal005NextOpen"
        Assert-Condition (@($real005CurrentBoundarySlice.blockers).Count -ge 1) "NS904 requires current REAL005 boundary blockers while P001 is still preflight-only: $expectedReal005NextOpen"
    }

    $checklistFullPath = Resolve-InRepoPath $ChecklistPath
    $isolatedMachineEvidenceTemplateFullPath = Resolve-InRepoPath $IsolatedMachineEvidenceTemplatePath
    $p001EvidenceFullPath = Resolve-InRepoPath $P001EvidenceMarkdownPath
    Assert-Condition (Test-Path -LiteralPath $checklistFullPath) "missing checklist: $ChecklistPath"
    Assert-Condition (Test-Path -LiteralPath $isolatedMachineEvidenceTemplateFullPath) "missing isolated-machine evidence template: $IsolatedMachineEvidenceTemplatePath"
    Assert-Condition (Test-Path -LiteralPath $p001EvidenceFullPath) "missing P001 evidence markdown: $P001EvidenceMarkdownPath"

    $checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
    Assert-TextContains $checklistText @(
        '隔离机器',
        '安装向导',
        '备份',
        '恢复',
        '权限审计',
        '教师入口 smoke',
        'p001-isolated-machine-evidence-template.md',
        'evidence'
    ) 'P001 checklist'

    $isolatedMachineEvidenceTemplateText = Get-Content -LiteralPath $isolatedMachineEvidenceTemplateFullPath -Raw
    Assert-TextContains $isolatedMachineEvidenceTemplateText @(
        'isolated-machine',
        '操作者签收',
        '打印 / 网络 / 权限域',
        'docs/evidence/<date>-p001-isolated-machine.md'
    ) 'P001 isolated-machine evidence template'

    $p001EvidenceText = Get-Content -LiteralPath $p001EvidenceFullPath -Raw
    Assert-TextContains $p001EvidenceText @(
        '隔离机器',
        '现场教师',
        '打印机',
        '网络',
        '权限域',
        'not_closed',
        'gate_na'
    ) 'P001 evidence markdown'

    $remainingSiteBlockers = @(
        [ordered]@{
            code = 'isolated_machine_install_wizard_not_executed'
            area = '隔离机安装'
            owner = 'NS1001/P001'
            requiredEvidence = '安装包版本、安装目录、数据目录、备份目录、health/readiness 日志'
        },
        [ordered]@{
            code = 'isolated_machine_backup_restore_not_executed'
            area = '隔离机备份恢复'
            owner = 'NS1001/P001'
            requiredEvidence = 'backup manifest、verify 输出、restore drill 输出和回滚命令'
        },
        [ordered]@{
            code = 'isolated_machine_role_audit_not_executed'
            area = '权限与审计'
            owner = 'NS1001/P001'
            requiredEvidence = 'teacher/group_lead/admin 分离、admin/internal fail-closed、高风险操作 audit'
        },
        [ordered]@{
            code = 'onsite_teacher_observation_not_recorded'
            area = '现场教师观察'
            owner = 'P001/P002'
            requiredEvidence = '四个教师入口 smoke 的耗时、卡点、接管点和反馈'
        },
        [ordered]@{
            code = 'isolated_machine_four_teacher_entry_smoke_not_executed'
            area = '四入口 smoke'
            owner = 'NS1001/P001'
            requiredEvidence = '导入、组卷、成绩、分析入口在隔离机完成基本路径'
        },
        [ordered]@{
            code = 'school_printer_artifact_smoke_not_executed'
            area = '打印与导出实物'
            owner = 'P001'
            requiredEvidence = '学生版/教师版/答案版导出后在现场打印或等价打印预检记录'
        },
        [ordered]@{
            code = 'school_network_access_smoke_not_executed'
            area = '学校网络'
            owner = 'P001'
            requiredEvidence = '目标网络下教师端访问、API health/readiness、离线/断网降级记录'
        },
        [ordered]@{
            code = 'school_domain_permission_smoke_not_executed'
            area = '权限域'
            owner = 'P001'
            requiredEvidence = '目标账号/域/本机权限下的登录、文件目录访问、备份目录访问和审计记录'
        },
        [ordered]@{
            code = 'live_operator_signoff_not_recorded'
            area = '操作者签收'
            owner = 'P001'
            requiredEvidence = '现场执行人、时间、机器、版本、风险、回滚确认和最终裁决'
        }
    )

    Assert-ItemsContain @($remainingSiteBlockers | ForEach-Object { [string]$_.code }) @(
        'isolated_machine_install_wizard_not_executed',
        'isolated_machine_backup_restore_not_executed',
        'isolated_machine_role_audit_not_executed',
        'onsite_teacher_observation_not_recorded',
        'isolated_machine_four_teacher_entry_smoke_not_executed',
        'school_printer_artifact_smoke_not_executed',
        'school_network_access_smoke_not_executed',
        'school_domain_permission_smoke_not_executed',
        'live_operator_signoff_not_recorded'
    ) 'NS904 remaining site blockers'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS904'
        checkedAt = (Get-Date).ToString('s')
        mode = 'p001_readiness_evidence_pack'
        productionEligible = $false
        nonSiteValidated = $false
        releaseReady = $false
        externalAiCalls = 0
        realStudentDataUsed = $false
        containsStudentPii = $false
        writesProductionHistory = $false
        activeAssetMutation = $false
        p001Status = [string]$p001.p001Status
        p001CanClose = $false
        readyForIsolatedMachineRun = [bool]$p001.readyForIsolatedMachineRun
        dependency = [ordered]@{
            ns903 = $NS903ReportPath
            p001 = $P001ReportPath
            ns803 = $NS803ReportPath
            ns804 = $NS804ReportPath
            ns805 = $NS805ReportPath
            ns806 = $NS806ReportPath
            ns901 = $NS901ReportPath
            ns906 = $NS906ReportPath
            real005 = $REAL005ReportPath
            checklist = $ChecklistPath
            isolatedMachineEvidenceTemplate = $IsolatedMachineEvidenceTemplatePath
            p001EvidenceMarkdown = $P001EvidenceMarkdownPath
        }
        readinessPack = [ordered]@{
            checklistPath = $ChecklistPath
            isolatedMachineEvidenceTemplatePath = $IsolatedMachineEvidenceTemplatePath
            preflightReportPath = $P001ReportPath
            ns8InstallerPackageReady = $true
            ns8BackupRestoreUpgradeReady = $true
            ns9ScenarioPackReady = $true
            visualSurrogateReady = $true
            dashboardRefreshReady = $true
            readyForIsolatedMachineRun = [bool]$p001.readyForIsolatedMachineRun
            releaseReadyCount = [int]$ns903.dashboard.releaseReadyCount
            nonSiteValidatedCount = [int]$ns903.nonSitePlan.nonSiteValidatedCount
            real005ClosureStatus = [string]$real005.closureStatus
            real005ASliceStatus = $real005AStatus
            real005BStatus = $real005BStatus
            real005CStatus = $real005CStatus
            real005DStatus = $real005DStatus
            real005NextOpenSlice = $expectedReal005NextOpen
            real005NextOpenBlockers = if ($null -eq $real005CurrentBoundarySlice) { [string[]]@() } else { [string[]]@($real005CurrentBoundarySlice.blockers) }
        }
        remainingSiteBlockers = $remainingSiteBlockers
        originalP001Blockers = @($p001.blockers)
        acceptance = [ordered]@{
            ns903DashboardPassed = $true
            p001PreflightPassed = $true
            p001RemainsTodo = $true
            p001CanCloseFalse = $true
            isolatedMachineChecklistLinked = $true
            isolatedMachineEvidenceTemplateLinked = $true
            installerHostEvidencePassed = $true
            windowsServicePackageEvidencePassed = $true
            capacityHealthDashboardEvidencePassed = $true
            efBundleUpgradeRestoreEvidencePassed = $true
            nonSiteScenarioPackEvidencePassed = $true
            visualSurrogateCannotReplaceSiteChecks = $true
            printerNetworkDomainTeacherBlockersExplicit = $true
            releaseReadyNotClaimed = $true
            nonSiteValidatedNotClaimed = $true
            real005NotClosed = $true
            noExternalAiCall = $true
            noRealStudentData = $true
            noStudentPii = $true
            noProductionHistoryWrite = $true
            noActiveWrite = $true
        }
        verification = [ordered]@{
            build = 'outer gate: dotnet build apps/api/K12QuestionGraph.Api.csproj before NS904'
            test = 'P001 preflight report plus NS803/NS804/NS805/NS806/NS901/NS903/NS906/REAL005 evidence aggregation'
            contractInvariant = 'NS904 assembles the P001 readiness pack, links the checklist, keeps P001 todo, keeps release_ready/non_site_validated false, and requires isolated-machine, onsite teacher, printer, network, domain permission, and operator signoff blockers to remain explicit'
            hotspot = 'gate_na: live P001 requires isolated target-machine installation, school network/printer/domain checks, real teacher observation, and operator signoff; this script only packages and guards the preflight evidence'
        }
        boundary = 'NS904 proves that the P001 readiness evidence pack is assembled and ready for an isolated-machine run. It does not execute the isolated-machine run, does not close P001, does not mark release_ready/non_site_validated, and does not close REAL005.'
        rollback = "git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1 tools/README.md; git clean -f -- tools/run-ns904-p001-readiness-pack.ps1 $ReportPath"
        next = 'NS905 can audit backlog/completion-dashboard/NS plan status synchronization; NS1001/P001 still require isolated-machine execution evidence.'
    }

    $jsonText = $report | ConvertTo-Json -Depth 12
    $reportFullPath = Resolve-InRepoPath $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $jsonText | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $jsonText
}
finally {
    Pop-Location
}

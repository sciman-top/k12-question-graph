param(
    [string] $Ns804ReportPath = '',
    [string] $Ns805ReportPath = '',
    [string] $Ns806ReportPath = '',
    [string] $ReportPath = 'docs/evidence/20260607-ns1302-service-control-panel.json',
    [string] $WebRoot = 'apps/web'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Read-Json([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing report: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Read-Text([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing file: $Path"
    return Get-Content -LiteralPath $fullPath -Raw
}

function Resolve-LatestEvidencePath([string] $Filter, [string] $Label) {
    $evidenceRoot = Join-Path $repoRoot 'docs\evidence'
    Assert-Condition (Test-Path -LiteralPath $evidenceRoot) 'missing docs/evidence directory'
    $latest = @(
        Get-ChildItem -LiteralPath $evidenceRoot -Filter $Filter -File |
            Sort-Object Name -Descending |
            Select-Object -First 1
    )
    Assert-Condition ($latest.Count -eq 1) "missing $Label matching filter: $Filter"
    return [System.IO.Path]::GetRelativePath($repoRoot, $latest[0].FullName).Replace('\', '/')
}

if ([string]::IsNullOrWhiteSpace($Ns804ReportPath)) {
    $Ns804ReportPath = Resolve-LatestEvidencePath '*-ns804-windows-service.json' 'NS804 report'
}
if ([string]::IsNullOrWhiteSpace($Ns805ReportPath)) {
    $Ns805ReportPath = Resolve-LatestEvidencePath '*-ns805-health-dashboard.json' 'NS805 report'
}
if ([string]::IsNullOrWhiteSpace($Ns806ReportPath)) {
    $Ns806ReportPath = Resolve-LatestEvidencePath '*-ns806-upgrade-bundle.json' 'NS806 report'
}

Push-Location $repoRoot
try {
    $ns804 = Read-Json $Ns804ReportPath
    $ns805 = Read-Json $Ns805ReportPath
    $ns806 = Read-Json $Ns806ReportPath

    Assert-Condition ($ns804.status -eq 'pass') 'NS1302 dependency NS804 did not pass'
    Assert-Condition ($ns805.status -eq 'pass') 'NS1302 dependency NS805 did not pass'
    Assert-Condition ($ns806.status -eq 'pass') 'NS1302 dependency NS806 did not pass'

    Assert-Condition ([bool]$ns804.acceptance.explicitContentRootSmokePassed) 'NS1302 requires explicit contentRoot smoke'
    Assert-Condition ([bool]$ns804.acceptance.dataRootSeparatedFromProgramRoot) 'NS1302 requires dataRoot/programRoot separation'
    Assert-Condition ([bool]$ns804.acceptance.healthReadinessPassed) 'NS1302 requires package health/readiness evidence'
    Assert-Condition ([bool]$ns805.acceptance.fileStoreCapacityVisible) 'NS1302 requires health dashboard capacity evidence'
    Assert-Condition ([bool]$ns805.acceptance.backupManifestVisible) 'NS1302 requires backup visibility evidence'
    Assert-Condition ([bool]$ns806.acceptance.efBundleExists) 'NS1302 requires upgrade bundle evidence'
    Assert-Condition ([bool]$ns806.acceptance.restoreDrillAfterBundle) 'NS1302 requires restore drill after upgrade bundle'

    $buildOutput = & npm --prefix $WebRoot run build 2>&1
    Assert-Condition ($LASTEXITCODE -eq 0) "NS1302 npm build failed: $($buildOutput | Out-String)"

    $lintOutput = & npm --prefix $WebRoot run lint 2>&1
    Assert-Condition ($LASTEXITCODE -eq 0) "NS1302 npm lint failed: $($lintOutput | Out-String)"

    $adminPanel = Read-Text 'apps/web/src/ui/AdminGovernancePanels.tsx'
    $servicePanel = Read-Text 'apps/web/src/ui/ServiceControlPanel.tsx'
    $css = Read-Text 'apps/web/src/App.css'
    $program = Read-Text 'apps/api/Program.cs'
    $technology = Read-Text 'docs/04_TechnologyStack.md'

    foreach ($marker in @(
        'data-flow="service-control-panel"',
        'data-contract="ns1302-admin-only"',
        'data-contract="windows-service-default-host"',
        'data-contract="control-panel-admin-only"',
        'data-contract="service-control-roots-and-status"',
        'data-contract="service-control-readiness"',
        'data-contract="service-control-actions"',
        'data-contract="no-teacher-workflow-in-control-panel"'
    )) {
        Assert-Condition ($servicePanel.Contains($marker)) "NS1302 service control panel marker missing: $marker"
    }

    foreach ($contractName in @(
        'windows-service-package-ready',
        'service-control-health-diagnostics',
        'service-control-upgrade-rehearsal'
    )) {
        Assert-Condition (
            $servicePanel.Contains("data-contract=""$contractName""") -or
            $servicePanel.Contains("contract: '$contractName'")
        ) "NS1302 service readiness contract missing: $contractName"
    }

    foreach ($actionName in @(
        'service-status-overview',
        'service-open-diagnostics',
        'service-open-config-diff',
        'service-open-backup-restore',
        'service-open-upgrade-rehearsal',
        'open-teacher-web-workbench'
    )) {
        Assert-Condition (
            $servicePanel.Contains("data-action=""$actionName""") -or
            $servicePanel.Contains("action: '$actionName'")
        ) "NS1302 service action marker missing: $actionName"
    }

    Assert-Condition ($adminPanel.Contains("from './ServiceControlPanel'")) 'NS1302 admin panel must import ServiceControlPanel'
    Assert-Condition ($adminPanel.Contains('<ServiceControlPanel />')) 'NS1302 admin panel must mount ServiceControlPanel'

    foreach ($cssMarker in @(
        '.service-control-panel',
        '.service-control-grid',
        '.service-control-card',
        '.service-control-readiness',
        '.service-readiness-row',
        '.service-control-actions'
    )) {
        Assert-Condition ($css.Contains($cssMarker)) "NS1302 CSS marker missing: $cssMarker"
    }

    foreach ($programMarker in @(
        'builder.Host.UseWindowsService();',
        'app.MapGet("/health"',
        'app.MapGet("/health/ready"',
        'app.MapGet("/api/admin/storage/summary"'
    )) {
        Assert-Condition ($program.Contains($programMarker)) "NS1302 API/runtime marker missing: $programMarker"
    }

    foreach ($docMarker in @(
        'Windows Service 主进程 + 安装初始化向导 + 服务端控制面板 + 浏览器教师工作台',
        '服务端控制面板',
        '只做服务状态、安装初始化、profile、AI 配置、备份恢复和升级演练'
    )) {
        Assert-Condition ($technology.Contains($docMarker)) "NS1302 technology doc marker missing: $docMarker"
    }

    $sectionPattern = '<section[\s\S]*?className="service-control-panel"[\s\S]*?</section>'
    $sectionMatch = [regex]::Match($servicePanel, $sectionPattern)
    Assert-Condition ($sectionMatch.Success) 'NS1302 service control panel section missing'
    $section = $sectionMatch.Value

    foreach ($forbidden in @(
        '导入试卷',
        '找题组卷',
        '导入成绩',
        '查看分析',
        'data-action="teacher-entry"',
        'data-flow="paper-assembly-workbench"',
        'data-flow="score-import-workbench"',
        'data-flow="manual-review"'
    )) {
        Assert-Condition (-not $section.Contains($forbidden)) "NS1302 control panel leaks teacher workflow marker: $forbidden"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS1302'
        checkedAt = (Get-Date).ToString('s')
        mode = 'windows_service_and_service_control_panel_contract'
        productionEligible = $false
        dependency = [ordered]@{
            ns804 = $Ns804ReportPath
            ns805 = $Ns805ReportPath
            ns806 = $Ns806ReportPath
        }
        runtime = [ordered]@{
            windowsServiceHost = $true
            contentRoot = [string]$ns804.smoke.contentRoot
            dataRoot = [string]$ns804.smoke.dataRoot
            apiExecutable = [string]$ns804.package.apiExecutable
            healthReadinessPassed = [bool]$ns804.acceptance.healthReadinessPassed
            packageRuntime = [string]$ns804.package.runtime
        }
        controlPanel = [ordered]@{
            ui = 'apps/web/src/ui/ServiceControlPanel.tsx'
            mountedFrom = 'apps/web/src/ui/AdminGovernancePanels.tsx'
            actionCount = 6
            readonlyEvidence = @(
                'windows-service-package-ready',
                'service-control-health-diagnostics',
                'service-control-upgrade-rehearsal'
            )
            teacherWorkflowEmbedded = $false
        }
        healthAndUpgrade = [ordered]@{
            storageAreas = @($ns805.dashboard.storageAreas | ForEach-Object { [string]$_.name })
            backupManifest = [string]$ns805.dashboard.backup.manifest
            bundleExe = [string]$ns806.migrationBundle.bundleExe
            restoreDrillReport = [string]$ns806.upgradeDrill.restoreDrillReport
        }
        acceptance = [ordered]@{
            windowsServiceIsDefaultHostShape = $true
            contentDataRootsExplicit = $true
            controlPanelAdminOnly = $true
            controlPanelCoversStatusDiagnosticsConfigBackupUpgradeOpenWeb = $true
            controlPanelDoesNotEmbedTeacherWorkflow = $true
            packageHealthSmokeVisible = $true
            backupRestoreEvidenceVisible = $true
            upgradeRehearsalEvidenceVisible = $true
        }
        verification = [ordered]@{
            build = 'npm --prefix apps/web run build'
            test = 'npm --prefix apps/web run lint'
            contractInvariant = 'NS804 package smoke + NS805 health dashboard + NS806 upgrade rehearsal + service control panel UI contract'
            hotspot = 'gate_na: no real Windows service install/start/stop against isolated target machine; NS1001/P001 still own live deployment and operator validation'
        }
        boundary = 'NS1302 proves the repository has a Windows Service-first runtime contract and an administrator-only service control panel surface. It does not install or start a real Windows Service on a target machine, and it does not move teacher workflows into the control panel.'
        rollback = "git restore apps/web/src/ui/AdminGovernancePanels.tsx apps/web/src/ui/ServiceControlPanel.tsx apps/web/src/App.css docs/04_TechnologyStack.md tasks/non-site-implementation-plan.csv tasks/productization-roadmap.csv tools/run-gates.ps1; git clean -f -- tools/run-ns1302-service-control-panel-contract.ps1 $ReportPath"
        next = 'NS1303 can continue host capability -> runtime profile/config generation after the control panel contract is fixed.'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 10
}
finally {
    Pop-Location
}

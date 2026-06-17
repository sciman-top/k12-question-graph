param(
    [string] $ReportPath = 'docs/evidence/20260607-ns1308-release-evidence-pack.json'
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
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing json report: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Read-Text([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing text file: $Path"
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

Push-Location $repoRoot
try {
    $ns803ReportPath = Resolve-LatestEvidencePath '*-ns803-installer-host.json' 'NS803 report'
    $ns804ReportPath = Resolve-LatestEvidencePath '*-ns804-windows-service.json' 'NS804 report'
    $ns805ReportPath = Resolve-LatestEvidencePath '*-ns805-health-dashboard.json' 'NS805 report'
    $ns806ReportPath = Resolve-LatestEvidencePath '*-ns806-upgrade-bundle.json' 'NS806 report'
    $ns904ReportPath = Resolve-LatestEvidencePath '*-ns904-p001-readiness.json' 'NS904 report'
    $p001ReportPath = Resolve-LatestEvidencePath '*-p001-live-pilot-readiness-preflight-report.json' 'P001 report'
    $ns803 = Read-Json $ns803ReportPath
    $ns804 = Read-Json $ns804ReportPath
    $ns805 = Read-Json $ns805ReportPath
    $ns806 = Read-Json $ns806ReportPath
    $ns904 = Read-Json $ns904ReportPath
    $p001 = Read-Json $p001ReportPath

    foreach ($report in @($ns803, $ns804, $ns805, $ns806, $ns904, $p001)) {
        Assert-Condition ($report.status -eq 'pass') 'NS1308 dependency report must pass'
    }

    $o004b = Read-Text 'docs/evidence/20260505-o004b-role-audit-closure.md'
    $p001Checklist = Read-Text 'docs/templates/p001-live-pilot-release-checklist.md'
    $p001IsolatedMachineEvidenceTemplate = Read-Text 'docs/templates/p001-isolated-machine-evidence-template.md'
    $releaseCard = Read-Text 'docs/109_ReleaseGoNoGoCard.md'
    $executionBoard = Read-Text 'docs/103_ExecutionControlBoard.md'
    $technologyStack = Read-Text 'docs/04_TechnologyStack.md'

    Assert-Condition ($o004b.Contains('status=pass')) 'NS1308 requires O004B pass evidence summary'
    Assert-Condition ($o004b.Contains('teacher') -and $o004b.Contains('group_lead') -and $o004b.Contains('admin')) 'NS1308 requires explicit role audit evidence'

    foreach ($marker in @(
        '安装向导',
        '备份',
        '恢复',
        '权限与审计',
        '教师入口 smoke',
        'p001-isolated-machine-evidence-template.md'
    )) {
        Assert-Condition ($p001Checklist.Contains($marker)) "NS1308 checklist marker missing: $marker"
    }
    foreach ($marker in @(
        'isolated-machine',
        '操作者签收',
        '打印 / 网络 / 权限域'
    )) {
        Assert-Condition ($p001IsolatedMachineEvidenceTemplate.Contains($marker)) "NS1308 isolated-machine evidence template marker missing: $marker"
    }

    Assert-Condition ($p001.readyForIsolatedMachineRun) 'NS1308 requires readyForIsolatedMachineRun=true'
    Assert-Condition (-not [bool]$p001.p001CanClose) 'NS1308 must not close P001'
    Assert-Condition (-not [bool]$ns904.releaseReady) 'NS1308 must not claim releaseReady'
    Assert-Condition (-not [bool]$ns904.nonSiteValidated) 'NS1308 must not claim nonSiteValidated'
    Assert-Condition (([string]$ns904.p001Status).Trim() -eq '待办') 'NS1308 must keep P001 todo'
    Assert-Condition ($ns904.remainingSiteBlockers.code -contains 'isolated_machine_four_teacher_entry_smoke_not_executed') 'NS1308 must keep four-entry onsite blocker explicit'

    Assert-Condition ($technologyStack.Contains('发布 evidence 必须覆盖 install、uninstall、upgrade、rollback')) 'NS1308 requires install/uninstall/upgrade/rollback boundary in technology stack'
    Assert-Condition ($p001Checklist.Contains('执行前确认回滚路径')) 'NS1308 requires rollback path in checklist'

    Assert-Condition ($releaseCard.Contains('`No-Go`') -or $releaseCard.Contains('No-Go')) 'NS1308 expects release card to remain No-Go before onsite and release decision closure'
    Assert-Condition ($executionBoard.Contains('`P001` readiness') -or $executionBoard.Contains('P001 readiness')) 'NS1308 expects execution board to keep P001 as current mainline'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS1308'
        checkedAt = (Get-Date).ToString('s')
        mode = 'release_evidence_pack_aggregation'
        productionEligible = $false
        dependency = [ordered]@{
            ns803 = $ns803ReportPath
            ns804 = $ns804ReportPath
            ns805 = $ns805ReportPath
            ns806 = $ns806ReportPath
            ns904 = $ns904ReportPath
            p001 = $p001ReportPath
            o004b = 'docs/evidence/20260505-o004b-role-audit-closure.md'
            checklist = 'docs/templates/p001-live-pilot-release-checklist.md'
        }
        releasePack = [ordered]@{
            installerDryRun = [ordered]@{
                status = [string]$ns803.status
                config = [string]$ns803.installer.config
                runtimeProfile = [string]$ns803.installer.hostCapability.runtimeProfile
                workerProfile = [string]$ns803.installer.workerProfile.recommendedDefaultProfile
            }
            windowsServicePackage = [ordered]@{
                status = [string]$ns804.status
                apiExecutable = [string]$ns804.package.apiExecutable
                contentRoot = [string]$ns804.smoke.contentRoot
                dataRoot = [string]$ns804.smoke.dataRoot
            }
            capacityHealth = [ordered]@{
                status = [string]$ns805.status
                backupManifest = [string]$ns805.dashboard.backup.manifest
                storageAreas = @($ns805.dashboard.storageAreas | ForEach-Object { [string]$_.name })
            }
            upgradeBundle = [ordered]@{
                status = [string]$ns806.status
                bundleExe = [string]$ns806.migrationBundle.bundleExe
                restoreDrillReport = [string]$ns806.upgradeDrill.restoreDrillReport
            }
            permissionAudit = [ordered]@{
                status = 'pass'
                source = 'docs/evidence/20260505-o004b-role-audit-closure.md'
                roleSplit = @('teacher_blocked', 'group_lead_read_only', 'admin_high_risk_write')
            }
            p001Readiness = [ordered]@{
                status = [string]$ns904.status
                readyForIsolatedMachineRun = [bool]$ns904.readyForIsolatedMachineRun
                p001CanClose = [bool]$ns904.p001CanClose
                releaseReady = [bool]$ns904.releaseReady
                nonSiteValidated = [bool]$ns904.nonSiteValidated
                remainingSiteBlockers = @($ns904.remainingSiteBlockers | ForEach-Object { [string]$_.code })
            }
            uninstallRollbackBoundary = [ordered]@{
                documentedOnly = $true
                technologyStack = 'docs/04_TechnologyStack.md'
                checklist = 'docs/templates/p001-live-pilot-release-checklist.md'
            }
        }
        acceptance = [ordered]@{
            installerDryRunEvidencePresent = $true
            windowsServicePackageEvidencePresent = $true
            migrationBundleRehearsalPresent = $true
            backupRestoreEvidencePresent = $true
            permissionAuditEvidencePresent = $true
            fourTeacherEntrySmokeChecklistPresent = $true
            p001ReadinessPackPresent = $true
            uninstallRollbackBoundaryDocumented = $true
            readyForIsolatedMachineRun = $true
            releaseReadyStillFalse = $true
            p001StillTodo = $true
            onsiteBlockersExplicit = $true
        }
        verification = [ordered]@{
            build = 'gate_na: NS1308 is an evidence-pack aggregation slice; it reuses already-passed installer/package/upgrade/readiness contracts'
            test = 'NS803 + NS804 + NS805 + NS806 + NS904 + P001 preflight + O004B evidence aggregation'
            contractInvariant = 'installer/upgrade/backup-restore/permission-audit/four-entry smoke checklist/P001 readiness pack must be linkable without claiming onsite execution or release-ready state'
            hotspot = 'gate_na: no isolated-machine install, no printer/network/domain run, no onsite teacher observation, and no release signoff in this slice'
        }
        boundary = 'NS1308 proves the repository now has an aggregated non-site release evidence pack covering installer dry-run, Windows Service package shape, backup/restore, upgrade bundle, permission audit evidence, and the P001 readiness pack. It does not execute the isolated-machine rehearsal, does not close P001/P003/P005/P006, and does not create a release candidate.'
        rollback = "git restore docs/103_ExecutionControlBoard.md docs/109_ReleaseGoNoGoCard.md tasks/backlog.csv tasks/non-site-implementation-plan.csv tasks/productization-roadmap.csv tools/run-gates.ps1 tools/README.md; git clean -f -- tools/run-ns1308-release-evidence-pack-contract.ps1 $ReportPath docs/evidence/20260607-ns1308-release-evidence-pack-closure.md"
        next = 'P001 becomes the remaining mainline entry; the repository-side NS13 closure no longer blocks progression to isolated-machine and onsite facts.'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 10
}
finally {
    Pop-Location
}

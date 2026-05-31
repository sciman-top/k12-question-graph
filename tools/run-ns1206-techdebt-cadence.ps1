param(
    [string] $ReportPath = 'docs/evidence/20260531-ns1206-techdebt-cadence.json',
    [string] $NonSitePlanPath = 'tasks/non-site-implementation-plan.csv',
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $R006ReportPath = 'docs/evidence/20260522-r006-techdebt-cadence-admission-report.json',
    [string] $R006DecisionPath = 'docs/decisions/ADR-008-techdebt-cadence-admission.md',
    [string] $R006ChecklistPath = 'docs/templates/r006-techdebt-cadence-checklist.md',
    [string] $R006PreflightEvidencePath = 'docs/evidence/20260505-r006-techdebt-cadence-preflight.md',
    [string] $CompletionDashboardPath = 'tasks/completion-state-dashboard.csv',
    [string] $GatesPath = 'tools/run-gates.ps1',
    [string] $RoadmapGuardPath = 'tools/run-roadmap-guard.ps1'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Resolve-InRepoPath([string] $RelativePath) {
    return Join-Path $repoRoot ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
}

function Read-Json([string] $Path) {
    $fullPath = Resolve-InRepoPath $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing json report: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Get-RequiredRow([object[]] $Rows, [string] $Id, [string] $Column = 'id') {
    $matches = @($Rows | Where-Object { [string]$_.$Column -eq $Id })
    Assert-Condition ($matches.Count -eq 1) "expected exactly one $Column=$Id row"
    return $matches[0]
}

function Assert-TextContains([string] $Text, [string[]] $Needles, [string] $Label) {
    foreach ($needle in $Needles) {
        Assert-Condition ($Text.Contains($needle)) "$Label missing text: $needle"
    }
}

Push-Location $repoRoot
try {
    $planFullPath = Resolve-InRepoPath $NonSitePlanPath
    $backlogFullPath = Resolve-InRepoPath $BacklogPath
    $decisionFullPath = Resolve-InRepoPath $R006DecisionPath
    $checklistFullPath = Resolve-InRepoPath $R006ChecklistPath
    $preflightEvidenceFullPath = Resolve-InRepoPath $R006PreflightEvidencePath
    $completionDashboardFullPath = Resolve-InRepoPath $CompletionDashboardPath
    $gatesFullPath = Resolve-InRepoPath $GatesPath
    $roadmapGuardFullPath = Resolve-InRepoPath $RoadmapGuardPath

    foreach ($requiredPath in @($planFullPath, $backlogFullPath, $decisionFullPath, $checklistFullPath, $preflightEvidenceFullPath, $completionDashboardFullPath, $gatesFullPath, $roadmapGuardFullPath)) {
        Assert-Condition (Test-Path -LiteralPath $requiredPath) "missing required file: $requiredPath"
    }

    $planRows = @(Import-Csv -LiteralPath $planFullPath -Encoding UTF8)
    $backlogRows = @(Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8)
    $dashboardRows = @(Import-Csv -LiteralPath $completionDashboardFullPath -Encoding UTF8)

    $ns1005 = Get-RequiredRow $planRows 'NS1005'
    $ns1206 = Get-RequiredRow $planRows 'NS1206'
    Assert-Condition ($ns1005.status -eq 'blocked_by_onsite') 'NS1206 must inherit NS1005 release-decision blocked_by_onsite boundary'
    Assert-Condition ($ns1206.depends_on -eq 'NS1005') 'NS1206 must continue to depend on NS1005'
    Assert-Condition ($ns1206.status -in @('planned','runtime_verified')) "NS1206 has unsupported status: $($ns1206.status)"
    Assert-Condition ($ns1206.acceptance -match '门禁维护' -and $ns1206.acceptance -match '依赖升级' -and $ns1206.acceptance -match '性能基线' -and $ns1206.acceptance -match '删除无效实验') 'NS1206 acceptance must keep tech-debt cadence evidence boundary'

    $p001 = Get-RequiredRow $backlogRows 'P001'
    $p006 = Get-RequiredRow $backlogRows 'P006'
    $r006 = Get-RequiredRow $backlogRows 'R006'
    Assert-Condition ($p001.status -eq '待办') 'NS1206 must not skip P001 isolated-machine evidence'
    Assert-Condition ($p006.status -eq '待办') 'NS1206 must not skip P006 release decision'
    Assert-Condition ($r006.status -eq '待办') 'NS1206 must not close R006 without release cadence owner and baseline evidence'
    Assert-Condition ($r006.depends_on -eq 'P006') 'R006 must continue to depend on P006'

    $r006Report = Read-Json $R006ReportPath
    Assert-Condition ($r006Report.status -eq 'pass') 'NS1206 requires R006 admission report to pass'
    Assert-Condition (-not [bool]$r006Report.closeTaskAllowed) 'R006 closeTaskAllowed must remain false'
    Assert-Condition ($r006Report.currentDecision -eq 'keep_R006_todo_fail_closed_for_techdebt_cadence') 'R006 decision must remain fail-closed for tech-debt cadence'
    Assert-Condition ($r006Report.currentBoundaries.dependencyRefreshMode -eq 'report_only') 'dependency refresh must remain report_only'
    Assert-Condition (-not [bool]$r006Report.currentBoundaries.dependencyInstallAllowed) 'dependency install must not be allowed'
    Assert-Condition (-not [bool]$r006Report.currentBoundaries.modelDownloadAllowed) 'model download must not be allowed'
    Assert-Condition ([bool]$r006Report.currentBoundaries.cacheCleanupRootOnly) 'cleanup must remain cache-root only'
    Assert-Condition (-not [bool]$r006Report.currentBoundaries.productionDataDeleteAllowed) 'production data delete must not be allowed'

    $matrixByArea = @{}
    foreach ($entry in @($r006Report.cadenceMatrix)) {
        $matrixByArea[[string]$entry.cadenceArea] = $entry
    }
    foreach ($area in @('gate_maintenance', 'dependency_refresh', 'performance_baseline', 'stale_experiment_cleanup')) {
        Assert-Condition ($matrixByArea.ContainsKey($area)) "R006 cadence matrix missing: $area"
    }
    Assert-Condition ($matrixByArea['gate_maintenance'].currentDecision -eq 'allowed_as_evidence_refresh') 'gate maintenance must remain evidence refresh only'
    Assert-Condition ($matrixByArea['dependency_refresh'].currentDecision -eq 'report_only') 'dependency refresh must remain report_only'
    Assert-Condition ($matrixByArea['performance_baseline'].currentDecision -eq 'blocked_until_baseline') 'performance work must remain blocked until baseline'
    Assert-Condition ($matrixByArea['stale_experiment_cleanup'].currentDecision -eq 'cache_only_draft_test_allowed') 'stale cleanup must remain cache-only draft/test'

    $decisionText = Get-Content -LiteralPath $decisionFullPath -Raw
    Assert-TextContains $decisionText @(
        'ADR-008',
        'fail-closed',
        'report-only',
        'dry-run',
        'stale experiment inventory',
        'dependency upgrade plan',
        'rollback'
    ) 'ADR-008'

    $checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
    Assert-TextContains $checklistText @(
        '门禁维护',
        '依赖升级',
        '性能基线',
        'dry-run preview',
        'rollback',
        'fail-closed'
    ) 'R006 checklist'

    $preflightText = Get-Content -LiteralPath $preflightEvidenceFullPath -Raw
    Assert-TextContains $preflightText @(
        'R006',
        'platform_na',
        'gate_na',
        '技术债',
        'fail-closed'
    ) 'R006 preflight evidence'

    $gatesText = Get-Content -LiteralPath $gatesFullPath -Raw
    Assert-TextContains $gatesText @(
        'r006 techdebt cadence preflight contract',
        'ns1206 techdebt cadence boundary pack',
        'pqr preflight pack contract'
    ) 'run-gates'

    $backupRestoreArea = Get-RequiredRow $dashboardRows 'backup-restore' 'area_id'
    $deploymentArea = Get-RequiredRow $dashboardRows 'deployment-install' 'area_id'
    $livePilotArea = Get-RequiredRow $dashboardRows 'live-pilot' 'area_id'
    Assert-Condition ($backupRestoreArea.blocking_gap -match 'P001') 'backup-restore must retain P001 operational review boundary'
    Assert-Condition ($deploymentArea.usable_today -eq '不可发布使用') 'deployment-install must remain not releasable'
    Assert-Condition ($livePilotArea.usable_today -eq '不可使用') 'live-pilot must remain unavailable'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS1206'
        checkedAt = (Get-Date).ToString('s')
        mode = 'techdebt_cadence_boundary'
        productionEligible = $false
        nonSiteValidated = $false
        releaseReady = $false
        externalAiCalls = 0
        realStudentDataUsed = $false
        containsStudentPii = $false
        writesProductionHistory = $false
        activeAssetMutation = $false
        dependency = [ordered]@{
            ns1005 = $NonSitePlanPath
            r006Report = $R006ReportPath
            r006Decision = $R006DecisionPath
            r006Checklist = $R006ChecklistPath
            r006PreflightEvidence = $R006PreflightEvidencePath
            fullGate = $GatesPath
            roadmapGuard = $RoadmapGuardPath
            completionDashboard = $CompletionDashboardPath
        }
        backlog = [ordered]@{
            p001Status = [string]$p001.status
            p006Status = [string]$p006.status
            r006Status = [string]$r006.status
            r006CloseTaskAllowed = $false
            ns1005Status = [string]$ns1005.status
            ns1206StatusAtCheck = [string]$ns1206.status
            ns1206DependsOn = [string]$ns1206.depends_on
        }
        cadenceDecision = [ordered]@{
            gateMaintenance = [string]$matrixByArea['gate_maintenance'].currentDecision
            dependencyRefresh = [string]$matrixByArea['dependency_refresh'].currentDecision
            performanceBaseline = [string]$matrixByArea['performance_baseline'].currentDecision
            staleExperimentCleanup = [string]$matrixByArea['stale_experiment_cleanup'].currentDecision
            currentDecision = [string]$r006Report.currentDecision
        }
        currentBoundaries = $r006Report.currentBoundaries
        acceptance = [ordered]@{
            r006AdmissionReportPassed = $true
            adr008FailClosedAccepted = $true
            gateMaintenanceEvidenceRefreshOnly = $true
            dependencyRefreshReportOnly = $true
            performanceBlockedUntilBaseline = $true
            staleCleanupCacheOnlyDraftTest = $true
            p001RemainsTodo = $true
            p006RemainsTodo = $true
            ns1005RemainsBlockedByOnsite = $true
            r006RemainsTodo = $true
            noDependencyUpgrade = $true
            noModelDownload = $true
            noPerformanceMutation = $true
            noExperimentDeletion = $true
            noProductionCleanup = $true
        }
        nextRequiredEvidence = @(
            'P006 release decision record',
            'release cadence owner and maintenance calendar',
            'latest full gate, roadmap guard, dependency report, and backup/restore evidence',
            'performance baseline with dataset, machine profile, budget, rollback, and teacher-efficiency impact',
            'stale experiment inventory with owner, last-used evidence, dry-run preview, and rollback',
            'dependency upgrade plan with source, diff, supply-chain risk, compatibility, and rollback evidence'
        )
        verification = [ordered]@{
            build = 'gate_na: admission boundary script only; no product code build required'
            test = 'tools/run-r006-techdebt-cadence-preflight-contract.ps1 + tools/run-ns1206-techdebt-cadence.ps1'
            contractInvariant = 'NS1206 keeps dependency refresh report-only, performance work blocked until baseline, cleanup cache-only, and leaves R006/P006/NS1005 blocked'
            hotspot = 'gate_na: operational cadence requires post-P006 release owner, calendar, full gate evidence, performance baseline, stale inventory, and rollback plans'
        }
        teacherEfficiencyBoundary = 'maintenance cadence must preserve teacher workflow stability; NS1206 prevents dependency, performance, or cleanup work from creating unbounded teacher-facing regression risk'
        boundary = 'NS1206 verifies the long-term technical-debt cadence boundary only. It does not upgrade dependencies, download models, mutate performance paths, delete experiments, clean production data, or change release state.'
        rollback = "git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1 tools/README.md; git clean -f -- tools/run-ns1206-techdebt-cadence.ps1 $ReportPath"
        next = 'All NS12 planned admission-boundary rows now have runtime evidence; NS10/P001-P006 remain blocked by onsite execution.'
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

param(
    [string] $ReportPath = 'docs/evidence/20260530-ns903-completion-dashboard.json',
    [string] $S001JsonReportPath = 'docs/evidence/20260506-s001-completion-state-dashboard.json',
    [string] $S001MarkdownReportPath = 'docs/evidence/20260506-s001-completion-state-dashboard.md',
    [string] $REAL005ReportPath = '',
    [switch] $SkipS001Refresh
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Read-Json([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing report: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Resolve-LatestReal005ReportPath([string] $PreferredPath) {
    if (-not [string]::IsNullOrWhiteSpace($PreferredPath)) {
        return $PreferredPath
    }

    $evidenceRoot = Join-Path $repoRoot 'docs/evidence'
    Assert-Condition (Test-Path -LiteralPath $evidenceRoot) 'missing docs/evidence directory'
    $latest = @(
        Get-ChildItem -LiteralPath $evidenceRoot -Filter '*-real005-guangzhou-2015-2025-closure-standard-report.json' -File |
            Sort-Object Name -Descending |
            Select-Object -First 1
    )
    Assert-Condition ($latest.Count -eq 1) 'missing REAL005 closure standard report under docs/evidence'
    return [System.IO.Path]::GetRelativePath($repoRoot, $latest[0].FullName).Replace('\', '/')
}

function Convert-OutputToJson([object[]] $Output, [string] $Label) {
    $lines = @($Output | ForEach-Object { [string]$_ })
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].TrimStart().StartsWith('{')) {
            $start = $i
            break
        }
    }

    Assert-Condition ($start -ge 0) "$Label did not emit a JSON object"
    $jsonText = ($lines[$start..($lines.Count - 1)] -join [Environment]::NewLine)
    return $jsonText | ConvertFrom-Json
}

function Get-RequiredRow([object[]] $Rows, [string] $Id, [string] $Column = 'id') {
    $matches = @($Rows | Where-Object { [string]$_.$Column -eq $Id })
    Assert-Condition ($matches.Count -eq 1) "expected exactly one $Column=$Id row"
    return $matches[0]
}

Push-Location $repoRoot
try {
    if (-not $SkipS001Refresh) {
        $s001Output = .\tools\run-s001-completion-state-dashboard.ps1 `
            -JsonReportPath $S001JsonReportPath `
            -MarkdownReportPath $S001MarkdownReportPath
        $s001 = Convert-OutputToJson $s001Output 'S001 completion-state dashboard'
    }
    else {
        $s001 = Read-Json $S001JsonReportPath
    }

    $ns901 = Read-Json 'docs/evidence/20260530-ns901-non-site-scenario-pack.json'
    $ns902 = Read-Json 'docs/evidence/20260528-non-site-e2e-rehearsal-report.json'
    $ns906 = Read-Json 'docs/evidence/20260528-ns906-visual-surrogate-review-report.json'
    $p001 = Read-Json 'docs/evidence/20260530-p001-live-pilot-readiness-preflight-report.json'
    $REAL005ReportPath = Resolve-LatestReal005ReportPath $REAL005ReportPath
    $real005 = Read-Json $REAL005ReportPath

    Assert-Condition ($s001.status -eq 'pass') 'NS903 dependency S001 dashboard did not pass'
    Assert-Condition ($ns901.status -eq 'pass') 'NS903 dependency NS901 report did not pass'
    Assert-Condition ($ns902.status -eq 'pass') 'NS903 dependency NS902/S012B report did not pass'
    Assert-Condition ($ns906.status -eq 'pass') 'NS903 dependency NS906 report did not pass'
    Assert-Condition ($p001.status -eq 'pass') 'NS903 dependency P001 preflight report did not pass'
    Assert-Condition ($real005.status -eq 'pass') 'NS903 dependency REAL005 closure report did not pass'

    Assert-Condition (-not [bool]$ns901.productionEligible) 'NS903 must not inherit a production-eligible NS901 report'
    Assert-Condition (-not [bool]$ns901.nonSiteValidated) 'NS903 must keep NS901 below non_site_validated'
    Assert-Condition (-not [bool]$ns902.productionEligible) 'NS903 must not inherit a production-eligible NS902 report'
    Assert-Condition (-not [bool]$ns902.realStudentDataUsed) 'NS903 must not use real student data'
    Assert-Condition (-not [bool]$ns906.productionEligible) 'NS903 must not inherit a production-eligible NS906 report'
    Assert-Condition ([int]@($ns906.workflowCoverage.missing).Count -eq 0) 'NS903 requires NS906 workflow coverage to have no missing steps'
    Assert-Condition ($real005.closureStatus -eq 'not_closed') 'NS903 must keep REAL005 not_closed'
    Assert-Condition (-not [bool]$real005.fullClosureAllowed) 'NS903 must not allow REAL005 full closure'
    Assert-Condition ($null -ne $real005.sliceCoverage) 'NS903 requires REAL005 sliceCoverage'
    Assert-Condition ($null -ne $real005.sliceCoverage.REAL005A) 'NS903 requires REAL005A slice coverage'
    Assert-Condition ([string]$real005.sliceCoverage.REAL005A.status -in @('blocked', 'partial')) 'NS903 requires REAL005A to remain blocked or partial while closeout is open'
    Assert-Condition (-not [bool]$p001.p001CanClose) 'NS903 must keep P001 open until isolated-machine evidence exists'
    Assert-Condition (@($p001.blockers).Count -gt 0) 'NS903 requires P001 blockers to stay explicit'

    $planRows = @(Import-Csv -LiteralPath (Join-Path $repoRoot 'tasks/non-site-implementation-plan.csv') -Encoding UTF8)
    $dashboardRows = @(Import-Csv -LiteralPath (Join-Path $repoRoot 'tasks/completion-state-dashboard.csv') -Encoding UTF8)
    Assert-Condition ($planRows.Count -gt 0) 'non-site implementation plan is empty'
    Assert-Condition ($dashboardRows.Count -gt 0) 'completion-state dashboard is empty'

    foreach ($id in @('NS806','NS901','NS902','NS906')) {
        $row = Get-RequiredRow $planRows $id
        Assert-Condition ($row.status -eq 'runtime_verified') "NS903 dependency $id must be runtime_verified"
        Assert-Condition ($row.evidence -notmatch '<date>') "NS903 dependency $id must use concrete evidence"
        Assert-Condition (Test-Path -LiteralPath (Join-Path $repoRoot $row.evidence)) "NS903 dependency evidence missing for $id"
    }

    $ns903Row = Get-RequiredRow $planRows 'NS903'
    Assert-Condition ($ns903Row.status -in @('planned','runtime_verified')) "NS903 row has unsupported status: $($ns903Row.status)"

    $coreTeacherAreaIds = @(
        'teacher-shell',
        'question-upload',
        'document-parsing',
        'question-cutting',
        'human-review',
        'question-save',
        'ai-tagging',
        'review-queue',
        'question-search',
        'paper-assembly',
        'paper-export',
        'score-import',
        'analysis-report'
    )
    $coreTeacherRows = @($dashboardRows | Where-Object { $coreTeacherAreaIds -contains [string]$_.area_id })
    Assert-Condition ($coreTeacherRows.Count -eq $coreTeacherAreaIds.Count) 'NS903 dashboard is missing a core teacher area'
    Assert-Condition ((@($coreTeacherRows | Where-Object { [string]$_.current_state -eq 'teacher_validated' }).Count) -eq $coreTeacherAreaIds.Count) 'NS903 requires all core teacher areas to be teacher_validated'

    $releaseReadyRows = @($dashboardRows | Where-Object { [string]$_.current_state -eq 'release_ready' })
    $p001Rows = @($dashboardRows | Where-Object { [string]$_.next_task -eq 'P001' })
    $nonSiteValidatedRows = @($planRows | Where-Object { [string]$_.status -eq 'non_site_validated' })
    Assert-Condition ($releaseReadyRows.Count -eq 0) 'NS903 must not mark any area release_ready'
    Assert-Condition ($p001Rows.Count -ge 1) 'NS903 must keep at least one dashboard row blocked by P001'
    Assert-Condition ($nonSiteValidatedRows.Count -eq 0) 'NS903 must not claim non_site_validated without authorized/onsite evidence'

    $livePilot = Get-RequiredRow $dashboardRows 'live-pilot' 'area_id'
    $deploymentInstall = Get-RequiredRow $dashboardRows 'deployment-install' 'area_id'
    $realFull = Get-RequiredRow $dashboardRows 'real-guangzhou-2015-2025' 'area_id'
    Assert-Condition ($livePilot.current_state -eq 'contract_done') 'NS903 live-pilot row must remain contract_done'
    Assert-Condition ($livePilot.next_task -eq 'P001') 'NS903 live-pilot row must point to P001'
    Assert-Condition ($deploymentInstall.current_state -eq 'contract_done') 'NS903 deployment-install row must remain contract_done'
    Assert-Condition ($deploymentInstall.next_task -eq 'P001') 'NS903 deployment-install row must point to P001'
    Assert-Condition ($realFull.current_state -eq 'contract_done') 'NS903 real full closure row must remain contract_done'
    Assert-Condition ($realFull.next_task -eq 'REAL005') 'NS903 real full closure row must point to REAL005'

    $runtimeVerifiedRows = @($planRows | Where-Object { [string]$_.status -eq 'runtime_verified' })
    $statusCounts = [ordered]@{}
    foreach ($group in ($planRows | Group-Object status | Sort-Object Name)) {
        $statusCounts[$group.Name] = $group.Count
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS903'
        checkedAt = (Get-Date).ToString('s')
        mode = 'completion_dashboard_refresh'
        productionEligible = $false
        nonSiteValidated = $false
        externalAiCalls = 0
        realStudentDataUsed = $false
        writesProductionHistory = $false
        activeAssetMutation = $false
        dependency = [ordered]@{
            s001 = $S001JsonReportPath
            ns901 = 'docs/evidence/20260530-ns901-non-site-scenario-pack.json'
            ns902 = 'docs/evidence/20260528-non-site-e2e-rehearsal-report.json'
            ns906 = 'docs/evidence/20260528-ns906-visual-surrogate-review-report.json'
            p001 = 'docs/evidence/20260530-p001-live-pilot-readiness-preflight-report.json'
            real005 = $REAL005ReportPath
        }
        dashboard = [ordered]@{
            areaCount = [int]$s001.areaCount
            stateCounts = $s001.stateCounts
            riskCounts = $s001.riskCounts
            teacherVisibleValidatedOrReleaseReadyCount = [int]$s001.teacherVisibleValidatedOrReleaseReadyCount
            releaseReadyCount = $releaseReadyRows.Count
            p001BlockedAreaCount = $p001Rows.Count
            coreTeacherValidatedCount = $coreTeacherRows.Count
            livePilotState = [string]$livePilot.current_state
            deploymentInstallState = [string]$deploymentInstall.current_state
            realFullClosureState = [string]$realFull.current_state
        }
        nonSitePlan = [ordered]@{
            rowCount = $planRows.Count
            statusCounts = $statusCounts
            runtimeVerifiedCount = $runtimeVerifiedRows.Count
            nonSiteValidatedCount = $nonSiteValidatedRows.Count
            nextAfterNs903 = 'NS904'
        }
        blockers = [ordered]@{
            p001CanClose = [bool]$p001.p001CanClose
            p001Blockers = @($p001.blockers)
            real005ClosureStatus = [string]$real005.closureStatus
            real005FullClosureAllowed = [bool]$real005.fullClosureAllowed
            real005NextSliceStatus = [string]$real005.sliceCoverage.REAL005A.status
            ns901NonSiteValidated = [bool]$ns901.nonSiteValidated
        }
        acceptance = [ordered]@{
            s001DashboardPassed = $true
            ns901RuntimeEvidencePassed = $true
            ns902E2eEvidencePassed = $true
            ns906VisualSurrogateEvidencePassed = $true
            coreTeacherAreasTeacherValidated = $true
            releaseReadyNotClaimed = $true
            nonSiteValidatedNotClaimed = $true
            p001LiveBoundaryBlocked = $true
            real005NotClosed = $true
            noExternalAiCall = $true
            noRealStudentData = $true
            noProductionHistoryWrite = $true
            noActiveWrite = $true
        }
        verification = [ordered]@{
            build = 'outer gate: dotnet build apps/api/K12QuestionGraph.Api.csproj before run-gates'
            test = 'S001 completion-state dashboard refresh plus NS901/NS902/NS906 runtime evidence checks'
            contractInvariant = 'NS903 only refreshes dashboard/status evidence; it requires runtime/E2E prerequisites and keeps non_site_validated, release_ready, P001, and REAL005 closure blocked'
            hotspot = 'gate_na: completion dashboard is evidence-only and does not include isolated-machine teacher observation, printer/network/domain checks, or live operator signoff'
        }
        boundary = 'NS903 refreshes the completion dashboard using runtime/E2E evidence and keeps live deployment and real full-closure claims blocked. It does not claim non_site_validated, release_ready, P001 closure, or REAL005 closure.'
        rollback = "git restore tasks/completion-state-dashboard.csv tasks/non-site-implementation-plan.csv tools/run-gates.ps1 tools/README.md; git clean -f -- tools/run-ns903-completion-dashboard.ps1 $ReportPath"
        next = 'NS904 should assemble the P001 readiness evidence pack while keeping isolated-machine and onsite blockers explicit.'
    }

    $jsonText = $report | ConvertTo-Json -Depth 12
    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $jsonText | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $jsonText
}
finally {
    Pop-Location
}

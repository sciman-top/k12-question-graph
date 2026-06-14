param(
    [string] $ReportPath = '',
    [string] $MarkdownReportPath = '',
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $LiveCloseoutPlanPath = 'tasks/live-pilot-closeout-plan.csv',
    [string] $LiveCloseoutGuardPath = '',
    [string] $Real005ReportPath = '',
    [string] $StatusSyncReportPath = '',
    [string] $RepoPreflightCiSummaryPath = '',
    [string] $P001ReportPath = '',
    [string] $P002ReportPath = '',
    [string] $P003ReportPath = '',
    [string] $P004ReportPath = '',
    [string] $P005ReportPath = '',
    [string] $P006ReportPath = '',
    [string] $PqrPreflightPackReportPath = 'tmp/gate-group-pqr/pqr-preflight-pack-report.json',
    [string] $PqrOrchestrationReportPath = 'tmp/gate-group-pqr/pqr-orchestration-consistency-report.json',
    [string] $P0LivePreflightRefreshReportPath = 'tmp/live-pilot-template-check/p0-live-preflight-refresh-report.json',
    [ValidateSet('not_run', 'pass', 'fail', 'inconclusive')]
    [string] $FullGateAttemptStatus = 'not_run',
    [string] $FullGateAttemptNote = '',
    [string] $FullGateObservedOutputRoot = 'tmp/full-gate-pqr'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runDate = Get-Date -Format 'yyyyMMdd'

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = ('docs/evidence/{0}-live-pilot-closeout-repo-side-audit.json' -f $runDate)
}

if ([string]::IsNullOrWhiteSpace($MarkdownReportPath)) {
    $MarkdownReportPath = ('docs/evidence/{0}-live-pilot-closeout-repo-side-audit.md' -f $runDate)
}

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Resolve-InRepoPath([string] $RelativePath) {
    return Join-Path $repoRoot ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
}

function Get-RelativeRepoPath([string] $FullPath) {
    return [System.IO.Path]::GetRelativePath($repoRoot, $FullPath).Replace('\', '/')
}

function Resolve-LatestEvidencePath([string] $Filter, [string] $PreferredPath) {
    if (-not [string]::IsNullOrWhiteSpace($PreferredPath)) {
        Assert-Condition (Test-Path -LiteralPath (Resolve-InRepoPath $PreferredPath)) "missing preferred evidence path: $PreferredPath"
        return $PreferredPath
    }

    $evidenceRoot = Resolve-InRepoPath 'docs/evidence'
    Assert-Condition (Test-Path -LiteralPath $evidenceRoot) 'missing docs/evidence directory'
    $latest = @(
        Get-ChildItem -LiteralPath $evidenceRoot -Filter $Filter -File |
            Sort-Object Name -Descending |
            Select-Object -First 1
    )
    Assert-Condition ($latest.Count -eq 1) "missing evidence matching filter: $Filter"
    return Get-RelativeRepoPath $latest[0].FullName
}

function Read-Json([string] $RelativePath) {
    $fullPath = Resolve-InRepoPath $RelativePath
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing JSON report: $RelativePath"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Read-Text([string] $RelativePath) {
    $fullPath = Resolve-InRepoPath $RelativePath
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing text report: $RelativePath"
    return Get-Content -LiteralPath $fullPath -Raw
}

function Get-RequiredRow([object[]] $Rows, [string] $Id, [string] $Column = 'id') {
    $matches = @($Rows | Where-Object { [string] $_.$Column -eq $Id })
    Assert-Condition ($matches.Count -eq 1) "expected exactly one $Column=$Id row"
    return $matches[0]
}

function Get-ObjectPropertyValue([object] $Object, [string] $Name) {
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Write-ContentIfChanged([string] $Path, [string] $Content) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    if (Test-Path -LiteralPath $Path) {
        $existing = Get-Content -LiteralPath $Path -Raw
        if ($existing -eq $Content) { return }
    }
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

function Get-ObservedFiles([string] $RelativeRoot) {
    $root = Resolve-InRepoPath $RelativeRoot
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        return @()
    }

    return @(
        Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue |
            Sort-Object Name |
            ForEach-Object {
                [ordered]@{
                    path = Get-RelativeRepoPath $_.FullName
                    length = $_.Length
                    lastWriteTime = $_.LastWriteTime.ToString('s')
                }
            }
    )
}

Push-Location $repoRoot
try {
    if ($FullGateAttemptStatus -eq 'inconclusive') {
        Assert-Condition (-not [string]::IsNullOrWhiteSpace($FullGateAttemptNote)) 'inconclusive full gate attempt requires FullGateAttemptNote'
    }

    $LiveCloseoutGuardPath = Resolve-LatestEvidencePath '*-live-pilot-closeout-plan-guard.json' $LiveCloseoutGuardPath
    $Real005ReportPath = Resolve-LatestEvidencePath '*-real005-guangzhou-2015-2025-closure-standard-report.json' $Real005ReportPath
    $StatusSyncReportPath = Resolve-LatestEvidencePath '*-ns905-status-sync.md' $StatusSyncReportPath
    $RepoPreflightCiSummaryPath = Resolve-LatestEvidencePath '*-repo-preflight-ci-summary.json' $RepoPreflightCiSummaryPath
    $P001ReportPath = Resolve-LatestEvidencePath '*-p001-live-pilot-readiness-preflight-report.json' $P001ReportPath
    $P002ReportPath = Resolve-LatestEvidencePath '*-p002-teacher-proxy-pilot-admission-report.json' $P002ReportPath
    $P003ReportPath = Resolve-LatestEvidencePath '*-p003-onsite-pilot-admission-report.json' $P003ReportPath
    $P004ReportPath = Resolve-LatestEvidencePath '*-p004-onsite-pilot-round1-report.json' $P004ReportPath
    $P005ReportPath = Resolve-LatestEvidencePath '*-p005-pilot-feedback-backlog-admission-report.json' $P005ReportPath
    $P006ReportPath = Resolve-LatestEvidencePath '*-p006-release-decision-admission-report.json' $P006ReportPath

    $backlogRows = @(Import-Csv -LiteralPath (Resolve-InRepoPath $BacklogPath) -Encoding UTF8)
    $closeoutRows = @(Import-Csv -LiteralPath (Resolve-InRepoPath $LiveCloseoutPlanPath) -Encoding UTF8)
    Assert-Condition ($backlogRows.Count -gt 0) 'backlog must not be empty'
    Assert-Condition ($closeoutRows.Count -eq 26) "live closeout plan row count drift: expected 26 actual $($closeoutRows.Count)"

    $requiredTodoIds = @('P001','P002','P003','P004','P005','P006','Q001','Q002','Q003','Q004','Q005','R001','R002','R003','R004','R005','R006','R007')
    $backlogStatuses = [ordered]@{}
    foreach ($id in $requiredTodoIds) {
        $row = Get-RequiredRow $backlogRows $id
        $backlogStatuses[$id] = [string] $row.status
        Assert-Condition ([string] $row.status -eq '待办') "$id must remain todo before live release decision"
    }
    $real005Backlog = Get-RequiredRow $backlogRows 'REAL005'
    Assert-Condition ([string] $real005Backlog.status -eq '已完成') 'REAL005 criteria task must remain completed as the guard-definition task'

    $closeoutStatusCounts = [ordered]@{}
    foreach ($group in ($closeoutRows | Group-Object status | Sort-Object Name)) {
        $closeoutStatusCounts[$group.Name] = $group.Count
    }
    $real005APlanRow = Get-RequiredRow $closeoutRows 'REAL005A'
    Assert-Condition ($closeoutStatusCounts.Contains('待办') -and [int] $closeoutStatusCounts['待办'] -eq 25) 'live closeout plan must keep 25 rows todo after REAL005A repo-side completion'
    Assert-Condition ($closeoutStatusCounts.Contains('已完成') -and [int] $closeoutStatusCounts['已完成'] -eq 1) 'live closeout plan must contain exactly one completed repo-side slice before onsite closure'
    Assert-Condition ([string] $real005APlanRow.status -eq '已完成') 'REAL005A must be the only completed live closeout plan row'

    $nextOpenByParent = [ordered]@{}
    foreach ($parent in @('REAL005','P001','P003','P005','P006')) {
        $nextOpen = @($closeoutRows | Where-Object { [string] $_.parent_id -eq $parent -and [string] $_.status -ne '已完成' } | Select-Object -First 1)
        $nextOpenByParent[$parent] = if ($nextOpen.Count -gt 0) { [string] $nextOpen[0].id } else { 'none' }
    }
    Assert-Condition ($nextOpenByParent.REAL005 -eq 'REAL005B') 'REAL005 next open slice must be REAL005B after REAL005A repo-side completion'
    Assert-Condition ($nextOpenByParent.P001 -eq 'P001A') 'P001 next open slice must remain P001A'
    Assert-Condition ($nextOpenByParent.P003 -eq 'P003A') 'P003 next open slice must remain P003A'
    Assert-Condition ($nextOpenByParent.P005 -eq 'P005A') 'P005 next open slice must remain P005A'
    Assert-Condition ($nextOpenByParent.P006 -eq 'P006A') 'P006 next open slice must remain P006A'

    $liveGuard = Read-Json $LiveCloseoutGuardPath
    $real005 = Read-Json $Real005ReportPath
    $repoPreflight = Read-Json $RepoPreflightCiSummaryPath
    $p001 = Read-Json $P001ReportPath
    $p002 = Read-Json $P002ReportPath
    $p003 = Read-Json $P003ReportPath
    $p004 = Read-Json $P004ReportPath
    $p005 = Read-Json $P005ReportPath
    $p006 = Read-Json $P006ReportPath
    $statusSyncText = Read-Text $StatusSyncReportPath

    Assert-Condition ([string] $liveGuard.status -eq 'pass') 'live closeout guard must pass'
    Assert-Condition ([string] $liveGuard.real005ClosureStatus -eq 'not_closed') 'live closeout guard must keep REAL005 not_closed'
    Assert-Condition (-not [bool] $liveGuard.fullClosureAllowed) 'live closeout guard must keep fullClosureAllowed=false'
    Assert-Condition ([string] $real005.status -eq 'pass') 'REAL005 closure standard report must pass as a guard definition'
    Assert-Condition ([string] $real005.closureStatus -eq 'not_closed') 'REAL005 closure status must remain not_closed'
    Assert-Condition (-not [bool] $real005.fullClosureAllowed) 'REAL005 fullClosureAllowed must remain false'
    Assert-Condition ($null -ne $real005.sliceCoverage.REAL005A) 'REAL005 report must expose sliceCoverage.REAL005A'
    $real005ASliceStatus = [string] $real005.sliceCoverage.REAL005A.status
    Assert-Condition ($real005ASliceStatus -eq 'pass') 'REAL005A must pass before this repo-side audit accepts the completed plan row'
    Assert-Condition (@($real005.sliceCoverage.REAL005A.blockers).Count -eq 0) 'REAL005A blockers must be empty after RG001/RG002 pass'

    Assert-Condition ([string] $repoPreflight.status -eq 'pass') 'repo preflight CI summary must pass'
    Assert-Condition ([string] $repoPreflight.mode -eq 'Ci') 'repo preflight summary must be Mode=Ci for this audit'
    Assert-Condition (-not [bool] $repoPreflight.fullGateIncluded) 'repo preflight CI must not pretend to include the full local gate'
    foreach ($step in @($repoPreflight.steps)) {
        Assert-Condition ([string] $step.status -eq 'pass') "repo preflight step did not pass: $($step.name)"
    }

    Assert-Condition ([string] $p001.status -eq 'pass') 'P001 preflight report must pass'
    Assert-Condition ([string] $p001.p001Status -eq '待办') 'P001 must remain todo'
    Assert-Condition ([bool] $p001.readyForIsolatedMachineRun) 'P001 must be ready for isolated-machine run'
    Assert-Condition (-not [bool] $p001.p001CanClose) 'P001 cannot close without isolated-machine evidence'

    foreach ($report in @($p002,$p003,$p004,$p005,$p006)) {
        Assert-Condition ([string] $report.status -eq 'pass') "$($report.taskId) preflight report must pass"
        Assert-Condition (-not [bool] $report.closeTaskAllowed) "$($report.taskId) must not be closeTaskAllowed"
    }

    Assert-Condition ([string] $p003.p003Status -eq '待办') 'P003 must remain todo'
    Assert-Condition ([string] $p004.p004Status -eq '待办') 'P004 must remain todo'
    Assert-Condition ([string] $p005.p005Status -eq '待办') 'P005 must remain todo'
    Assert-Condition ([string] $p006.p006Status -eq '待办') 'P006 must remain todo'

    foreach ($template in @(
        @{ path = 'docs/templates/p003-onsite-pilot-admission-card-template.json'; schema = 'p003-onsite-pilot-admission-card.v1' },
        @{ path = 'docs/templates/p004-onsite-pilot-round1-evidence-template.json'; schema = 'p004-onsite-pilot-round1-evidence.v1' }
    )) {
        $templateJson = Read-Json $template.path
        Assert-Condition ([string] $templateJson.schemaVersion -eq $template.schema) "template schema mismatch: $($template.path)"
    }
    foreach ($scriptPath in @(
        'tools/run-p003-onsite-pilot-admission-card-import.ps1',
        'tools/run-p004-onsite-pilot-round1-evidence-import.ps1'
    )) {
        Assert-Condition (Test-Path -LiteralPath (Resolve-InRepoPath $scriptPath)) "missing import validator script: $scriptPath"
    }

    $pqrPack = Read-Json $PqrPreflightPackReportPath
    Assert-Condition ([string] $pqrPack.status -eq 'pass') 'PQR preflight pack report must pass'
    Assert-Condition ([int] $pqrPack.targetCount -eq 18) 'PQR preflight pack target count must remain 18'
    Assert-Condition ([int] $pqrPack.todoCount -eq 18) 'PQR preflight pack must keep all P/Q/R targets todo'
    Assert-Condition ([string] $pqrPack.templateAnchors.p003AdmissionCard -eq 'docs/templates/p003-onsite-pilot-admission-card-template.json') 'PQR pack must anchor P003 structured template'
    Assert-Condition ([string] $pqrPack.templateAnchors.p004TeacherPilotEvidence -eq 'docs/templates/p004-onsite-pilot-round1-evidence-template.json') 'PQR pack must anchor P004 structured template'

    $pqrOrchestration = Read-Json $PqrOrchestrationReportPath
    Assert-Condition ([string] $pqrOrchestration.status -eq 'pass') 'PQR orchestration consistency report must pass'

    $p0Refresh = Read-Json $P0LivePreflightRefreshReportPath
    Assert-Condition ([string] $p0Refresh.status -eq 'pass') 'P0-live preflight refresh must pass'
    Assert-Condition ([int] $p0Refresh.passCount -eq [int] $p0Refresh.total) 'P0-live preflight refresh must have all child contracts pass'
    Assert-Condition ([string] $p0Refresh.boundary -match 'preflight_only') 'P0-live preflight refresh must stay preflight-only'

    foreach ($keyword in @(
        'release_ready_count: 0',
        'backlog_p001_p006_remain_todo: true',
        'dashboard_release_ready_not_claimed: true',
        'real005_not_closed: true'
    )) {
        Assert-Condition ($statusSyncText.Contains($keyword)) "NS905 status sync report missing keyword: $keyword"
    }

    $observedFullGateOutputs = Get-ObservedFiles $FullGateObservedOutputRoot
    $remainingBlockers = [ordered]@{
        REAL005B = @($real005.sliceCoverage.REAL005B.blockers)
        P001 = @($p001.blockers)
        P002 = @($p002.blockers)
        P003 = @($p003.blockers)
        P004 = @($p004.blockers)
        P005 = @($p005.blockers)
        P006 = @($p006.blockers)
    }

    $checkedAt = (Get-Date).ToString('s')
    $summary = [ordered]@{
        status = 'pass'
        taskId = 'LIVE_PILOT_CLOSEOUT_REPO_SIDE_AUDIT'
        checkedAt = $checkedAt
        reportPath = $ReportPath
        markdownReportPath = $MarkdownReportPath
        repoSideValidated = [ordered]@{
            structuredP003Template = $true
            structuredP004Template = $true
            p003ImportValidator = $true
            p004ImportValidator = $true
            p0LivePreflightRefresh = 'pass'
            pqrPreflightPack = 'pass'
            pqrOrchestration = 'pass'
            repoPreflightCi = 'pass'
        }
        truthBoundary = [ordered]@{
            real005ClosureStatus = [string] $real005.closureStatus
            fullClosureAllowed = [bool] $real005.fullClosureAllowed
            p001CanClose = [bool] $p001.p001CanClose
            readyForIsolatedMachineRun = [bool] $p001.readyForIsolatedMachineRun
            p001ToP006BacklogStatuses = [ordered]@{
                P001 = $backlogStatuses.P001
                P002 = $backlogStatuses.P002
                P003 = $backlogStatuses.P003
                P004 = $backlogStatuses.P004
                P005 = $backlogStatuses.P005
                P006 = $backlogStatuses.P006
            }
            qFormalTasksRemainTodo = @('Q001','Q002','Q003','Q004','Q005')
            rFormalTasksRemainTodo = @('R001','R002','R003','R004','R005','R006','R007')
            liveCloseoutPlanStatusCounts = $closeoutStatusCounts
            nextOpenByParent = $nextOpenByParent
            releaseReadyClaimed = $false
        }
        fullGate = [ordered]@{
            attemptStatus = $FullGateAttemptStatus
            note = $FullGateAttemptNote
            observedOutputRoot = $FullGateObservedOutputRoot
            observedOutputs = $observedFullGateOutputs
        }
        evidenceInputs = [ordered]@{
            liveCloseoutGuard = $LiveCloseoutGuardPath
            real005Report = $Real005ReportPath
            statusSyncReport = $StatusSyncReportPath
            repoPreflightCiSummary = $RepoPreflightCiSummaryPath
            p0LivePreflightRefresh = $P0LivePreflightRefreshReportPath
            pqrPreflightPack = $PqrPreflightPackReportPath
            pqrOrchestration = $PqrOrchestrationReportPath
            p001 = $P001ReportPath
            p002 = $P002ReportPath
            p003 = $P003ReportPath
            p004 = $P004ReportPath
            p005 = $P005ReportPath
            p006 = $P006ReportPath
        }
        remainingBlockers = $remainingBlockers
        boundary = 'repo-side audit only; does not execute isolated-machine, onsite teacher pilot, operator signoff, release tag creation, or Q/R formal tasks'
        rollback = "git clean -f -- tools/run-live-pilot-closeout-repo-side-audit.ps1 $ReportPath $MarkdownReportPath; git restore tools/README.md"
    }

    $reportJson = $summary | ConvertTo-Json -Depth 12
    Write-ContentIfChanged -Path (Resolve-InRepoPath $ReportPath) -Content $reportJson

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Live Pilot Closeout Repo-Side Audit')
    $lines.Add('')
    $lines.Add("- status: pass")
    $lines.Add("- checked_at: $checkedAt")
    $lines.Add("- repo_preflight_ci: pass")
    $lines.Add("- p0_live_preflight_refresh: pass")
    $lines.Add("- pqr_preflight_pack: pass")
    $lines.Add("- pqr_orchestration: pass")
    $lines.Add("- full_gate_attempt: $FullGateAttemptStatus")
    if (-not [string]::IsNullOrWhiteSpace($FullGateAttemptNote)) {
        $lines.Add("- full_gate_note: $FullGateAttemptNote")
    }
    $lines.Add('')
    $lines.Add('## Repo-Side Validated')
    $lines.Add('- P003 structured admission-card template and import validator are present and passing.')
    $lines.Add('- P004 structured teacher-pilot evidence template and import validator are present and passing.')
    $lines.Add('- P001-P006 preflight reports passed as preflight-only contracts.')
    $lines.Add('- PQR preflight pack and orchestration reports passed with all 18 P/Q/R targets still todo.')
    $lines.Add('- CI repo preflight passed without claiming to replace the full local gate.')
    $lines.Add('')
    $lines.Add('## Truth Boundary')
    $lines.Add("- REAL005 closure_status: $($real005.closureStatus)")
    $lines.Add("- full_closure_allowed: $([bool] $real005.fullClosureAllowed)")
    $lines.Add("- P001 ready_for_isolated_machine_run: $([bool] $p001.readyForIsolatedMachineRun)")
    $lines.Add("- P001 can_close: $([bool] $p001.p001CanClose)")
    foreach ($id in @('P001','P002','P003','P004','P005','P006')) {
        $lines.Add("- ${id}: $($backlogStatuses[$id])")
    }
    $lines.Add('- Q001-Q005: 待办; preflight evidence only, no formal Q execution.')
    $lines.Add('- R001-R007: 待办; preflight evidence only, no formal R execution.')
    $lines.Add('- release_ready_claimed: false')
    $lines.Add('')
    $lines.Add('## Next Open Slices')
    foreach ($entry in $nextOpenByParent.GetEnumerator()) {
        $lines.Add("- $($entry.Key): $($entry.Value)")
    }
    $lines.Add('')
    $lines.Add('## Remaining Blockers')
    foreach ($entry in $remainingBlockers.GetEnumerator()) {
        $items = @($entry.Value)
        $value = if ($items.Count -eq 0) { 'none' } else { $items -join ' | ' }
        $lines.Add("- $($entry.Key): $value")
    }
    $lines.Add('')
    $lines.Add('## Evidence Inputs')
    foreach ($entry in $summary.evidenceInputs.GetEnumerator()) {
        $lines.Add(("- {0}: ``{1}``" -f $entry.Key, $entry.Value))
    }
    $lines.Add('')
    $lines.Add('## Boundary')
    $lines.Add('This audit is repo-side only. It does not execute isolated-machine work, onsite teacher observation, operator signoff, release tag creation, or Q/R formal tasks. A timed-out or otherwise untraceable full-gate attempt must remain inconclusive unless a final exit code and terminal report are available.')
    $lines.Add('')
    $lines.Add('## Rollback')
    $lines.Add("git clean -f -- tools/run-live-pilot-closeout-repo-side-audit.ps1 $ReportPath $MarkdownReportPath; git restore tools/README.md")

    Write-ContentIfChanged -Path (Resolve-InRepoPath $MarkdownReportPath) -Content ($lines -join "`r`n")
    $reportJson
}
finally {
    Pop-Location
}

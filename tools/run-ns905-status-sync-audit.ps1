param(
    [string] $ReportPath = 'docs/evidence/20260530-ns905-status-sync.md',
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $DashboardPath = 'tasks/completion-state-dashboard.csv',
    [string] $NonSitePlanPath = 'tasks/non-site-implementation-plan.csv',
    [string] $LiveCloseoutPlanPath = 'tasks/live-pilot-closeout-plan.csv',
    [string] $NS904ReportPath = 'docs/evidence/20260530-ns904-p001-readiness.json',
    [string] $NS903ReportPath = 'docs/evidence/20260530-ns903-completion-dashboard.json',
    [string] $P001ReportPath = 'docs/evidence/20260530-p001-live-pilot-readiness-preflight-report.json',
    [string] $REAL005ReportPath = 'docs/evidence/20260512-real005-guangzhou-2015-2025-closure-standard-report.json'
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

function Get-RequiredRow([object[]] $Rows, [string] $Id, [string] $Column = 'id') {
    $matches = @($Rows | Where-Object { [string]$_.$Column -eq $Id })
    Assert-Condition ($matches.Count -eq 1) "expected exactly one $Column=$Id row"
    return $matches[0]
}

function Assert-ContainsAll([string[]] $Actual, [string[]] $Required, [string] $Label) {
    foreach ($item in $Required) {
        Assert-Condition ($Actual -contains $item) "$Label missing item: $item"
    }
}

Push-Location $repoRoot
try {
    $backlogFullPath = Resolve-InRepoPath $BacklogPath
    $dashboardFullPath = Resolve-InRepoPath $DashboardPath
    $planFullPath = Resolve-InRepoPath $NonSitePlanPath
    $closeoutPlanFullPath = Resolve-InRepoPath $LiveCloseoutPlanPath
    Assert-Condition (Test-Path -LiteralPath $backlogFullPath) "missing backlog: $BacklogPath"
    Assert-Condition (Test-Path -LiteralPath $dashboardFullPath) "missing completion dashboard: $DashboardPath"
    Assert-Condition (Test-Path -LiteralPath $planFullPath) "missing non-site plan: $NonSitePlanPath"
    Assert-Condition (Test-Path -LiteralPath $closeoutPlanFullPath) "missing live closeout plan: $LiveCloseoutPlanPath"

    $backlogRows = @(Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8)
    $dashboardRows = @(Import-Csv -LiteralPath $dashboardFullPath -Encoding UTF8)
    $planRows = @(Import-Csv -LiteralPath $planFullPath -Encoding UTF8)
    $closeoutRows = @(Import-Csv -LiteralPath $closeoutPlanFullPath -Encoding UTF8)
    Assert-Condition ($backlogRows.Count -gt 0) 'backlog must not be empty'
    Assert-Condition ($dashboardRows.Count -gt 0) 'completion dashboard must not be empty'
    Assert-Condition ($planRows.Count -gt 0) 'non-site plan must not be empty'
    Assert-Condition ($closeoutRows.Count -eq 26) "live closeout plan row count drift: expected 26 actual $($closeoutRows.Count)"

    $ns904 = Read-Json $NS904ReportPath
    $ns903 = Read-Json $NS903ReportPath
    $p001 = Read-Json $P001ReportPath
    $real005 = Read-Json $REAL005ReportPath

    Assert-Condition ($ns904.status -eq 'pass') 'NS905 dependency NS904 did not pass'
    Assert-Condition ($ns903.status -eq 'pass') 'NS905 dependency NS903 did not pass'
    Assert-Condition ($p001.status -eq 'pass') 'NS905 dependency P001 preflight did not pass'
    Assert-Condition ($real005.status -eq 'pass') 'NS905 dependency REAL005 did not pass'

    Assert-Condition (-not [bool]$ns904.releaseReady) 'NS905 must not inherit releaseReady=true from NS904'
    Assert-Condition (-not [bool]$ns904.nonSiteValidated) 'NS905 must not inherit nonSiteValidated=true from NS904'
    Assert-Condition (-not [bool]$ns904.p001CanClose) 'NS905 must keep p001CanClose=false'
    Assert-Condition ($ns904.p001Status -eq '待办') 'NS905 must keep P001 status as todo'
    Assert-Condition ($ns904.readinessPack.real005ClosureStatus -eq 'not_closed') 'NS905 must keep REAL005 not_closed through NS904'
    Assert-Condition (-not [bool]$real005.fullClosureAllowed) 'NS905 must not allow REAL005 full closure'

    $p001Backlog = Get-RequiredRow $backlogRows 'P001'
    $p002Backlog = Get-RequiredRow $backlogRows 'P002'
    $p003Backlog = Get-RequiredRow $backlogRows 'P003'
    $p004Backlog = Get-RequiredRow $backlogRows 'P004'
    $p005Backlog = Get-RequiredRow $backlogRows 'P005'
    $p006Backlog = Get-RequiredRow $backlogRows 'P006'
    $real005Backlog = Get-RequiredRow $backlogRows 'REAL005'

    $closeoutParentCounts = [ordered]@{}
    foreach ($group in ($closeoutRows | Group-Object parent_id | Sort-Object Name)) {
        $closeoutParentCounts[$group.Name] = $group.Count
    }
    Assert-Condition ($closeoutParentCounts['REAL005'] -eq 4) 'live closeout REAL005 slice count must remain 4'
    Assert-Condition ($closeoutParentCounts['P001'] -eq 8) 'live closeout P001 slice count must remain 8'
    Assert-Condition ($closeoutParentCounts['P003'] -eq 5) 'live closeout P003 slice count must remain 5'
    Assert-Condition ($closeoutParentCounts['P005'] -eq 4) 'live closeout P005 slice count must remain 4'
    Assert-Condition ($closeoutParentCounts['P006'] -eq 5) 'live closeout P006 slice count must remain 5'

    $closeoutNextOpen = [ordered]@{}
    foreach ($parent in @('REAL005','P001','P003','P005','P006')) {
        $nextOpen = @($closeoutRows | Where-Object { [string] $_.parent_id -eq $parent -and [string] $_.status -ne '已完成' } | Select-Object -First 1)
        $closeoutNextOpen[$parent] = if ($nextOpen.Count -gt 0) { [string] $nextOpen[0].id } else { 'none' }
    }

    foreach ($row in @($p001Backlog, $p002Backlog, $p003Backlog, $p004Backlog, $p005Backlog, $p006Backlog)) {
        Assert-Condition ($row.status -eq '待办') "P-live backlog task must remain todo: $($row.id)"
    }
    Assert-Condition ($real005Backlog.status -eq '已完成') 'REAL005 criteria task must remain completed as a guard definition'
    Assert-Condition ($closeoutNextOpen['REAL005'] -eq 'REAL005A') 'next REAL005 closeout slice must start at REAL005A while not_closed'
    Assert-Condition ($closeoutNextOpen['P001'] -eq 'P001A') 'next P001 closeout slice must start at P001A while todo'
    Assert-Condition ($closeoutNextOpen['P003'] -eq 'P003A') 'next P003 closeout slice must start at P003A while todo'
    Assert-Condition ($closeoutNextOpen['P005'] -eq 'P005A') 'next P005 closeout slice must start at P005A while todo'
    Assert-Condition ($closeoutNextOpen['P006'] -eq 'P006A') 'next P006 closeout slice must start at P006A while todo'
    Assert-ContainsAll @($p001Backlog.depends_on -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) @(
        'S012',
        'O004B',
        'O006',
        'O007',
        'O008',
        'REAL012'
    ) 'P001 backlog dependencies'

    $dashboardNextTaskIds = @($dashboardRows | ForEach-Object { [string]$_.next_task } | Sort-Object -Unique)
    $backlogIds = @($backlogRows | ForEach-Object { [string]$_.id })
    foreach ($nextTask in $dashboardNextTaskIds) {
        Assert-Condition ($backlogIds -contains $nextTask) "completion dashboard next_task missing from backlog: $nextTask"
    }

    $releaseReadyRows = @($dashboardRows | Where-Object { [string]$_.current_state -eq 'release_ready' })
    $p001Rows = @($dashboardRows | Where-Object { [string]$_.next_task -eq 'P001' })
    $p001ReleaseRows = @($p001Rows | Where-Object { [string]$_.current_state -eq 'release_ready' })
    Assert-Condition ($releaseReadyRows.Count -eq 0) 'NS905 must not find release_ready rows before P001'
    Assert-Condition ($p001Rows.Count -ge 1) 'NS905 requires explicit P001-blocked dashboard rows'
    Assert-Condition ($p001ReleaseRows.Count -eq 0) 'P001-blocked dashboard rows must not be release_ready'

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
    Assert-Condition ($coreTeacherRows.Count -eq $coreTeacherAreaIds.Count) 'dashboard missing core teacher area rows'
    Assert-Condition ((@($coreTeacherRows | Where-Object { [string]$_.current_state -eq 'teacher_validated' }).Count) -eq $coreTeacherAreaIds.Count) 'core teacher rows must remain teacher_validated'
    Assert-Condition ((@($coreTeacherRows | Where-Object { [string]$_.next_task -eq 'P001' }).Count) -eq $coreTeacherAreaIds.Count) 'core teacher rows must remain blocked by P001'

    $deploymentInstall = Get-RequiredRow $dashboardRows 'deployment-install' 'area_id'
    $livePilot = Get-RequiredRow $dashboardRows 'live-pilot' 'area_id'
    $realFull = Get-RequiredRow $dashboardRows 'real-guangzhou-2015-2025' 'area_id'
    Assert-Condition ($deploymentInstall.current_state -eq 'contract_done' -and $deploymentInstall.next_task -eq 'P001') 'deployment-install dashboard row must remain contract_done -> P001'
    Assert-Condition ($livePilot.current_state -eq 'contract_done' -and $livePilot.next_task -eq 'P001') 'live-pilot dashboard row must remain contract_done -> P001'
    Assert-Condition ($realFull.current_state -eq 'contract_done' -and $realFull.next_task -eq 'REAL005') 'real full closure dashboard row must remain contract_done -> REAL005'

    $planIds = @($planRows | ForEach-Object { [string]$_.id })
    foreach ($requiredId in @('NS903','NS904','NS905','NS1001','NS1005','NS1101')) {
        Assert-Condition ($planIds -contains $requiredId) "non-site plan missing row: $requiredId"
    }

    $ns903Row = Get-RequiredRow $planRows 'NS903'
    $ns904Row = Get-RequiredRow $planRows 'NS904'
    $ns905Row = Get-RequiredRow $planRows 'NS905'
    $ns1001Row = Get-RequiredRow $planRows 'NS1001'
    $ns1005Row = Get-RequiredRow $planRows 'NS1005'

    Assert-Condition ($ns903Row.status -eq 'runtime_verified') 'NS903 must remain runtime_verified'
    Assert-Condition ($ns904Row.status -eq 'runtime_verified') 'NS904 must remain runtime_verified'
    Assert-Condition ($ns905Row.status -in @('planned','runtime_verified')) "NS905 row has unsupported status: $($ns905Row.status)"
    Assert-Condition ($ns905Row.depends_on -eq 'NS904') 'NS905 must depend on NS904'
    Assert-Condition ($ns1001Row.status -eq 'blocked_by_onsite' -and $ns1001Row.depends_on -eq 'NS904') 'NS1001 must remain blocked_by_onsite after NS904'
    Assert-Condition ($ns1005Row.status -eq 'blocked_by_onsite') 'NS1005 release decision must remain blocked_by_onsite'

    $nonSiteValidatedRows = @($planRows | Where-Object { [string]$_.status -eq 'non_site_validated' })
    Assert-Condition ($nonSiteValidatedRows.Count -eq 0) 'NS905 must not find non_site_validated rows without onsite/authorized evidence'
    foreach ($row in @($ns903Row, $ns904Row)) {
        Assert-Condition ($row.evidence -notmatch '<date>') "runtime row must use concrete evidence: $($row.id)"
        Assert-Condition (Test-Path -LiteralPath (Resolve-InRepoPath $row.evidence)) "runtime row evidence missing: $($row.id)"
    }

    $statusCounts = [ordered]@{}
    foreach ($group in ($planRows | Group-Object status | Sort-Object Name)) {
        $statusCounts[$group.Name] = $group.Count
    }
    $dashboardStateCounts = [ordered]@{}
    foreach ($group in ($dashboardRows | Group-Object current_state | Sort-Object Name)) {
        $dashboardStateCounts[$group.Name] = $group.Count
    }
    $dashboardNextTaskCounts = [ordered]@{}
    foreach ($group in ($dashboardRows | Group-Object next_task | Sort-Object Name)) {
        $dashboardNextTaskCounts[$group.Name] = $group.Count
    }
    $backlogPStatuses = [ordered]@{}
    foreach ($row in @($p001Backlog, $p002Backlog, $p003Backlog, $p004Backlog, $p005Backlog, $p006Backlog)) {
        $backlogPStatuses[$row.id] = [string]$row.status
    }

    $firstPlanned = @($planRows | Where-Object { [string]$_.status -eq 'planned' } | Select-Object -First 1)
    $nextPlannedTask = if ($firstPlanned.Count -gt 0) { [string]$firstPlanned[0].id } else { 'none' }

    $lines = New-Object System.Collections.Generic.List[string]
    $checkedAt = (Get-Date).ToString('s')
    $lines.Add('# NS905 status sync audit')
    $lines.Add('')
    $lines.Add("- status: pass")
    $lines.Add("- checked_at: $checkedAt")
    $lines.Add("- task_id: NS905")
    $lines.Add("- mode: csv_status_sync_audit")
    $lines.Add("- backlog_path: ``$BacklogPath``")
    $lines.Add("- dashboard_path: ``$DashboardPath``")
    $lines.Add("- non_site_plan_path: ``$NonSitePlanPath``")
    $lines.Add("- live_closeout_plan_path: ``$LiveCloseoutPlanPath``")
    $lines.Add('')
    $lines.Add('## Backlog P-live Status')
    foreach ($entry in $backlogPStatuses.GetEnumerator()) {
        $lines.Add("- $($entry.Key): $($entry.Value)")
    }
    $lines.Add('')
    $lines.Add('## Completion Dashboard')
    $lines.Add("- area_count: $($dashboardRows.Count)")
    $lines.Add("- release_ready_count: $($releaseReadyRows.Count)")
    $lines.Add("- p001_blocked_area_count: $($p001Rows.Count)")
    $lines.Add("- core_teacher_validated_count: $($coreTeacherRows.Count)")
    foreach ($entry in $dashboardStateCounts.GetEnumerator()) {
        $lines.Add("- state.$($entry.Key): $($entry.Value)")
    }
    foreach ($entry in $dashboardNextTaskCounts.GetEnumerator()) {
        $lines.Add("- next_task.$($entry.Key): $($entry.Value)")
    }
    $lines.Add('')
    $lines.Add('## Non-Site Plan')
    foreach ($entry in $statusCounts.GetEnumerator()) {
        $lines.Add("- status.$($entry.Key): $($entry.Value)")
    }
    $lines.Add("- ns903: $($ns903Row.status) -> $($ns903Row.evidence)")
    $lines.Add("- ns904: $($ns904Row.status) -> $($ns904Row.evidence)")
    $lines.Add("- ns905_current_status: $($ns905Row.status)")
    $lines.Add("- ns1001: $($ns1001Row.status)")
    $lines.Add("- next_planned_task_after_this_sync: $nextPlannedTask")
    $lines.Add('')
    $lines.Add('## Live Closeout Plan')
    $lines.Add("- row_count: $($closeoutRows.Count)")
    foreach ($entry in $closeoutParentCounts.GetEnumerator()) {
        $lines.Add("- parent.$($entry.Key): $($entry.Value)")
    }
    foreach ($entry in $closeoutNextOpen.GetEnumerator()) {
        $lines.Add("- next_open.$($entry.Key): $($entry.Value)")
    }
    $lines.Add('')
    $lines.Add('## Acceptance')
    $lines.Add('- backlog_p001_p006_remain_todo: true')
    $lines.Add('- dashboard_release_ready_not_claimed: true')
    $lines.Add('- dashboard_p001_blockers_explicit: true')
    $lines.Add('- ns_plan_ns904_runtime_verified: true')
    $lines.Add('- ns_plan_non_site_validated_not_claimed: true')
    $lines.Add('- old_status_did_not_override_ns904_evidence: true')
    $lines.Add('- real005_not_closed: true')
    $lines.Add('- live_closeout_plan_keeps_next_open_slices_explicit: true')
    $lines.Add('')
    $lines.Add('## Boundary')
    $lines.Add('NS905 audits status synchronization only. It does not close P001, does not mark release_ready or non_site_validated, and does not replace isolated-machine or onsite pilot evidence.')
    $lines.Add('')
    $lines.Add('## Rollback')
    $lines.Add("git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1 tools/README.md; git clean -f -- tools/run-ns905-status-sync-audit.ps1 $ReportPath")

    $reportFullPath = Resolve-InRepoPath $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $lines | Set-Content -LiteralPath $reportFullPath -Encoding UTF8

    $summary = [ordered]@{
        status = 'pass'
        taskId = 'NS905'
        checkedAt = $checkedAt
        mode = 'csv_status_sync_audit'
        reportPath = $ReportPath
        releaseReadyCount = $releaseReadyRows.Count
        p001BlockedAreaCount = $p001Rows.Count
        nonSiteValidatedCount = $nonSiteValidatedRows.Count
        ns905CurrentStatus = [string]$ns905Row.status
        nextPlannedTask = $nextPlannedTask
        liveCloseoutRowCount = $closeoutRows.Count
        liveCloseoutNextOpen = $closeoutNextOpen
        p001Status = [string]$p001Backlog.status
        p001CanClose = [bool]$p001.p001CanClose
        real005ClosureStatus = [string]$real005.closureStatus
        boundary = 'status sync audit only; no live/onsite closure'
    }
    $summary | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}

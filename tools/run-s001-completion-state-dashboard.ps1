param(
    [string] $DashboardPath = 'tasks/completion-state-dashboard.csv',
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $JsonReportPath = 'docs/evidence/20260506-s001-completion-state-dashboard.json',
    [string] $MarkdownReportPath = 'docs/evidence/20260506-s001-completion-state-dashboard.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$dashboardFullPath = Join-Path $repoRoot $DashboardPath
$backlogFullPath = Join-Path $repoRoot $BacklogPath
$jsonFullPath = Join-Path $repoRoot $JsonReportPath
$markdownFullPath = Join-Path $repoRoot $MarkdownReportPath

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

Assert-True (Test-Path -LiteralPath $dashboardFullPath) "completion dashboard missing: $DashboardPath"
Assert-True (Test-Path -LiteralPath $backlogFullPath) "backlog missing: $BacklogPath"

$rows = @(Import-Csv -LiteralPath $dashboardFullPath -Encoding UTF8)
$backlogRows = @(Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8)
$byId = @{}
foreach ($row in $backlogRows) { $byId[$row.id] = $row }

$requiredColumns = @('area_id','area','user_visible','current_state','usable_today','evidence_basis','blocking_gap','next_task','risk_level')
foreach ($column in $requiredColumns) {
    Assert-True ($rows.Count -gt 0 -and $rows[0].PSObject.Properties.Name -contains $column) "dashboard missing column: $column"
}

$allowedStates = @('contract_done','synthetic_done','db_backed_done','ui_productized','teacher_validated','release_ready')
$allowedRisks = @('low','medium','high')
$requiredAreas = @(
    'teacher-shell','question-upload','document-parsing','question-cutting','human-review','question-save',
    'ai-tagging','review-queue','question-search','paper-assembly','paper-export','score-import','analysis-report','backup-restore','deployment-install','live-pilot'
)

foreach ($areaId in $requiredAreas) {
    Assert-True (($rows | Where-Object area_id -eq $areaId).Count -eq 1) "dashboard missing required area: $areaId"
}

foreach ($row in $rows) {
    Assert-True ($allowedStates -contains $row.current_state) "invalid current_state for $($row.area_id): $($row.current_state)"
    Assert-True ($allowedRisks -contains $row.risk_level) "invalid risk_level for $($row.area_id): $($row.risk_level)"
    Assert-True (-not [string]::IsNullOrWhiteSpace($row.blocking_gap)) "blocking_gap is required for $($row.area_id)"
    Assert-True (-not [string]::IsNullOrWhiteSpace($row.evidence_basis)) "evidence_basis is required for $($row.area_id)"
    Assert-True ($byId.ContainsKey($row.next_task)) "next_task does not exist in backlog for $($row.area_id): $($row.next_task)"
}

$s001 = $byId['S001']
$s002 = $byId['S002']
$s012 = $byId['S012']
$p001 = $byId['P001']
Assert-True ($null -ne $s001) 'S001 missing from backlog'
Assert-True ($null -ne $s002) 'S002 missing from backlog'
Assert-True ($null -ne $s012) 'S012 missing from backlog'
Assert-True ($null -ne $p001) 'P001 missing from backlog'
Assert-True ($s001.status -eq '已完成') 'S001 must be completed after dashboard is installed'
Assert-True (($p001.depends_on -split ';') -contains 'S012') 'P001 must depend on S012'

$teacherReleaseRows = @($rows | Where-Object { $_.user_visible -eq 'true' -and $_.current_state -in @('teacher_validated','release_ready') })
$coreTeacherAreaIds = @(
    'teacher-shell','question-upload','document-parsing','question-cutting','human-review','question-save',
    'ai-tagging','review-queue','question-search','paper-assembly','paper-export','score-import','analysis-report'
)
$coreTeacherRows = @($rows | Where-Object { $coreTeacherAreaIds -contains $_.area_id })
$preflightBlockedRows = @($rows | Where-Object { $_.next_task -eq 'P001' })

if ($s012.status -eq '待办') {
    Assert-True ($s002.status -eq '待办') 'S002 must remain next unfinished productization task before S012 is completed'
    Assert-True ($teacherReleaseRows.Count -eq 0) 'no teacher-visible area may be marked teacher_validated or release_ready before S012'
}
elseif ($s012.status -eq '已完成') {
    Assert-True ($coreTeacherRows.Count -eq $coreTeacherAreaIds.Count) 'core teacher areas are incomplete in completion dashboard'
    Assert-True ((@($coreTeacherRows | Where-Object current_state -eq 'teacher_validated').Count) -eq $coreTeacherAreaIds.Count) 'all core teacher areas must be teacher_validated after S012'
    Assert-True ($preflightBlockedRows.Count -ge 1) 'at least one area must remain blocked by P001 preflight after S012'
}
else {
    throw "S012 status is unsupported for S001 dashboard guard: $($s012.status)"
}

$stateCounts = [ordered]@{}
foreach ($state in $allowedStates) { $stateCounts[$state] = @($rows | Where-Object current_state -eq $state).Count }
$riskCounts = [ordered]@{}
foreach ($risk in $allowedRisks) { $riskCounts[$risk] = @($rows | Where-Object risk_level -eq $risk).Count }
$normalUsableRows = @($rows | Where-Object { $_.usable_today -match '不可|不可正常|不可生产|不可发布' })
$nextTaskCounts = [ordered]@{}
foreach ($group in ($rows | Group-Object next_task | Sort-Object Name)) { $nextTaskCounts[$group.Name] = $group.Count }

$report = [ordered]@{
    status = 'pass'
    task = 'S001'
    checkedAt = (Get-Date).ToString('s')
    dashboardPath = $DashboardPath
    backlogPath = $BacklogPath
    areaCount = $rows.Count
    stateCounts = $stateCounts
    riskCounts = $riskCounts
    notNormallyUsableCount = $normalUsableRows.Count
    teacherVisibleValidatedOrReleaseReadyCount = $teacherReleaseRows.Count
    nextTaskCounts = $nextTaskCounts
    s001Status = $s001.status
    nextProductizationTask = if ($s012.status -eq '待办') { 'S002' } else { 'P001' }
    conclusion = if ($s012.status -eq '待办') {
        '当前项目拥有可验证底座和合同能力 但教师可直接连续使用的 release_ready 板块为 0 必须先执行 S002-S012'
    }
    else {
        'S012 已完成并将核心教师板块推进到 teacher_validated；现场与发布仍由 P001 preflight 阻断'
    }
}

New-Item -ItemType Directory -Path (Split-Path -Parent $jsonFullPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonFullPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# S001 完成态看板证据')
$lines.Add('')
$lines.Add("- status: pass")
$lines.Add("- checked_at: $($report.checkedAt)")
$lines.Add("- area_count: $($report.areaCount)")
$lines.Add("- not_normally_usable_count: $($report.notNormallyUsableCount)")
$lines.Add("- teacher_visible_validated_or_release_ready_count: $($report.teacherVisibleValidatedOrReleaseReadyCount)")
$lines.Add("- next_productization_task: $($report.nextProductizationTask)")
$lines.Add('')
$lines.Add('## State Counts')
foreach ($state in $allowedStates) { $lines.Add("- ${state}: $($stateCounts[$state])") }
$lines.Add('')
$lines.Add('## High Risk Gaps')
foreach ($row in ($rows | Where-Object risk_level -eq 'high')) {
    $lines.Add("- $($row.area_id): $($row.current_state) -> $($row.next_task); $($row.blocking_gap)")
}
$lines.Add('')
$lines.Add('## Conclusion')
$lines.Add($report.conclusion)
$lines | Set-Content -LiteralPath $markdownFullPath -Encoding UTF8

$report | ConvertTo-Json -Depth 8

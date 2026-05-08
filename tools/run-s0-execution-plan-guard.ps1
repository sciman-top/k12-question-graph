param(
    [string] $PlanPath = 'tasks/productization-s0-execution-plan.csv',
    [string] $RoadmapPath = 'tasks/productization-roadmap.csv',
    [string] $DashboardPath = 'tasks/completion-state-dashboard.csv',
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $JsonReportPath = 'docs/evidence/20260506-s0-execution-plan-guard.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$planFullPath = Join-Path $repoRoot $PlanPath
$roadmapFullPath = Join-Path $repoRoot $RoadmapPath
$dashboardFullPath = Join-Path $repoRoot $DashboardPath
$backlogFullPath = Join-Path $repoRoot $BacklogPath
$jsonFullPath = Join-Path $repoRoot $JsonReportPath

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

foreach ($path in @($planFullPath, $roadmapFullPath, $dashboardFullPath, $backlogFullPath)) {
    Assert-True (Test-Path -LiteralPath $path) "required file missing: $path"
}

$rows = @(Import-Csv -LiteralPath $planFullPath -Encoding UTF8)
$roadmapRows = @(Import-Csv -LiteralPath $roadmapFullPath -Encoding UTF8)
$dashboardRows = @(Import-Csv -LiteralPath $dashboardFullPath -Encoding UTF8)
$backlogRows = @(Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8)
$backlogIds = @{}
foreach ($row in $backlogRows) { $backlogIds[$row.id] = $row }
$roadmapIds = @{}
foreach ($row in $roadmapRows) { $roadmapIds[$row.id] = $row }
$planIds = @{}
foreach ($row in $rows) {
    Assert-True (-not $planIds.ContainsKey($row.id)) "duplicate plan id: $($row.id)"
    $planIds[$row.id] = $row
}

$requiredColumns = @('id','parent_id','wave','category','slice','entry_state','exit_state','status','depends_on','acceptance','verification','likely_touched')
foreach ($column in $requiredColumns) {
    Assert-True ($rows.Count -gt 0 -and $rows[0].PSObject.Properties.Name -contains $column) "S0 execution plan missing column: $column"
}

$allowedStates = @('contract_done','synthetic_done','db_backed_done','ui_productized','teacher_validated','release_ready')
foreach ($row in $rows) {
    Assert-True ($roadmapIds.ContainsKey($row.parent_id)) "parent_id missing from productization roadmap: $($row.id) -> $($row.parent_id)"
    Assert-True ($row.parent_id -match '^S00[2-9]$|^S01[0-2]$') "subtask must belong to S002-S012: $($row.id)"
    Assert-True ($allowedStates -contains $row.entry_state) "invalid entry_state for $($row.id): $($row.entry_state)"
    Assert-True ($allowedStates -contains $row.exit_state) "invalid exit_state for $($row.id): $($row.exit_state)"
    Assert-True (-not [string]::IsNullOrWhiteSpace($row.acceptance)) "acceptance required for $($row.id)"
    Assert-True (-not [string]::IsNullOrWhiteSpace($row.verification)) "verification required for $($row.id)"
    Assert-True (-not [string]::IsNullOrWhiteSpace($row.likely_touched)) "likely_touched required for $($row.id)"
}

$automationFirstRows = @()
$automationFirstPath = Join-Path $repoRoot 'tasks\automation-first-contract.csv'
Assert-True (Test-Path -LiteralPath $automationFirstPath) 'automation-first contract missing: tasks/automation-first-contract.csv'
$automationFirstRows = @(Import-Csv -LiteralPath $automationFirstPath -Encoding UTF8)
$automationFirstIds = @{}
foreach ($row in $automationFirstRows) { $automationFirstIds[$row.task_id] = $row }

foreach ($parentId in @('S002','S003','S004','S005','S006','S007','S008','S009','S010','S011','S012')) {
    $children = @($rows | Where-Object parent_id -eq $parentId)
    Assert-True ($children.Count -gt 0) "parent has no executable subtasks: $parentId"
}

foreach ($row in ($rows | Where-Object { $_.status -ne '已完成' })) {
    Assert-True ($automationFirstIds.ContainsKey($row.id)) "open S0 subtask missing automation-first coverage: $($row.id)"
}

foreach ($row in $rows) {
    if ([string]::IsNullOrWhiteSpace($row.depends_on)) { continue }
    foreach ($dependency in ($row.depends_on -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        Assert-True ($planIds.ContainsKey($dependency) -or $roadmapIds.ContainsKey($dependency) -or $backlogIds.ContainsKey($dependency)) "dependency does not exist for $($row.id): $dependency"
    }
}

$lastByParent = @{}
foreach ($parentId in @('S002','S003','S004','S005','S006','S007','S008','S009','S010','S011','S012')) {
    $children = @($rows | Where-Object parent_id -eq $parentId | Sort-Object id)
    $lastByParent[$parentId] = $children[-1].id
}
Assert-True (($planIds['S003A'].depends_on -split ';') -contains $lastByParent['S002']) 'S003 must depend on S002 final subtask'
Assert-True (($planIds['S004A'].depends_on -split ';') -contains $lastByParent['S003']) 'S004 must depend on S003 final subtask'
Assert-True (($planIds['S012C'].verification -match 'full gate') -or ($planIds['S012C'].verification -match 'roadmap guard')) 'S012C must include release gate verification'

$coreTeacherRows = @($dashboardRows | Where-Object { $_.user_visible -eq 'true' -and $_.risk_level -eq 'high' })
Assert-True ($coreTeacherRows.Count -ge 10) 'dashboard should continue exposing high-risk teacher-visible gaps until S012 closes'

$byParent = [ordered]@{}
foreach ($group in ($rows | Group-Object parent_id | Sort-Object Name)) { $byParent[$group.Name] = $group.Count }
$byWave = [ordered]@{}
foreach ($group in ($rows | Group-Object wave | Sort-Object Name)) { $byWave[$group.Name] = $group.Count }

$todoRows = @($rows | Where-Object { $_.status -eq '待办' } | Sort-Object id)
$firstExecutableTask = $null
foreach ($candidate in $todoRows) {
    $deps = @()
    if (-not [string]::IsNullOrWhiteSpace($candidate.depends_on)) {
        $deps = @($candidate.depends_on -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $allDepsSatisfied = $true
    foreach ($dep in $deps) {
        if ($planIds.ContainsKey($dep) -and $planIds[$dep].status -ne '已完成') {
            $allDepsSatisfied = $false
            break
        }
    }

    if ($allDepsSatisfied) {
        $firstExecutableTask = $candidate.id
        break
    }
}

if ($null -eq $firstExecutableTask) {
    $firstExecutableTask = 'none'
}

$report = [ordered]@{
    status = 'pass'
    task = 'S0 execution plan guard'
    checkedAt = (Get-Date).ToString('s')
    planPath = $PlanPath
    rowCount = $rows.Count
    parentCoverage = $byParent
    waveCoverage = $byWave
    firstExecutableTask = $firstExecutableTask
    lastReleaseGateTask = 'S012C'
    automationFirstContract = 'tasks/automation-first-contract.csv'
    conclusion = 'S002-S012 have been decomposed into smaller executable subtasks and remain gated by completion-state evidence before P001'
}

New-Item -ItemType Directory -Path (Split-Path -Parent $jsonFullPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonFullPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8

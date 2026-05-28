param(
    [string] $PlanPath = 'tasks/non-site-implementation-plan.csv',
    [string] $RoadmapPath = 'docs/101_NonSiteCapabilityImplementationRoadmap.md',
    [string] $ReportPath = 'docs/evidence/20260528-ns004-non-site-plan-guard-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$planFullPath = Join-Path $repoRoot $PlanPath
$roadmapFullPath = Join-Path $repoRoot $RoadmapPath
$reportFullPath = Join-Path $repoRoot $ReportPath

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

Assert-True (Test-Path -LiteralPath $planFullPath) "non-site implementation plan missing: $PlanPath"
Assert-True (Test-Path -LiteralPath $roadmapFullPath) "non-site roadmap missing: $RoadmapPath"

$rows = @(Import-Csv -LiteralPath $planFullPath -Encoding UTF8)
Assert-True ($rows.Count -gt 0) 'non-site implementation plan must not be empty'

$requiredColumns = @(
    'id',
    'phase',
    'wave',
    'category',
    'task',
    'priority',
    'status',
    'depends_on',
    'acceptance',
    'verification',
    'likely_touched',
    'evidence',
    'rollback'
)

foreach ($column in $requiredColumns) {
    Assert-True ($rows[0].PSObject.Properties.Name -contains $column) "non-site plan missing column: $column"
}

$allowedStatuses = @(
    'planned',
    'contract_only',
    'repo_landed',
    'runtime_verified',
    'non_site_validated',
    'blocked_by_onsite'
)

$ids = @{}
foreach ($row in $rows) {
    Assert-True (-not [string]::IsNullOrWhiteSpace($row.id)) 'non-site plan row has blank id'
    Assert-True (-not $ids.ContainsKey($row.id)) "duplicate non-site plan id: $($row.id)"
    $ids[$row.id] = $row

    foreach ($column in $requiredColumns) {
        if ($column -eq 'depends_on') { continue }
        Assert-True (-not [string]::IsNullOrWhiteSpace($row.$column)) "non-site row $($row.id) missing $column"
    }

    Assert-True ($row.id -match '^NS\d{3,4}$') "non-site row id must use NS prefix: $($row.id)"
    Assert-True ($allowedStatuses -contains $row.status) "invalid non-site status for $($row.id): $($row.status)"
    Assert-True ($row.acceptance.Length -ge 10) "acceptance is too short for $($row.id)"
    Assert-True ($row.verification.Length -ge 5) "verification is too short for $($row.id)"
    Assert-True ($row.rollback.Length -ge 5) "rollback is too short for $($row.id)"

    if ($row.status -in @('repo_landed', 'runtime_verified', 'non_site_validated')) {
        Assert-True ($row.evidence -notmatch '<date>') "completed non-site row must use concrete evidence path: $($row.id)"
        $evidencePath = Join-Path $repoRoot $row.evidence
        if ($evidencePath -ne $reportFullPath) {
            Assert-True (Test-Path -LiteralPath $evidencePath) "completed non-site row evidence missing for $($row.id): $($row.evidence)"
        }
    }

    if ($row.status -eq 'blocked_by_onsite') {
        $onsiteText = @($row.phase, $row.category, $row.task, $row.acceptance) -join ' '
        Assert-True ($onsiteText -match '现场|隔离|教师|代理|试点|release|部署|发布|授权') "blocked_by_onsite row must name an onsite/live blocker: $($row.id)"
    }
}

foreach ($row in $rows) {
    if ([string]::IsNullOrWhiteSpace($row.depends_on)) { continue }
    foreach ($dependency in ($row.depends_on -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        Assert-True ($ids.ContainsKey($dependency)) "dependency does not exist for $($row.id): $dependency"
    }
}

foreach ($requiredId in @('NS001','NS002','NS003','NS004','NS901','NS902','NS904','NS1001','NS1005')) {
    Assert-True ($ids.ContainsKey($requiredId)) "required non-site milestone missing: $requiredId"
}

$roadmapContent = Get-Content -LiteralPath $roadmapFullPath -Raw
foreach ($status in $allowedStatuses) {
    Assert-True ($roadmapContent.Contains($status)) "roadmap missing status definition: $status"
}
Assert-True ($roadmapContent.Contains('tasks/non-site-implementation-plan.csv')) 'roadmap must link the machine-readable non-site plan'

$byStatus = [ordered]@{}
foreach ($group in ($rows | Group-Object status | Sort-Object Name)) {
    $byStatus[$group.Name] = $group.Count
}

$byPhase = [ordered]@{}
foreach ($group in ($rows | Group-Object phase | Sort-Object Name)) {
    $byPhase[$group.Name] = $group.Count
}

$firstPlanned = @($rows | Where-Object { $_.status -eq 'planned' } | Select-Object -First 1)
$nextTask = if ($firstPlanned.Count -gt 0) { $firstPlanned[0].id } else { 'none' }

$report = [ordered]@{
    status = 'pass'
    task = 'non-site implementation plan guard'
    checkedAt = (Get-Date).ToString('s')
    planPath = $PlanPath
    roadmapPath = $RoadmapPath
    rowCount = $rows.Count
    statusCounts = $byStatus
    phaseCounts = $byPhase
    nextPlannedTask = $nextTask
    requiredStatuses = $allowedStatuses
    conclusion = 'non-site plan is parseable, dependency-closed, status-bounded, and concrete evidence is required before rows can claim landed or validated states'
}

New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8

param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $CurrentStatusPath = 'docs/CurrentClosureStatus.md',
    [string] $ReleaseCardPath = 'docs/109_ReleaseGoNoGoCard.md',
    [string] $ReportPath = 'tmp/verification/roadmap.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Resolve-RepoPath([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "missing roadmap input: $Path" }
    return $fullPath
}

$rows = @(Import-Csv -LiteralPath (Resolve-RepoPath $BacklogPath) -Encoding UTF8)
if ($rows.Count -eq 0) { throw 'backlog must contain at least one task' }

$requiredColumns = @('id', 'phase', 'category', 'task', 'priority', 'status', 'depends_on', 'acceptance', 'verification')
$actualColumns = @($rows[0].PSObject.Properties.Name)
$missingColumns = @($requiredColumns | Where-Object { $actualColumns -notcontains $_ })
if ($missingColumns.Count -gt 0) { throw "backlog columns missing: $($missingColumns -join ', ')" }

$byId = @{}
foreach ($row in $rows) {
    $id = [string]$row.id
    if ([string]::IsNullOrWhiteSpace($id)) { throw 'backlog task id must not be blank' }
    if ($byId.ContainsKey($id)) { throw "duplicate backlog task id: $id" }
    if ([string]$row.status -notin @('已完成', '待办')) { throw "unsupported backlog status for $id`: $($row.status)" }
    $byId[$id] = $row
}

foreach ($row in $rows) {
    foreach ($dependency in @(([string]$row.depends_on -split ';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        if (-not $byId.ContainsKey($dependency)) { throw "unknown dependency for $($row.id): $dependency" }
    }
}

foreach ($id in @('REAL005', 'P001', 'P002', 'P003', 'P004', 'P005', 'P006')) {
    if (-not $byId.ContainsKey($id)) { throw "required closeout task missing: $id" }
}
if ([string]$byId['REAL005'].status -ne '已完成') { throw 'REAL005 backlog row must preserve repo-side completion' }
foreach ($id in @('P001', 'P002', 'P003', 'P004', 'P005', 'P006')) {
    if ([string]$byId[$id].status -ne '待办') { throw "$id must remain open until onsite/manual evidence closes it" }
}

$currentStatus = Get-Content -LiteralPath (Resolve-RepoPath $CurrentStatusPath) -Raw -Encoding UTF8
$releaseCard = Get-Content -LiteralPath (Resolve-RepoPath $ReleaseCardPath) -Raw -Encoding UTF8
if ($currentStatus -notmatch 'REAL005\s*=\s*not_closed' -or $currentStatus -notmatch 'P001-P006') {
    throw 'current closure status must preserve REAL005 not_closed and P001-P006 open'
}
if ($releaseCard -notmatch 'No-Go') { throw 'release card must remain No-Go' }

$report = [ordered]@{
    status = 'pass'
    checkedAt = (Get-Date).ToString('s')
    taskCount = $rows.Count
    completedCount = @($rows | Where-Object status -eq '已完成').Count
    openCount = @($rows | Where-Object status -eq '待办').Count
    nextTask = 'P001'
    closeout = [ordered]@{
        real005RepoSide = [string]$byId['REAL005'].status
        real005ClosureStatus = 'not_closed'
        open = @('P001', 'P002', 'P003', 'P004', 'P005', 'P006')
        releaseDecision = 'No-Go'
    }
    boundary = 'Backlog structure and current closeout truth only; completed-task evidence is historical and is not re-audited here.'
}

$fullReportPath = Join-Path $repoRoot $ReportPath
New-Item -ItemType Directory -Path (Split-Path -Parent $fullReportPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $fullReportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 6

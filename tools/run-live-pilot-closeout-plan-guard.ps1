param(
    [string] $PlanPath = 'tasks/live-pilot-closeout-plan.csv',
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ReleaseCardPath = 'docs/109_ReleaseGoNoGoCard.md',
    [string] $ClosureSummaryPath = 'docs/CurrentClosureStatus.md',
    [string] $Real005ReportPath = '',
    [string] $JsonReportPath = 'tmp/verification/live-pilot-closeout-plan.json',
    [string] $MarkdownReportPath = 'tmp/verification/live-pilot-closeout-plan.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Resolve-RepoPath([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "missing closeout input: $Path" }
    return $fullPath
}

if ([string]::IsNullOrWhiteSpace($Real005ReportPath)) {
    $entry = & (Join-Path $PSScriptRoot 'get-current-evidence.ps1') -Id 'real005-closure-standard' | ConvertFrom-Json
    $Real005ReportPath = [string]$entry.currentPath
}

$plan = @(Import-Csv -LiteralPath (Resolve-RepoPath $PlanPath) -Encoding UTF8)
$backlog = @(Import-Csv -LiteralPath (Resolve-RepoPath $BacklogPath) -Encoding UTF8)
$real005 = Get-Content -LiteralPath (Resolve-RepoPath $Real005ReportPath) -Raw -Encoding UTF8 | ConvertFrom-Json
$releaseCard = Get-Content -LiteralPath (Resolve-RepoPath $ReleaseCardPath) -Raw -Encoding UTF8
$closureSummary = Get-Content -LiteralPath (Resolve-RepoPath $ClosureSummaryPath) -Raw -Encoding UTF8

$requiredColumns = @('id', 'parent_id', 'wave', 'category', 'slice', 'status', 'depends_on', 'acceptance', 'verification', 'evidence_anchor', 'owner_role')
$actualColumns = @($plan[0].PSObject.Properties.Name)
$missingColumns = @($requiredColumns | Where-Object { $actualColumns -notcontains $_ })
if ($missingColumns.Count -gt 0) { throw "closeout plan columns missing: $($missingColumns -join ', ')" }
if ($plan.Count -ne 26) { throw "closeout plan must contain 26 rows, actual=$($plan.Count)" }

$expectedCompleted = @('REAL005A', 'REAL005B', 'REAL005C', 'REAL005D')
$expectedParents = @('REAL005', 'P001', 'P003', 'P005', 'P006')
$planById = @{}
foreach ($row in $plan) {
    if ($planById.ContainsKey([string]$row.id)) { throw "duplicate closeout slice: $($row.id)" }
    if ([string]$row.parent_id -notin $expectedParents) { throw "unsupported closeout parent for $($row.id): $($row.parent_id)" }
    if ([string]$row.status -notin @('已完成', '待办')) { throw "unsupported closeout status for $($row.id): $($row.status)" }
    $planById[[string]$row.id] = $row
}
foreach ($id in $expectedCompleted) {
    if (-not $planById.ContainsKey($id) -or [string]$planById[$id].status -ne '已完成') { throw "$id must remain repo-side complete" }
}
if (@($plan | Where-Object status -eq '已完成').Count -ne 4 -or @($plan | Where-Object status -eq '待办').Count -ne 22) {
    throw 'closeout plan must preserve 4 repo-side complete slices and 22 open onsite/manual slices'
}

$backlogById = @{}
foreach ($row in $backlog) { $backlogById[[string]$row.id] = $row }
foreach ($id in @('P001', 'P002', 'P003', 'P004', 'P005', 'P006')) {
    if (-not $backlogById.ContainsKey($id) -or [string]$backlogById[$id].status -ne '待办') { throw "$id must remain open in backlog" }
}
if ([string]$real005.closureStatus -ne 'not_closed' -or $real005.fullClosureAllowed -ne $false) {
    throw 'REAL005 current evidence must remain not_closed and fullClosureAllowed=false'
}
if ($releaseCard -notmatch 'No-Go' -or $closureSummary -notmatch 'REAL005\s*=\s*not_closed') {
    throw 'release/closure docs must preserve No-Go and REAL005 not_closed'
}

$nextOpen = [ordered]@{}
foreach ($parent in $expectedParents) {
    $next = @($plan | Where-Object { $_.parent_id -eq $parent -and $_.status -eq '待办' } | Select-Object -First 1)
    $nextOpen[$parent] = if ($next.Count -eq 1) { [string]$next[0].id } else { $null }
}

$report = [ordered]@{
    status = 'pass'
    checkedAt = (Get-Date).ToString('s')
    rowCount = $plan.Count
    completedCount = 4
    openCount = 22
    real005 = [ordered]@{
        currentPath = $Real005ReportPath
        closureStatus = [string]$real005.closureStatus
        fullClosureAllowed = [bool]$real005.fullClosureAllowed
    }
    nextOpen = $nextOpen
    releaseDecision = 'No-Go'
    boundary = 'Repo-side plan consistency only; onsite environment, operator action, timing, and signatures remain external.'
}

$jsonFullPath = Join-Path $repoRoot $JsonReportPath
$markdownFullPath = Join-Path $repoRoot $MarkdownReportPath
New-Item -ItemType Directory -Path (Split-Path -Parent $jsonFullPath) -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $markdownFullPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $jsonFullPath -Encoding UTF8
@(
    '# Live pilot closeout plan'
    ''
    '- status: pass'
    '- REAL005: not_closed'
    '- release: No-Go'
    '- repo-side complete: REAL005A, REAL005B, REAL005C, REAL005D'
    '- onsite/manual open: 22'
    '- boundary: repo-side plan consistency only'
) | Set-Content -LiteralPath $markdownFullPath -Encoding UTF8
$report | ConvertTo-Json -Depth 7

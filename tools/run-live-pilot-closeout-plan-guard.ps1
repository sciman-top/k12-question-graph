param(
    [string] $PlanPath = 'tasks/live-pilot-closeout-plan.csv',
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ReleaseCardPath = 'docs/109_ReleaseGoNoGoCard.md',
    [string] $ClosureSummaryPath = 'docs/CurrentClosureStatus.md',
    [string] $Real005ReportPath = '',
    [string] $CurrentTruthPath = '',
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

Import-Module (Join-Path $PSScriptRoot 'verification/CurrentTruth.psm1') -Force
$currentTruth = if ([string]::IsNullOrWhiteSpace($CurrentTruthPath)) {
    Get-CurrentTruth -RepoRoot $repoRoot -ReleaseCardPath $ReleaseCardPath -ClosureSummaryPath $ClosureSummaryPath
}
else {
    Assert-CurrentTruthReceipt -RepoRoot $repoRoot -ReceiptPath $CurrentTruthPath `
        -ReleaseCardPath $ReleaseCardPath -ClosureSummaryPath $ClosureSummaryPath
}
$Real005ReportPath = [string]$currentTruth.real005.currentPath

$plan = @(Import-Csv -LiteralPath (Resolve-RepoPath $PlanPath) -Encoding UTF8)
$backlog = @(Import-Csv -LiteralPath (Resolve-RepoPath $BacklogPath) -Encoding UTF8)
if (-not [string]::IsNullOrWhiteSpace($PSBoundParameters['Real005ReportPath']) -and
    [string]$PSBoundParameters['Real005ReportPath'] -ne $Real005ReportPath) {
    throw "Real005 report path contradicts current evidence: expected=$Real005ReportPath"
}

$requiredColumns = @('id', 'parent_id', 'wave', 'category', 'slice', 'status', 'depends_on', 'acceptance', 'verification', 'evidence_anchor', 'owner_role')
$actualColumns = @($plan[0].PSObject.Properties.Name)
$missingColumns = @($requiredColumns | Where-Object { $actualColumns -notcontains $_ })
if ($missingColumns.Count -gt 0) { throw "closeout plan columns missing: $($missingColumns -join ', ')" }

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
$completedIds = @($plan | Where-Object status -eq '已完成' | ForEach-Object { [string]$_.id })
$unexpectedCompleted = @($completedIds | Where-Object { $expectedCompleted -notcontains $_ })
if ($unexpectedCompleted.Count -gt 0) {
    throw "only REAL005A-D may be repo-side complete, unexpected: $($unexpectedCompleted -join ', ')"
}

$backlogById = @{}
foreach ($row in $backlog) { $backlogById[[string]$row.id] = $row }
foreach ($id in @('P001', 'P002', 'P003', 'P004', 'P005', 'P006')) {
    if (-not $backlogById.ContainsKey($id) -or [string]$backlogById[$id].status -ne '待办') {
        throw "$id must remain open until onsite/manual evidence closes it"
    }
}

$nextOpen = [ordered]@{}
foreach ($parent in $expectedParents) {
    $next = @($plan | Where-Object { $_.parent_id -eq $parent -and $_.status -eq '待办' } | Select-Object -First 1)
    $nextOpen[$parent] = if ($next.Count -eq 1) { [string]$next[0].id } else { $null }
}

$completedCount = $completedIds.Count
$openCount = @($plan | Where-Object status -eq '待办').Count
$report = [ordered]@{
    status = 'pass'
    checkedAt = (Get-Date).ToString('s')
    rowCount = $plan.Count
    completedCount = $completedCount
    openCount = $openCount
    real005 = [ordered]@{
        currentPath = $Real005ReportPath
        closureStatus = [string]$currentTruth.real005.closureStatus
        fullClosureAllowed = [bool]$currentTruth.real005.fullClosureAllowed
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
    "- onsite/manual open: $openCount"
    '- boundary: repo-side plan consistency only'
) | Set-Content -LiteralPath $markdownFullPath -Encoding UTF8
$report | ConvertTo-Json -Depth 7

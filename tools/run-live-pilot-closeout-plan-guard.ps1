param(
    [string] $PlanPath = 'tasks/live-pilot-closeout-plan.csv',
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ReleaseCardPath = 'docs/109_ReleaseGoNoGoCard.md',
    [string] $ClosureSummaryPath = 'docs/112_CurrentClosureStatus_20260609.md',
    [string] $NavigationPath = 'docs/111_ProjectNavigationOverview.md',
    [string] $ReadmePath = 'README.md',
    [string] $Real005ReportPath = 'docs/evidence/20260512-real005-guangzhou-2015-2025-closure-standard-report.json',
    [string] $JsonReportPath = 'docs/evidence/20260609-live-pilot-closeout-plan-guard.json',
    [string] $MarkdownReportPath = 'docs/evidence/20260609-live-pilot-closeout-plan-guard.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Resolve-InRepoPath([string] $RelativePath) {
    return Join-Path $repoRoot $RelativePath
}

function Get-RequiredRow([object[]] $Rows, [string] $Value, [string] $Column = 'id') {
    $matches = @($Rows | Where-Object { [string] $_.$Column -eq $Value })
    Assert-True ($matches.Count -eq 1) "expected exactly one $Column=$Value row"
    return $matches[0]
}

function Get-ReferencedPaths([string] $Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }

    $matches = [regex]::Matches($Text, '(docs|tasks|tools)[\\/][A-Za-z0-9_\-./]+')
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($match in $matches) {
        $candidate = $match.Value.Replace('\', '/')
        if (-not $paths.Contains($candidate)) {
            $paths.Add($candidate)
        }
    }
    return $paths
}

function Test-InRepoPathExists([string] $RelativePath) {
    $fullPath = Resolve-InRepoPath $RelativePath
    return Test-Path -LiteralPath $fullPath
}

function Read-Json([string] $RelativePath) {
    $fullPath = Resolve-InRepoPath $RelativePath
    Assert-True (Test-Path -LiteralPath $fullPath) "missing JSON report: $RelativePath"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

$requiredColumns = @(
    'id',
    'parent_id',
    'wave',
    'category',
    'slice',
    'status',
    'depends_on',
    'acceptance',
    'verification',
    'evidence_anchor',
    'owner_role'
)

$expectedRows = @(
    @{ id = 'REAL005A'; parent = 'REAL005'; wave = 'W0' },
    @{ id = 'REAL005B'; parent = 'REAL005'; wave = 'W0' },
    @{ id = 'REAL005C'; parent = 'REAL005'; wave = 'W0' },
    @{ id = 'REAL005D'; parent = 'REAL005'; wave = 'W0' },
    @{ id = 'P001A'; parent = 'P001'; wave = 'W1' },
    @{ id = 'P001B'; parent = 'P001'; wave = 'W1' },
    @{ id = 'P001C'; parent = 'P001'; wave = 'W1' },
    @{ id = 'P001D'; parent = 'P001'; wave = 'W1' },
    @{ id = 'P001E'; parent = 'P001'; wave = 'W1' },
    @{ id = 'P001F'; parent = 'P001'; wave = 'W1' },
    @{ id = 'P001G'; parent = 'P001'; wave = 'W1' },
    @{ id = 'P001H'; parent = 'P001'; wave = 'W1' },
    @{ id = 'P003A'; parent = 'P003'; wave = 'W2' },
    @{ id = 'P003B'; parent = 'P003'; wave = 'W2' },
    @{ id = 'P003C'; parent = 'P003'; wave = 'W2' },
    @{ id = 'P003D'; parent = 'P003'; wave = 'W2' },
    @{ id = 'P003E'; parent = 'P003'; wave = 'W2' },
    @{ id = 'P005A'; parent = 'P005'; wave = 'W3' },
    @{ id = 'P005B'; parent = 'P005'; wave = 'W3' },
    @{ id = 'P005C'; parent = 'P005'; wave = 'W3' },
    @{ id = 'P005D'; parent = 'P005'; wave = 'W3' },
    @{ id = 'P006A'; parent = 'P006'; wave = 'W4' },
    @{ id = 'P006B'; parent = 'P006'; wave = 'W4' },
    @{ id = 'P006C'; parent = 'P006'; wave = 'W4' },
    @{ id = 'P006D'; parent = 'P006'; wave = 'W4' },
    @{ id = 'P006E'; parent = 'P006'; wave = 'W4' }
)

$docReferences = @(
    @{ path = $ReleaseCardPath; keywords = @('No-Go', 'tasks/live-pilot-closeout-plan.csv', 'REAL005', 'P001', 'P003', 'P005', 'P006') },
    @{ path = $ClosureSummaryPath; keywords = @('REAL005', 'not_closed', 'P001', '现场') },
    @{ path = $NavigationPath; keywords = @('tasks/live-pilot-closeout-plan.csv', 'P001 / P003 / P005 / P006 / REAL005') },
    @{ path = $ReadmePath; keywords = @('tasks/live-pilot-closeout-plan.csv', 'REAL005', 'P001/P003/P005/P006') }
)

$planFullPath = Resolve-InRepoPath $PlanPath
$backlogFullPath = Resolve-InRepoPath $BacklogPath
$jsonReportFullPath = Resolve-InRepoPath $JsonReportPath
$markdownReportFullPath = Resolve-InRepoPath $MarkdownReportPath

Assert-True (Test-Path -LiteralPath $planFullPath) "missing closeout plan: $PlanPath"
Assert-True (Test-Path -LiteralPath $backlogFullPath) "missing backlog: $BacklogPath"

$planRows = @(Import-Csv -LiteralPath $planFullPath -Encoding UTF8)
$backlogRows = @(Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8)
Assert-True ($planRows.Count -eq $expectedRows.Count) "unexpected closeout row count: expected $($expectedRows.Count), actual $($planRows.Count)"

foreach ($column in $requiredColumns) {
    Assert-True ($planRows.Count -gt 0 -and $planRows[0].PSObject.Properties.Name -contains $column) "closeout plan missing column: $column"
}

$backlogById = @{}
foreach ($row in $backlogRows) {
    $backlogById[[string] $row.id] = $row
}

foreach ($requiredId in @('REAL005', 'P001', 'P002', 'P003', 'P004', 'P005', 'P006', 'NS1308')) {
    Assert-True ($backlogById.ContainsKey($requiredId)) "backlog missing required task: $requiredId"
}

for ($i = 0; $i -lt $expectedRows.Count; $i++) {
    $expected = $expectedRows[$i]
    $actual = $planRows[$i]
    Assert-True ([string] $actual.id -eq $expected.id) "closeout row order drift at position $($i + 1): expected $($expected.id), actual $($actual.id)"
    Assert-True ([string] $actual.parent_id -eq $expected.parent) "closeout row parent mismatch for $($expected.id)"
    Assert-True ([string] $actual.wave -eq $expected.wave) "closeout row wave mismatch for $($expected.id)"
    Assert-True ($backlogById.ContainsKey([string] $actual.parent_id)) "closeout row parent missing from backlog: $($actual.id) -> $($actual.parent_id)"
    foreach ($fieldName in @('category','slice','status','acceptance','verification','evidence_anchor','owner_role')) {
        Assert-True (-not [string]::IsNullOrWhiteSpace([string] $actual.$fieldName)) "closeout row missing ${fieldName}: $($actual.id)"
    }
}

$allowedStatuses = @('待办', '进行中', '已完成', 'blocked_by_onsite')
foreach ($row in $planRows) {
    Assert-True ($allowedStatuses -contains [string] $row.status) "unsupported closeout status for $($row.id): $($row.status)"
}

$real005Row = $backlogById['REAL005']
$p001Row = $backlogById['P001']
$p003Row = $backlogById['P003']
$p005Row = $backlogById['P005']
$p006Row = $backlogById['P006']
$p002Row = $backlogById['P002']
$p004Row = $backlogById['P004']

Assert-True ([string] $real005Row.status -eq '已完成') 'REAL005 must remain completed as the closure-standard definition task'
foreach ($taskRow in @($p001Row, $p003Row, $p005Row, $p006Row)) {
    Assert-True ([string] $taskRow.status -eq '待办') "$($taskRow.id) must remain todo before onsite closeout"
    Assert-True ([string] $taskRow.acceptance -match 'live-pilot-closeout-plan\.csv') "$($taskRow.id) acceptance must reference live-pilot-closeout-plan.csv"
}
Assert-True ([string] $p002Row.status -eq '待办') 'P002 must remain todo before P003 closeout'
Assert-True ([string] $p004Row.status -eq '待办') 'P004 must remain todo before P005 closeout'

Assert-True (([string] $p001Row.depends_on -split ';') -contains 'NS1308') 'P001 must still depend on NS1308'
Assert-True ([string] (Get-RequiredRow $planRows 'P001A').depends_on -eq 'NS1308') 'P001A must start from NS1308'
Assert-True ([string] (Get-RequiredRow $planRows 'P001H').depends_on -eq 'P001E;P001F;P001G') 'P001H must wait for printer/network/domain facts'
Assert-True ([string] (Get-RequiredRow $planRows 'P003A').depends_on -eq 'P002') 'P003A must depend on P002'
Assert-True ([string] (Get-RequiredRow $planRows 'P005A').depends_on -eq 'P004') 'P005A must depend on P004'
Assert-True ([string] (Get-RequiredRow $planRows 'P006A').depends_on -eq 'P005D') 'P006A must depend on P005D'

$real005Report = Read-Json $Real005ReportPath
Assert-True ([string] $real005Report.status -eq 'pass') 'REAL005 report must pass as a guard definition'
Assert-True ([string] $real005Report.closureStatus -eq 'not_closed') 'REAL005 report must stay not_closed'
Assert-True (-not [bool] $real005Report.fullClosureAllowed) 'REAL005 fullClosureAllowed must remain false'

foreach ($entry in $docReferences) {
    $fullPath = Resolve-InRepoPath $entry.path
    Assert-True (Test-Path -LiteralPath $fullPath) "missing referenced document: $($entry.path)"
    $text = Get-Content -LiteralPath $fullPath -Raw
    foreach ($keyword in $entry.keywords) {
        Assert-True ($text.Contains($keyword)) "$($entry.path) missing keyword: $keyword"
    }
}

$missingAnchors = New-Object System.Collections.Generic.List[string]
foreach ($row in $planRows) {
    foreach ($fieldValue in @([string] $row.verification, [string] $row.evidence_anchor)) {
        foreach ($reference in (Get-ReferencedPaths $fieldValue)) {
            if (-not (Test-InRepoPathExists $reference)) {
                $missingAnchors.Add("$($row.id):$reference")
            }
        }
    }
}
Assert-True ($missingAnchors.Count -eq 0) ("closeout plan references missing repo paths: " + ($missingAnchors -join ', '))

$statusCounts = [ordered]@{}
foreach ($group in ($planRows | Group-Object status | Sort-Object Name)) {
    $statusCounts[$group.Name] = $group.Count
}

$parentCounts = [ordered]@{}
foreach ($group in ($planRows | Group-Object parent_id | Sort-Object Name)) {
    $parentCounts[$group.Name] = $group.Count
}

$nextOpenByParent = [ordered]@{}
foreach ($parent in @('REAL005','P001','P003','P005','P006')) {
    $nextOpen = @($planRows | Where-Object { [string] $_.parent_id -eq $parent -and [string] $_.status -ne '已完成' } | Select-Object -First 1)
    $nextOpenByParent[$parent] = if ($nextOpen.Count -gt 0) { [string] $nextOpen[0].id } else { 'none' }
}

$checkedAt = (Get-Date).ToString('s')
$report = [ordered]@{
    status = 'pass'
    taskId = 'LIVE_CLOSEOUT_GUARD'
    checkedAt = $checkedAt
    planPath = $PlanPath
    backlogPath = $BacklogPath
    releaseCardPath = $ReleaseCardPath
    closureSummaryPath = $ClosureSummaryPath
    real005ClosureStatus = [string] $real005Report.closureStatus
    fullClosureAllowed = [bool] $real005Report.fullClosureAllowed
    rowCount = $planRows.Count
    statusCounts = $statusCounts
    parentCounts = $parentCounts
    nextOpenByParent = $nextOpenByParent
    backlogStatuses = [ordered]@{
        REAL005 = [string] $real005Row.status
        P001 = [string] $p001Row.status
        P003 = [string] $p003Row.status
        P005 = [string] $p005Row.status
        P006 = [string] $p006Row.status
    }
    boundary = 'closeout plan guard only; it keeps REAL005 not_closed and does not create onsite evidence'
}

New-Item -ItemType Directory -Path (Split-Path -Parent $jsonReportFullPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonReportFullPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# Live Pilot Closeout Plan Guard')
$lines.Add('')
$lines.Add("- status: pass")
$lines.Add("- checked_at: $checkedAt")
$lines.Add("- plan_path: $PlanPath")
$lines.Add("- row_count: $($planRows.Count)")
$lines.Add("- real005_closure_status: $($real005Report.closureStatus)")
$lines.Add("- full_closure_allowed: $([bool] $real005Report.fullClosureAllowed)")
$lines.Add('')
$lines.Add('## Backlog Status')
foreach ($entry in $report.backlogStatuses.GetEnumerator()) {
    $lines.Add("- $($entry.Key): $($entry.Value)")
}
$lines.Add('')
$lines.Add('## Status Counts')
foreach ($entry in $statusCounts.GetEnumerator()) {
    $lines.Add("- $($entry.Key): $($entry.Value)")
}
$lines.Add('')
$lines.Add('## Next Open Slice By Parent')
foreach ($entry in $nextOpenByParent.GetEnumerator()) {
    $lines.Add("- $($entry.Key): $($entry.Value)")
}
$lines.Add('')
$lines.Add('## Boundary')
$lines.Add('This guard validates the repo-side closeout plan, path anchors, and truthful No-Go wording. It does not execute isolated-machine work, printer/network/domain checks, onsite pilot observation, or final signoff.')

New-Item -ItemType Directory -Path (Split-Path -Parent $markdownReportFullPath) -Force | Out-Null
$lines | Set-Content -LiteralPath $markdownReportFullPath -Encoding UTF8

$report | ConvertTo-Json -Depth 8

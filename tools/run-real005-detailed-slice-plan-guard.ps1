param(
    [string] $PlanPath = 'tasks/real005-detailed-slice-plan.csv',
    [string] $CriteriaPath = 'tasks/real-guangzhou-closure-criteria.csv',
    [string] $TopLevelPlanPath = 'tasks/live-pilot-closeout-plan.csv',
    [string] $DetailedTreePath = 'docs/115_REAL005_DetailedSliceTree.md',
    [string] $JsonReportPath = '',
    [string] $MarkdownReportPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runDate = Get-Date -Format 'yyyyMMdd'

function Resolve-RepoPath([string] $Path) {
    Join-Path $repoRoot $Path
}

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Split-Values([string] $Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
    return @(
        $Value.Split(';') |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

if ([string]::IsNullOrWhiteSpace($JsonReportPath)) {
    $JsonReportPath = ('docs/evidence/{0}-real005-detailed-slice-plan-guard.json' -f $runDate)
}

if ([string]::IsNullOrWhiteSpace($MarkdownReportPath)) {
    $MarkdownReportPath = ('docs/evidence/{0}-real005-detailed-slice-plan-guard.md' -f $runDate)
}

$planFullPath = Resolve-RepoPath $PlanPath
$criteriaFullPath = Resolve-RepoPath $CriteriaPath
$topLevelPlanFullPath = Resolve-RepoPath $TopLevelPlanPath
$treeFullPath = Resolve-RepoPath $DetailedTreePath
$jsonFullPath = Resolve-RepoPath $JsonReportPath
$markdownFullPath = Resolve-RepoPath $MarkdownReportPath

foreach ($path in @($planFullPath, $criteriaFullPath, $topLevelPlanFullPath, $treeFullPath)) {
    Assert-True (Test-Path -LiteralPath $path) "missing REAL005 detailed slice input: $path"
}

$planRows = @(Import-Csv -LiteralPath $planFullPath -Encoding UTF8)
$criteriaRows = @(Import-Csv -LiteralPath $criteriaFullPath -Encoding UTF8)
$topLevelRows = @(Import-Csv -LiteralPath $topLevelPlanFullPath -Encoding UTF8)
$treeText = Get-Content -LiteralPath $treeFullPath -Raw

$requiredColumns = @('id','parent_slice','criterion_ids','focus','status','depends_on','acceptance','verification','evidence_anchor','owner_role')
foreach ($column in $requiredColumns) {
    Assert-True ($planRows.Count -gt 0 -and $planRows[0].PSObject.Properties.Name -contains $column) "REAL005 detailed slice plan missing column: $column"
}

$expectedIds = @(
    'REAL005B1','REAL005B2','REAL005B3','REAL005B4','REAL005B5','REAL005B6',
    'REAL005C1','REAL005C2','REAL005C3','REAL005C4','REAL005C5'
)

Assert-True ($planRows.Count -eq $expectedIds.Count) "unexpected REAL005 detailed slice row count: expected $($expectedIds.Count), actual $($planRows.Count)"

$criteriaIds = @($criteriaRows | ForEach-Object { [string] $_.criterion_id })
$topLevelIds = @($topLevelRows | ForEach-Object { [string] $_.id })
Assert-True ($topLevelIds -contains 'REAL005B') 'top-level closeout plan must keep REAL005B'
Assert-True ($topLevelIds -contains 'REAL005C') 'top-level closeout plan must keep REAL005C'

$allowedStatuses = @('待办', '进行中', '已完成')
$byId = @{}
for ($i = 0; $i -lt $planRows.Count; $i++) {
    $row = $planRows[$i]
    $expectedId = $expectedIds[$i]
    Assert-True ([string] $row.id -eq $expectedId) "REAL005 detailed slice row order drift at position $($i + 1): expected $expectedId actual $($row.id)"
    Assert-True (-not $byId.ContainsKey([string] $row.id)) "duplicate REAL005 detailed slice id: $($row.id)"
    $byId[[string] $row.id] = $row
    foreach ($fieldName in @('parent_slice','criterion_ids','focus','status','depends_on','acceptance','verification','evidence_anchor','owner_role')) {
        Assert-True (-not [string]::IsNullOrWhiteSpace([string] $row.$fieldName)) "REAL005 detailed slice row missing ${fieldName}: $($row.id)"
    }
    Assert-True ($allowedStatuses -contains [string] $row.status) "unsupported REAL005 detailed slice status for $($row.id): $($row.status)"
    Assert-True (@('REAL005B','REAL005C') -contains [string] $row.parent_slice) "REAL005 detailed slice parent must remain REAL005B or REAL005C: $($row.id)"
    foreach ($criterionId in (Split-Values $row.criterion_ids)) {
        Assert-True ($criteriaIds -contains $criterionId) "REAL005 detailed slice references unknown criterion: $criterionId"
    }
}

Assert-True ([string] $byId['REAL005B1'].depends_on -eq 'REAL005A') 'REAL005B1 must start from REAL005A'
Assert-True ([string] $byId['REAL005B2'].depends_on -eq 'REAL005B1') 'REAL005B2 must depend on REAL005B1'
Assert-True ([string] $byId['REAL005B3'].depends_on -eq 'REAL005B2') 'REAL005B3 must depend on REAL005B2'
Assert-True ([string] $byId['REAL005B4'].depends_on -eq 'REAL005B3') 'REAL005B4 must depend on REAL005B3'
Assert-True ([string] $byId['REAL005B5'].depends_on -eq 'REAL005B4') 'REAL005B5 must depend on REAL005B4'
Assert-True ([string] $byId['REAL005B6'].depends_on -eq 'REAL005B5') 'REAL005B6 must depend on REAL005B5'
Assert-True ([string] $byId['REAL005C1'].depends_on -eq 'REAL005B6') 'REAL005C1 must depend on REAL005B6'
Assert-True ([string] $byId['REAL005C2'].depends_on -eq 'REAL005C1') 'REAL005C2 must depend on REAL005C1'
Assert-True ([string] $byId['REAL005C3'].depends_on -eq 'REAL005C2') 'REAL005C3 must depend on REAL005C2'
Assert-True ([string] $byId['REAL005C4'].depends_on -eq 'REAL005C3') 'REAL005C4 must depend on REAL005C3'
Assert-True ([string] $byId['REAL005C5'].depends_on -eq 'REAL005C4') 'REAL005C5 must depend on REAL005C4'

foreach ($docNeedle in @('REAL005B1','REAL005B6','REAL005C1','REAL005C5')) {
    Assert-True ($treeText.Contains($docNeedle)) "REAL005 detailed tree doc must mention $docNeedle"
}

$report = [ordered]@{
    status = 'pass'
    taskId = 'REAL005_DETAILED_SLICE_PLAN_GUARD'
    checkedAt = (Get-Date).ToString('s')
    rowCount = $planRows.Count
    planPath = $PlanPath
    detailedTreePath = $DetailedTreePath
    boundary = 'REAL005 detailed slice plan may refine REAL005B/C execution, but must not replace the top-level live-pilot closeout plan or weaken not_closed truth semantics'
}

New-Item -ItemType Directory -Path (Split-Path -Parent $jsonFullPath) -Force | Out-Null
$json = $report | ConvertTo-Json -Depth 6
Set-Content -LiteralPath $jsonFullPath -Value $json -Encoding UTF8
$markdown = @(
    '# REAL005 Detailed Slice Plan Guard',
    '',
    "- checked_at: $($report.checkedAt)",
    "- row_count: $($report.rowCount)",
    ('- plan_path: `{0}`' -f $PlanPath),
    ('- detailed_tree_path: `{0}`' -f $DetailedTreePath),
    "- boundary: $($report.boundary)"
) -join [Environment]::NewLine
Set-Content -LiteralPath $markdownFullPath -Value $markdown -Encoding UTF8

$report | ConvertTo-Json -Depth 6

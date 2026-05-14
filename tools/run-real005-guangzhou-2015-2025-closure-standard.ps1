param(
    [string] $CriteriaPath = 'tasks/real-guangzhou-closure-criteria.csv',
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $DashboardPath = 'tasks/completion-state-dashboard.csv',
    [string] $JsonReportPath = 'docs/evidence/20260512-real005-guangzhou-2015-2025-closure-standard-report.json',
    [string] $MarkdownReportPath = 'docs/evidence/20260512-real005-guangzhou-2015-2025-closure-standard-report.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Resolve-RepoPath([string] $Path) {
    Join-Path $repoRoot $Path
}

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

$criteriaFullPath = Resolve-RepoPath $CriteriaPath
$backlogFullPath = Resolve-RepoPath $BacklogPath
$dashboardFullPath = Resolve-RepoPath $DashboardPath
$jsonFullPath = Resolve-RepoPath $JsonReportPath
$markdownFullPath = Resolve-RepoPath $MarkdownReportPath

foreach ($path in @($criteriaFullPath, $backlogFullPath, $dashboardFullPath)) {
    Assert-True (Test-Path -LiteralPath $path) "required REAL005 input missing: $path"
}

$criteriaRows = @(Import-Csv -LiteralPath $criteriaFullPath -Encoding UTF8)
$backlogRows = @(Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8)
$dashboardRows = @(Import-Csv -LiteralPath $dashboardFullPath -Encoding UTF8)

$requiredCriteriaColumns = @(
    'criterion_id',
    'category',
    'required_scope',
    'completion_requirement',
    'evidence_required',
    'blocking_gap_policy'
)

foreach ($column in $requiredCriteriaColumns) {
    Assert-True ($criteriaRows.Count -gt 0 -and $criteriaRows[0].PSObject.Properties.Name -contains $column) "criteria missing column: $column"
}

$criteriaById = @{}
foreach ($row in $criteriaRows) {
    Assert-True (-not [string]::IsNullOrWhiteSpace($row.criterion_id)) 'criteria row has blank criterion_id'
    Assert-True (-not $criteriaById.ContainsKey($row.criterion_id)) "duplicate criterion_id: $($row.criterion_id)"
    $criteriaById[$row.criterion_id] = $row
    foreach ($column in $requiredCriteriaColumns) {
        Assert-True (-not [string]::IsNullOrWhiteSpace($row.$column)) "criterion $($row.criterion_id) missing $column"
    }
    Assert-True ($row.blocking_gap_policy -match 'not_closed') "criterion $($row.criterion_id) must fail closed to not_closed"
}

foreach ($id in @('RG001','RG002','RG003','RG004','RG005','RG006','RG007','RG008','RG009','RG010','RG011','RG012')) {
    Assert-True ($criteriaById.ContainsKey($id)) "required closure criterion missing: $id"
}

$backlogById = @{}
foreach ($row in $backlogRows) { $backlogById[$row.id] = $row }
foreach ($id in @('REAL001','REAL002','REAL003','REAL004','REAL005')) {
    Assert-True ($backlogById.ContainsKey($id)) "backlog missing $id"
}

$dashboardRow = $dashboardRows | Where-Object { $_.area_id -eq 'real-guangzhou-2015-2025' } | Select-Object -First 1
Assert-True ($null -ne $dashboardRow) 'completion dashboard missing real-guangzhou-2015-2025 row'
Assert-True ($dashboardRow.next_task -eq 'REAL005') 'real-guangzhou-2015-2025 dashboard row must point to REAL005'
Assert-True ($dashboardRow.current_state -ne 'teacher_validated' -and $dashboardRow.current_state -ne 'release_ready') '2015-2025 closure cannot be marked teacher_validated/release_ready before all REAL criteria pass'

$knownEvidence = [ordered]@{
    REAL001 = @(
        'docs/evidence/20260512-guangzhou-2015-real-ingest-slice-report.json',
        'docs/evidence/20260512-guangzhou-2015-real-ingest-slice-dry-run-report.json'
    )
    REAL002 = @(
        'docs/evidence/20260512-guangzhou-2015-visual-region-slice-report.json'
    )
    REAL003 = @(
        'docs/evidence/20260514-real003-guangzhou-physics-year-batch-ingest-report.json'
    )
    REAL004 = @(
        'docs/evidence/20260512-real004-guangzhou-2015-review-smoke-report.json'
    )
}

$gaps = New-Object System.Collections.Generic.List[object]
foreach ($id in @('REAL002','REAL003','REAL004')) {
    if ($backlogById[$id].status -ne '已完成') {
        $gaps.Add([ordered]@{
            id = $id
            reason = "backlog status is $($backlogById[$id].status)"
            nextAction = $backlogById[$id].verification
        })
    }
}

foreach ($scriptPath in @(
    'tools/run-guangzhou-2015-visual-region-slice.ps1',
    'tools/run-guangzhou-physics-year-batch-ingest.ps1'
)) {
    if (-not (Test-Path -LiteralPath (Resolve-RepoPath $scriptPath))) {
        $gaps.Add([ordered]@{
            id = $scriptPath
            reason = 'required implementation gate script is missing'
            nextAction = 'implement script with dry-run default, evidence report, and rollback policy'
        })
    }
}

foreach ($item in $knownEvidence.GetEnumerator()) {
    foreach ($evidencePath in $item.Value) {
        if (-not (Test-Path -LiteralPath (Resolve-RepoPath $evidencePath))) {
            $gaps.Add([ordered]@{
                id = $evidencePath
                reason = "expected evidence for $($item.Key) is missing"
                nextAction = "rerun $($item.Key) guard"
            })
        }
    }
}

if ($dashboardRow.current_state -ne 'teacher_validated' -and $dashboardRow.current_state -ne 'release_ready') {
    $gaps.Add([ordered]@{
        id = 'real-guangzhou-2015-2025-dashboard'
        reason = "dashboard state is $($dashboardRow.current_state); gap=$($dashboardRow.blocking_gap)"
        nextAction = 'complete yearly question evidence and update dashboard only after every REAL005 criterion is satisfied'
    })
}

$closureStatus = if ($gaps.Count -eq 0 -and $backlogById['REAL005'].status -eq '已完成') { 'closed' } else { 'not_closed' }
$gapItems = @($gaps | ForEach-Object { $_ })
$criteriaItems = @($criteriaRows | ForEach-Object {
    [ordered]@{
        criterionId = $_.criterion_id
        category = $_.category
        requiredScope = $_.required_scope
        evidenceRequired = $_.evidence_required
        blockingGapPolicy = $_.blocking_gap_policy
    }
})
$unfinishedRealTasks = @('REAL002','REAL003','REAL004') | Where-Object { $backlogById[$_].status -ne '已完成' }
$unfinishedText = if ($unfinishedRealTasks.Count -gt 0) { $unfinishedRealTasks -join '/' } else { '逐年逐题闭环证据' }
$summaryChinese = if ($closureStatus -eq 'closed') {
    'REAL005 判定标准全部满足，才允许宣称 2015-2025 真卷全流程闭环。'
}
else {
    "REAL005 判定标准已安装并通过自检；当前真实状态是 not_closed，仍需完成 $unfinishedText。"
}

$report = [ordered]@{
    status = 'pass'
    task = 'REAL005'
    checkedAt = (Get-Date).ToString('s')
    closureStatus = $closureStatus
    criteriaPath = $CriteriaPath
    criteriaCount = $criteriaRows.Count
    requiredYears = @(2015..2025)
    fullClosureAllowed = ($closureStatus -eq 'closed')
    currentTruth = 'S012/REAL001/REAL002/REAL003 dry-run/REAL004 review smoke evidence is not enough to claim 2015-2025 full workflow closure'
    gaps = $gapItems
    requiredCriteria = $criteriaItems
    rollback = 'git restore tracked files; remove generated REAL005 evidence reports if this standard is reverted'
    summaryChinese = $summaryChinese
}

New-Item -ItemType Directory -Path (Split-Path -Parent $jsonFullPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonFullPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# REAL005 广州 2015-2025 真卷全流程闭环判定标准')
$lines.Add('')
$lines.Add("- status: $($report.status)")
$lines.Add("- closure_status: $($report.closureStatus)")
$lines.Add("- criteria_count: $($report.criteriaCount)")
$lines.Add("- full_closure_allowed: $($report.fullClosureAllowed)")
$lines.Add('')
$lines.Add('## 当前结论')
$lines.Add($report.summaryChinese)
$lines.Add('')
$lines.Add('## 阻断缺口')
if ($gaps.Count -eq 0) {
    $lines.Add('- 无')
}
else {
    foreach ($gap in $gaps) {
        $lines.Add("- $($gap.id): $($gap.reason); next=$($gap.nextAction)")
    }
}
$lines.Add('')
$lines.Add('## 判定标准')
foreach ($criterion in $criteriaRows) {
    $lines.Add("- $($criterion.criterion_id) $($criterion.category): $($criterion.evidence_required)")
}
$lines | Set-Content -LiteralPath $markdownFullPath -Encoding UTF8

$report | ConvertTo-Json -Depth 8

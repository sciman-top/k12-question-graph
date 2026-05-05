param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/q004-cross-subject-diff-report-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-q004-cross-subject-diff-report-preflight.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$backlogFullPath = Join-Path $repoRoot $BacklogPath
$checklistFullPath = Join-Path $repoRoot $ChecklistPath
$evidenceFullPath = Join-Path $repoRoot $EvidencePath

Assert-True (Test-Path -LiteralPath $backlogFullPath) "Q004 backlog file missing: $BacklogPath"
Assert-True (Test-Path -LiteralPath $checklistFullPath) "Q004 checklist missing: $ChecklistPath"
Assert-True (Test-Path -LiteralPath $evidenceFullPath) "Q004 evidence markdown missing: $EvidencePath"

$rows = Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8
$byId = @{}
foreach ($row in $rows) { $byId[$row.id] = $row }

foreach ($requiredTaskId in @('Q003', 'Q004')) {
    Assert-True ($byId.ContainsKey($requiredTaskId)) "Q004 prerequisite task missing: $requiredTaskId"
}

$q003 = $byId['Q003']
$q004 = $byId['Q004']

Assert-True ($q004.depends_on -eq 'Q003') 'Q004 must depend on Q003'
Assert-True ($q003.status -eq '待办') 'Q003 still pending; Q004 must remain todo before active drill closes'
Assert-True ($q004.status -eq '待办') 'Q004 must remain todo until cross-subject diff report evidence is completed'

$checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
foreach ($keyword in @('题型', '标签', '评分', '导出', '分析', 'docs/58')) {
    Assert-True ($checklistText.Contains($keyword)) "Q004 checklist missing keyword: $keyword"
}

$evidenceText = Get-Content -LiteralPath $evidenceFullPath -Raw
foreach ($keyword in @('preflight', 'Q004', 'platform_na', 'gate_na', '差异报告', '下一步')) {
    Assert-True ($evidenceText.Contains($keyword)) "Q004 evidence missing keyword: $keyword"
}

[ordered]@{
    status = 'pass'
    taskId = 'Q004'
    mode = 'preflight_only'
    q003Status = $q003.status
    q004Status = $q004.status
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    boundary = 'cross-subject diff report is not executed in this contract; keep Q004 as todo until Q003 closes and docs evidence is complete'
    checkedAt = (Get-Date).ToString('s')
} | ConvertTo-Json -Depth 4

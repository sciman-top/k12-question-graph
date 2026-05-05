param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/q005-multi-subject-ui-simplification-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-q005-multi-subject-ui-simplification-preflight.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$backlogFullPath = Join-Path $repoRoot $BacklogPath
$checklistFullPath = Join-Path $repoRoot $ChecklistPath
$evidenceFullPath = Join-Path $repoRoot $EvidencePath

Assert-True (Test-Path -LiteralPath $backlogFullPath) "Q005 backlog file missing: $BacklogPath"
Assert-True (Test-Path -LiteralPath $checklistFullPath) "Q005 checklist missing: $ChecklistPath"
Assert-True (Test-Path -LiteralPath $evidenceFullPath) "Q005 evidence markdown missing: $EvidencePath"

$rows = Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8
$byId = @{}
foreach ($row in $rows) { $byId[$row.id] = $row }

foreach ($requiredTaskId in @('Q004', 'Q005')) {
    Assert-True ($byId.ContainsKey($requiredTaskId)) "Q005 prerequisite task missing: $requiredTaskId"
}

$q004 = $byId['Q004']
$q005 = $byId['Q005']

Assert-True ($q005.depends_on -eq 'Q004') 'Q005 must depend on Q004'
Assert-True ($q004.status -eq '待办') 'Q004 still pending; Q005 must remain todo before diff report closes'
Assert-True ($q005.status -eq '待办') 'Q005 must remain todo until multi-subject UI simplification evidence is completed'

$checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
foreach ($keyword in @('四个入口', '学科切换', '默认值', '模板', 'UI smoke', 'teacher efficiency')) {
    Assert-True ($checklistText.Contains($keyword)) "Q005 checklist missing keyword: $keyword"
}

$evidenceText = Get-Content -LiteralPath $evidenceFullPath -Raw
foreach ($keyword in @('preflight', 'Q005', 'platform_na', 'gate_na', 'UI 简化复核', '下一步')) {
    Assert-True ($evidenceText.Contains($keyword)) "Q005 evidence missing keyword: $keyword"
}

[ordered]@{
    status = 'pass'
    taskId = 'Q005'
    mode = 'preflight_only'
    q004Status = $q004.status
    q005Status = $q005.status
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    boundary = 'multi-subject UI simplification review is not executed in this contract; keep Q005 as todo until Q004 closes and UI evidence is complete'
    checkedAt = (Get-Date).ToString('s')
} | ConvertTo-Json -Depth 4

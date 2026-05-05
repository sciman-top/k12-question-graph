param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/p005-pilot-feedback-backlog-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-p005-pilot-feedback-backlog-preflight.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$backlogFullPath = Join-Path $repoRoot $BacklogPath
$checklistFullPath = Join-Path $repoRoot $ChecklistPath
$evidenceFullPath = Join-Path $repoRoot $EvidencePath

Assert-True (Test-Path -LiteralPath $backlogFullPath) "P005 backlog file missing: $BacklogPath"
Assert-True (Test-Path -LiteralPath $checklistFullPath) "P005 checklist missing: $ChecklistPath"
Assert-True (Test-Path -LiteralPath $evidenceFullPath) "P005 evidence markdown missing: $EvidencePath"

$rows = Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8
$byId = @{}
foreach ($row in $rows) { $byId[$row.id] = $row }

foreach ($requiredTaskId in @('P004', 'P005')) {
    Assert-True ($byId.ContainsKey($requiredTaskId)) "P005 prerequisite task missing: $requiredTaskId"
}

$p004 = $byId['P004']
$p005 = $byId['P005']

Assert-True ($p005.depends_on -eq 'P004') 'P005 must depend on P004'
Assert-True ($p004.status -eq '待办') 'P004 still pending; P005 must stay todo before onsite round1 evidence closes'
Assert-True ($p005.status -eq '待办') 'P005 must remain todo until pilot feedback is transformed into backlog decisions'

$checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
foreach ($keyword in @('教师效率', '频率', '风险', '成本', '保留', '修改', '后置', '不做')) {
    Assert-True ($checklistText.Contains($keyword)) "P005 checklist missing keyword: $keyword"
}

$evidenceText = Get-Content -LiteralPath $evidenceFullPath -Raw
foreach ($keyword in @('preflight', 'P005', 'platform_na', 'gate_na', '试点反馈转 backlog', '下一步')) {
    Assert-True ($evidenceText.Contains($keyword)) "P005 evidence missing keyword: $keyword"
}

[ordered]@{
    status = 'pass'
    taskId = 'P005'
    mode = 'preflight_only'
    p004Status = $p004.status
    p005Status = $p005.status
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    boundary = 'pilot feedback triage is not executed in this contract; keep P005 as todo until P004 closes and backlog triage evidence is complete'
    checkedAt = (Get-Date).ToString('s')
} | ConvertTo-Json -Depth 4

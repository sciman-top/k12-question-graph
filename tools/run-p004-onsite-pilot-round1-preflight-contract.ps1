param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/p004-onsite-pilot-round1-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-p004-onsite-pilot-round1-preflight.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$backlogFullPath = Join-Path $repoRoot $BacklogPath
$checklistFullPath = Join-Path $repoRoot $ChecklistPath
$evidenceFullPath = Join-Path $repoRoot $EvidencePath

Assert-True (Test-Path -LiteralPath $backlogFullPath) "P004 backlog file missing: $BacklogPath"
Assert-True (Test-Path -LiteralPath $checklistFullPath) "P004 checklist missing: $ChecklistPath"
Assert-True (Test-Path -LiteralPath $evidenceFullPath) "P004 evidence markdown missing: $EvidencePath"

$rows = Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8
$byId = @{}
foreach ($row in $rows) { $byId[$row.id] = $row }

foreach ($requiredTaskId in @('P003', 'P004')) {
    Assert-True ($byId.ContainsKey($requiredTaskId)) "P004 prerequisite task missing: $requiredTaskId"
}

$p003 = $byId['P003']
$p004 = $byId['P004']

Assert-True ($p004.depends_on -eq 'P003') 'P004 must depend on P003'
Assert-True ($p003.status -eq '待办') 'P003 still pending; P004 must stay todo before onsite admission closes'
Assert-True ($p004.status -eq '待办') 'P004 must remain todo until onsite pilot round1 evidence is complete'

$checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
foreach ($keyword in @('实际耗时', '操作卡点', '错误', '文案困惑', '回滚事件', 'teacher pilot evidence')) {
    Assert-True ($checklistText.Contains($keyword)) "P004 checklist missing keyword: $keyword"
}

$evidenceText = Get-Content -LiteralPath $evidenceFullPath -Raw
foreach ($keyword in @('preflight', 'P004', 'platform_na', 'gate_na', '现场教师试点第 1 轮', '下一步')) {
    Assert-True ($evidenceText.Contains($keyword)) "P004 evidence missing keyword: $keyword"
}

[ordered]@{
    status = 'pass'
    taskId = 'P004'
    mode = 'preflight_only'
    p003Status = $p003.status
    p004Status = $p004.status
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    boundary = 'onsite pilot round1 is not executed in this contract; keep P004 as todo until P003 closes and teacher pilot evidence is complete'
    checkedAt = (Get-Date).ToString('s')
} | ConvertTo-Json -Depth 4

param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/p002-teacher-proxy-pilot-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-p002-teacher-proxy-pilot-preflight.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$backlogFullPath = Join-Path $repoRoot $BacklogPath
$checklistFullPath = Join-Path $repoRoot $ChecklistPath
$evidenceFullPath = Join-Path $repoRoot $EvidencePath

Assert-True (Test-Path -LiteralPath $backlogFullPath) "P002 backlog file missing: $BacklogPath"
Assert-True (Test-Path -LiteralPath $checklistFullPath) "P002 checklist missing: $ChecklistPath"
Assert-True (Test-Path -LiteralPath $evidenceFullPath) "P002 evidence markdown missing: $EvidencePath"

$rows = Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8
$byId = @{}
foreach ($row in $rows) { $byId[$row.id] = $row }

foreach ($requiredTaskId in @('P001', 'P002')) {
    Assert-True ($byId.ContainsKey($requiredTaskId)) "P002 prerequisite task missing: $requiredTaskId"
}

$p001 = $byId['P001']
$p002 = $byId['P002']

Assert-True ($p002.depends_on -eq 'P001') 'P002 must depend on P001'
Assert-True ($p001.status -eq '待办') 'P001 still pending; P002 must stay todo before isolated-machine rehearsal evidence closes'
Assert-True ($p002.status -eq '待办') 'P002 must remain todo until authorized/de-identified materials proxy pilot evidence is completed'

$checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
foreach ($keyword in @('授权', '脱敏', '导入', '组卷', '导出', '成绩导入', 'teacher proxy report', 'evidence')) {
    Assert-True ($checklistText.Contains($keyword)) "P002 checklist missing keyword: $keyword"
}

$evidenceText = Get-Content -LiteralPath $evidenceFullPath -Raw
foreach ($keyword in @('preflight', 'P002', 'platform_na', 'gate_na', '代理试点', '下一步')) {
    Assert-True ($evidenceText.Contains($keyword)) "P002 evidence missing keyword: $keyword"
}

[ordered]@{
    status = 'pass'
    taskId = 'P002'
    mode = 'preflight_only'
    p001Status = $p001.status
    p002Status = $p002.status
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    boundary = 'teacher proxy pilot not executed in this contract; keep P002 as todo until P001 closes and proxy evidence is complete'
    checkedAt = (Get-Date).ToString('s')
} | ConvertTo-Json -Depth 4

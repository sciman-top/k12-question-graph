param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/p003-onsite-pilot-admission-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-p003-onsite-pilot-admission-preflight.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$backlogFullPath = Join-Path $repoRoot $BacklogPath
$checklistFullPath = Join-Path $repoRoot $ChecklistPath
$evidenceFullPath = Join-Path $repoRoot $EvidencePath

Assert-True (Test-Path -LiteralPath $backlogFullPath) "P003 backlog file missing: $BacklogPath"
Assert-True (Test-Path -LiteralPath $checklistFullPath) "P003 checklist missing: $ChecklistPath"
Assert-True (Test-Path -LiteralPath $evidenceFullPath) "P003 evidence markdown missing: $EvidencePath"

$rows = Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8
$byId = @{}
foreach ($row in $rows) { $byId[$row.id] = $row }

foreach ($requiredTaskId in @('P002', 'P003')) {
    Assert-True ($byId.ContainsKey($requiredTaskId)) "P003 prerequisite task missing: $requiredTaskId"
}

$p002 = $byId['P002']
$p003 = $byId['P003']

Assert-True ($p003.depends_on -eq 'P002') 'P003 must depend on P002'
Assert-True ($p002.status -eq '待办') 'P002 still pending; P003 must stay todo before teacher proxy pilot evidence closes'
Assert-True ($p003.status -eq '待办') 'P003 must remain todo until onsite pilot admission card is complete'

$checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
foreach ($keyword in @('教师参与边界', '数据授权', '支持人', '回滚方案', '反馈模板', 'pilot admission card')) {
    Assert-True ($checklistText.Contains($keyword)) "P003 checklist missing keyword: $keyword"
}

$evidenceText = Get-Content -LiteralPath $evidenceFullPath -Raw
foreach ($keyword in @('preflight', 'P003', 'platform_na', 'gate_na', '现场教师试点准入', '下一步')) {
    Assert-True ($evidenceText.Contains($keyword)) "P003 evidence missing keyword: $keyword"
}

[ordered]@{
    status = 'pass'
    taskId = 'P003'
    mode = 'preflight_only'
    p002Status = $p002.status
    p003Status = $p003.status
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    boundary = 'onsite pilot admission is not executed in this contract; keep P003 as todo until P002 closes and admission card is complete'
    checkedAt = (Get-Date).ToString('s')
} | ConvertTo-Json -Depth 4

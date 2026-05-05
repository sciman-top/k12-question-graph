param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/p006-release-decision-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-p006-release-decision-preflight.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$backlogFullPath = Join-Path $repoRoot $BacklogPath
$checklistFullPath = Join-Path $repoRoot $ChecklistPath
$evidenceFullPath = Join-Path $repoRoot $EvidencePath

Assert-True (Test-Path -LiteralPath $backlogFullPath) "P006 backlog file missing: $BacklogPath"
Assert-True (Test-Path -LiteralPath $checklistFullPath) "P006 checklist missing: $ChecklistPath"
Assert-True (Test-Path -LiteralPath $evidenceFullPath) "P006 evidence markdown missing: $EvidencePath"

$rows = Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8
$byId = @{}
foreach ($row in $rows) { $byId[$row.id] = $row }

foreach ($requiredTaskId in @('P005', 'P006')) {
    Assert-True ($byId.ContainsKey($requiredTaskId)) "P006 prerequisite task missing: $requiredTaskId"
}

$p005 = $byId['P005']
$p006 = $byId['P006']

Assert-True ($p006.depends_on -eq 'P005') 'P006 must depend on P005'
Assert-True ($p005.status -eq '待办') 'P005 still pending; P006 must stay todo before feedback triage closes'
Assert-True ($p006.status -eq '待办') 'P006 must remain todo until release decision record is complete'

$checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
foreach ($keyword in @('门禁', '备份', '恢复', '教师效率', '隐私边界', 'release decision record', 'tag candidate')) {
    Assert-True ($checklistText.Contains($keyword)) "P006 checklist missing keyword: $keyword"
}

$evidenceText = Get-Content -LiteralPath $evidenceFullPath -Raw
foreach ($keyword in @('preflight', 'P006', 'platform_na', 'gate_na', '发布裁决', '下一步')) {
    Assert-True ($evidenceText.Contains($keyword)) "P006 evidence missing keyword: $keyword"
}

[ordered]@{
    status = 'pass'
    taskId = 'P006'
    mode = 'preflight_only'
    p005Status = $p005.status
    p006Status = $p006.status
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    boundary = 'release decision is not executed in this contract; keep P006 as todo until P005 closes and decision evidence is complete'
    checkedAt = (Get-Date).ToString('s')
} | ConvertTo-Json -Depth 4

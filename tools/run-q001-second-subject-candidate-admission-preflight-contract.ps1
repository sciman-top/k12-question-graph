param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/q001-second-subject-candidate-admission-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-q001-second-subject-candidate-admission-preflight.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$backlogFullPath = Join-Path $repoRoot $BacklogPath
$checklistFullPath = Join-Path $repoRoot $ChecklistPath
$evidenceFullPath = Join-Path $repoRoot $EvidencePath

Assert-True (Test-Path -LiteralPath $backlogFullPath) "Q001 backlog file missing: $BacklogPath"
Assert-True (Test-Path -LiteralPath $checklistFullPath) "Q001 checklist missing: $ChecklistPath"
Assert-True (Test-Path -LiteralPath $evidenceFullPath) "Q001 evidence markdown missing: $EvidencePath"

$rows = Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8
$byId = @{}
foreach ($row in $rows) { $byId[$row.id] = $row }

foreach ($requiredTaskId in @('P006', 'Q001')) {
    Assert-True ($byId.ContainsKey($requiredTaskId)) "Q001 prerequisite task missing: $requiredTaskId"
}

$p006 = $byId['P006']
$q001 = $byId['Q001']

Assert-True ($q001.depends_on -eq 'P006') 'Q001 must depend on P006'
Assert-True ($p006.status -eq '待办') 'P006 still pending; Q001 must remain todo before release decision closes'
Assert-True ($q001.status -eq '待办') 'Q001 must remain todo until second-subject source package admission is completed'

$checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
foreach ($keyword in @('候选', '来源资料', 'candidate', '不直接 active', 'dry-run', 'evidence')) {
    Assert-True ($checklistText.Contains($keyword)) "Q001 checklist missing keyword: $keyword"
}

$evidenceText = Get-Content -LiteralPath $evidenceFullPath -Raw
foreach ($keyword in @('preflight', 'Q001', 'platform_na', 'gate_na', '多学科', '下一步')) {
    Assert-True ($evidenceText.Contains($keyword)) "Q001 evidence missing keyword: $keyword"
}

[ordered]@{
    status = 'pass'
    taskId = 'Q001'
    mode = 'preflight_only'
    p006Status = $p006.status
    q001Status = $q001.status
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    boundary = 'second-subject candidate admission is not executed in this contract; keep Q001 as todo until P006 closes and source package evidence is complete'
    checkedAt = (Get-Date).ToString('s')
} | ConvertTo-Json -Depth 4

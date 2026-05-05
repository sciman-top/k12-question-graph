param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/q002-second-subject-teacher-review-template-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-q002-second-subject-teacher-review-template-preflight.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$backlogFullPath = Join-Path $repoRoot $BacklogPath
$checklistFullPath = Join-Path $repoRoot $ChecklistPath
$evidenceFullPath = Join-Path $repoRoot $EvidencePath

Assert-True (Test-Path -LiteralPath $backlogFullPath) "Q002 backlog file missing: $BacklogPath"
Assert-True (Test-Path -LiteralPath $checklistFullPath) "Q002 checklist missing: $ChecklistPath"
Assert-True (Test-Path -LiteralPath $evidenceFullPath) "Q002 evidence markdown missing: $EvidencePath"

$rows = Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8
$byId = @{}
foreach ($row in $rows) { $byId[$row.id] = $row }

foreach ($requiredTaskId in @('Q001', 'Q002')) {
    Assert-True ($byId.ContainsKey($requiredTaskId)) "Q002 prerequisite task missing: $requiredTaskId"
}

$q001 = $byId['Q001']
$q002 = $byId['Q002']

Assert-True ($q002.depends_on -eq 'Q001') 'Q002 must depend on Q001'
Assert-True ($q001.status -eq '待办') 'Q001 still pending; Q002 must remain todo before candidate admission closes'
Assert-True ($q002.status -eq '待办') 'Q002 must remain todo until teacher review template evidence is completed'

$checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
foreach ($keyword in @('教师复核', '候选知识点', '教材章节', '课标', '考点', 'review evidence')) {
    Assert-True ($checklistText.Contains($keyword)) "Q002 checklist missing keyword: $keyword"
}

$evidenceText = Get-Content -LiteralPath $evidenceFullPath -Raw
foreach ($keyword in @('preflight', 'Q002', 'platform_na', 'gate_na', '复核模板', '下一步')) {
    Assert-True ($evidenceText.Contains($keyword)) "Q002 evidence missing keyword: $keyword"
}

[ordered]@{
    status = 'pass'
    taskId = 'Q002'
    mode = 'preflight_only'
    q001Status = $q001.status
    q002Status = $q002.status
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    boundary = 'second-subject teacher review template is not executed in this contract; keep Q002 as todo until Q001 closes and review evidence is complete'
    checkedAt = (Get-Date).ToString('s')
} | ConvertTo-Json -Depth 4

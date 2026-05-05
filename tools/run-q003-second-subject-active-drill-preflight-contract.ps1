param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/q003-second-subject-active-drill-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-q003-second-subject-active-drill-preflight.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$backlogFullPath = Join-Path $repoRoot $BacklogPath
$checklistFullPath = Join-Path $repoRoot $ChecklistPath
$evidenceFullPath = Join-Path $repoRoot $EvidencePath

Assert-True (Test-Path -LiteralPath $backlogFullPath) "Q003 backlog file missing: $BacklogPath"
Assert-True (Test-Path -LiteralPath $checklistFullPath) "Q003 checklist missing: $ChecklistPath"
Assert-True (Test-Path -LiteralPath $evidenceFullPath) "Q003 evidence markdown missing: $EvidencePath"

$rows = Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8
$byId = @{}
foreach ($row in $rows) { $byId[$row.id] = $row }

foreach ($requiredTaskId in @('Q002', 'Q003')) {
    Assert-True ($byId.ContainsKey($requiredTaskId)) "Q003 prerequisite task missing: $requiredTaskId"
}

$q002 = $byId['Q002']
$q003 = $byId['Q003']

Assert-True ($q003.depends_on -eq 'Q002') 'Q003 must depend on Q002'
Assert-True ($q002.status -eq '待办') 'Q002 still pending; Q003 must remain todo before review template closes'
Assert-True ($q003.status -eq '待办') 'Q003 must remain todo until second-subject active drill evidence is completed'

$checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
foreach ($keyword in @('backup', 'readiness', 'reviewed', 'active', 'rollback snapshot', 'dry-run')) {
    Assert-True ($checklistText.Contains($keyword)) "Q003 checklist missing keyword: $keyword"
}

$evidenceText = Get-Content -LiteralPath $evidenceFullPath -Raw
foreach ($keyword in @('preflight', 'Q003', 'platform_na', 'gate_na', 'active 演练', '下一步')) {
    Assert-True ($evidenceText.Contains($keyword)) "Q003 evidence missing keyword: $keyword"
}

[ordered]@{
    status = 'pass'
    taskId = 'Q003'
    mode = 'preflight_only'
    q002Status = $q002.status
    q003Status = $q003.status
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    boundary = 'second-subject active drill is not executed in this contract; keep Q003 as todo until Q002 closes and activation evidence is complete'
    checkedAt = (Get-Date).ToString('s')
} | ConvertTo-Json -Depth 4

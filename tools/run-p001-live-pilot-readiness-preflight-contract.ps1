param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/p001-live-pilot-release-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-p001-live-pilot-readiness-preflight.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Resolve-InRepoPath([string]$RelativePath) {
    return Join-Path $repoRoot $RelativePath
}

$backlogFullPath = Resolve-InRepoPath $BacklogPath
$checklistFullPath = Resolve-InRepoPath $ChecklistPath
$evidenceFullPath = Resolve-InRepoPath $EvidencePath

Assert-True (Test-Path -LiteralPath $backlogFullPath) "P001 backlog file missing: $BacklogPath"
Assert-True (Test-Path -LiteralPath $checklistFullPath) "P001 checklist missing: $ChecklistPath"
Assert-True (Test-Path -LiteralPath $evidenceFullPath) "P001 evidence markdown missing: $EvidencePath"

$rows = Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8
$byId = @{}
foreach ($row in $rows) {
    $byId[$row.id] = $row
}

foreach ($requiredTaskId in @('O004B', 'O006', 'O007', 'P001')) {
    Assert-True ($byId.ContainsKey($requiredTaskId)) "P001 prerequisite task missing: $requiredTaskId"
}

$p001 = $byId['P001']
$o004b = $byId['O004B']
$o006 = $byId['O006']
$o007 = $byId['O007']

$dependencies = @($p001.depends_on -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($required in @('O004B', 'O006', 'O007')) {
    Assert-True ($dependencies -contains $required) "P001 depends_on must include $required"
}

Assert-True ($p001.status -eq '待办') 'P001 must remain todo until isolated-machine rehearsal is executed with live evidence'
Assert-True ($o004b.status -eq '已完成') 'O004B must be completed before P001 preflight can pass'
Assert-True ($o006.status -eq '已完成') 'O006 must be completed before P001 preflight can pass'
Assert-True ($o007.status -eq '已完成') 'O007 must be completed before P001 preflight can pass'

$checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
foreach ($keyword in @('隔离机器', '安装向导', '备份', '恢复', '权限审计', '教师入口 smoke', 'release checklist', 'evidence')) {
    Assert-True ($checklistText.Contains($keyword)) "P001 checklist missing keyword: $keyword"
}

$evidenceText = Get-Content -LiteralPath $evidenceFullPath -Raw
foreach ($keyword in @('preflight', 'P001', 'platform_na', 'gate_na', '隔离机器', '下一步')) {
    Assert-True ($evidenceText.Contains($keyword)) "P001 evidence missing keyword: $keyword"
}

[ordered]@{
    status = 'pass'
    taskId = 'P001'
    mode = 'preflight_only'
    p001Status = $p001.status
    dependencies = $dependencies
    prerequisites = [ordered]@{
        O004B = $o004b.status
        O006 = $o006.status
        O007 = $o007.status
    }
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    boundary = 'isolated-machine live rehearsal not executed in this contract; keep P001 as todo until site run is complete'
    checkedAt = (Get-Date).ToString('s')
} | ConvertTo-Json -Depth 6

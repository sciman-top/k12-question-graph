param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/p004-onsite-pilot-round1-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-p004-onsite-pilot-round1-preflight.md',
    [string] $ReportPath = 'docs/evidence/20260523-p004-onsite-pilot-round1-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Resolve-RepoPath([string]$Path) {
    return Join-Path $repoRoot ($Path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
}

function Write-ContentIfChanged([string]$Path, [string]$Content) {
    $fullPath = Resolve-RepoPath $Path
    $parent = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (Test-Path -LiteralPath $fullPath) {
        $existing = Get-Content -LiteralPath $fullPath -Raw
        if ($existing -eq $Content) { return }
    }

    Set-Content -LiteralPath $fullPath -Value $Content -Encoding UTF8
}

$backlogFullPath = Resolve-RepoPath $BacklogPath
$checklistFullPath = Resolve-RepoPath $ChecklistPath
$evidenceFullPath = Resolve-RepoPath $EvidencePath

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

$report = [ordered]@{
    status = 'pass'
    taskId = 'P004'
    mode = 'preflight_only'
    checkedAt = (Get-Date).ToString('s')
    p003Status = $p003.status
    p004Status = $p004.status
    closeTaskAllowed = $false
    currentDecision = 'keep_P004_todo_until_onsite_round1_evidence_close'
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    reportPath = $ReportPath
    blockers = @(
        'P003 onsite admission card is not closed.',
        'Actual teacher elapsed time is not recorded.',
        'Operation friction, error, copy confusion, rollback event, and teacher evidence are not recorded.'
    )
    nextRequiredEvidence = @(
        'pilot admission card from P003',
        'onsite teacher pilot evidence',
        'elapsed time and operation friction log',
        'rollback event log and support-owner notes'
    )
    failClosedRules = @(
        'Do not execute onsite pilot round1 from this preflight contract.',
        'Do not mark P004 complete without actual teacher/onsite or explicitly authorized proxy evidence.',
        'Do not advance P005 feedback backlog until P004 teacher pilot evidence exists.'
    )
    boundary = 'onsite pilot round1 is not executed in this contract; keep P004 as todo until P003 closes and teacher pilot evidence is complete'
    rollback = 'revert tools/run-p004-onsite-pilot-round1-preflight-contract.ps1, tasks/backlog.csv, and remove the generated P004 admission report.'
}

$json = $report | ConvertTo-Json -Depth 8
Write-ContentIfChanged -Path $ReportPath -Content $json
$report | ConvertTo-Json -Depth 8

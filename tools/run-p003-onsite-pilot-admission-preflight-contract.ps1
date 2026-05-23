param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/p003-onsite-pilot-admission-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-p003-onsite-pilot-admission-preflight.md',
    [string] $ReportPath = 'docs/evidence/20260523-p003-onsite-pilot-admission-report.json'
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

$report = [ordered]@{
    status = 'pass'
    taskId = 'P003'
    mode = 'preflight_only'
    checkedAt = (Get-Date).ToString('s')
    p002Status = $p002.status
    p003Status = $p003.status
    closeTaskAllowed = $false
    currentDecision = 'keep_P003_todo_until_proxy_pilot_and_onsite_admission_card_close'
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    reportPath = $ReportPath
    blockers = @(
        'P002 teacher proxy pilot evidence is not closed.',
        'Teacher participation boundary is not signed off.',
        'Data authorization, support owner, rollback plan, and feedback template are not recorded.'
    )
    nextRequiredEvidence = @(
        'teacher proxy pilot report from P002',
        'onsite pilot admission card',
        'data authorization and support owner record',
        'rollback plan and feedback template'
    )
    failClosedRules = @(
        'Do not execute onsite pilot admission from this preflight contract.',
        'Do not mark P003 complete without explicit teacher boundary, data authorization, support owner, and rollback evidence.',
        'Do not advance P004 onsite round1 until P003 admission card is complete.'
    )
    boundary = 'onsite pilot admission is not executed in this contract; keep P003 as todo until P002 closes and admission card is complete'
    rollback = 'revert tools/run-p003-onsite-pilot-admission-preflight-contract.ps1, tasks/backlog.csv, and remove the generated P003 admission report.'
}

$json = $report | ConvertTo-Json -Depth 8
Write-ContentIfChanged -Path $ReportPath -Content $json
$report | ConvertTo-Json -Depth 8

param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/p002-teacher-proxy-pilot-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-p002-teacher-proxy-pilot-preflight.md',
    [string] $ReportPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runDate = Get-Date -Format 'yyyyMMdd'

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = ('docs/evidence/{0}-p002-teacher-proxy-pilot-admission-report.json' -f $runDate)
}

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

$report = [ordered]@{
    status = 'pass'
    taskId = 'P002'
    mode = 'preflight_only'
    checkedAt = (Get-Date).ToString('s')
    p001Status = $p001.status
    p002Status = $p002.status
    closeTaskAllowed = $false
    currentDecision = 'keep_P002_todo_until_P001_and_proxy_evidence_close'
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    reportPath = $ReportPath
    blockers = @(
        'P001 isolated-machine rehearsal evidence is not closed.',
        'Authorized or de-identified teacher proxy material path is not recorded.',
        'Teacher proxy timing, rollback, import, paper export, and score import evidence is not recorded.'
    )
    nextRequiredEvidence = @(
        'P001 isolated-machine release rehearsal report',
        'authorized_or_deidentified_material_manifest',
        'teacher proxy import to paper export to score import timing report',
        'rollback and privacy handling evidence'
    )
    failClosedRules = @(
        'Do not mark P002 complete from a local preflight-only run.',
        'Do not use real student or school data without authorization/de-identification evidence.',
        'Do not advance P003 onsite admission until P002 has a teacher proxy report.'
    )
    boundary = 'teacher proxy pilot not executed in this contract; keep P002 as todo until P001 closes and proxy evidence is complete'
    rollback = 'revert tools/run-p002-teacher-proxy-pilot-preflight-contract.ps1, tasks/backlog.csv, and remove the generated P002 admission report.'
}

$json = $report | ConvertTo-Json -Depth 8
Write-ContentIfChanged -Path $ReportPath -Content $json
$report | ConvertTo-Json -Depth 8

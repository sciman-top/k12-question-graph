param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/q004-cross-subject-diff-report-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-q004-cross-subject-diff-report-preflight.md',
    [string] $ReportPath = 'docs/evidence/20260523-q004-cross-subject-diff-report.json'
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

Assert-True (Test-Path -LiteralPath $backlogFullPath) "Q004 backlog file missing: $BacklogPath"
Assert-True (Test-Path -LiteralPath $checklistFullPath) "Q004 checklist missing: $ChecklistPath"
Assert-True (Test-Path -LiteralPath $evidenceFullPath) "Q004 evidence markdown missing: $EvidencePath"

$rows = Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8
$byId = @{}
foreach ($row in $rows) { $byId[$row.id] = $row }

foreach ($requiredTaskId in @('Q003', 'Q004')) {
    Assert-True ($byId.ContainsKey($requiredTaskId)) "Q004 prerequisite task missing: $requiredTaskId"
}

$q003 = $byId['Q003']
$q004 = $byId['Q004']

Assert-True ($q004.depends_on -eq 'Q003') 'Q004 must depend on Q003'
Assert-True ($q003.status -eq '待办') 'Q003 still pending; Q004 must remain todo before active drill closes'
Assert-True ($q004.status -eq '待办') 'Q004 must remain todo until cross-subject diff report evidence is completed'

$checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
foreach ($keyword in @('题型', '标签', '评分', '导出', '分析', 'docs/58')) {
    Assert-True ($checklistText.Contains($keyword)) "Q004 checklist missing keyword: $keyword"
}

$evidenceText = Get-Content -LiteralPath $evidenceFullPath -Raw
foreach ($keyword in @('preflight', 'Q004', 'platform_na', 'gate_na', '差异报告', '下一步')) {
    Assert-True ($evidenceText.Contains($keyword)) "Q004 evidence missing keyword: $keyword"
}

$report = [ordered]@{
    status = 'pass'
    taskId = 'Q004'
    mode = 'preflight_only'
    checkedAt = (Get-Date).ToString('s')
    q003Status = $q003.status
    q004Status = $q004.status
    closeTaskAllowed = $false
    currentDecision = 'keep_Q004_todo_until_Q003_and_cross_subject_diff_evidence_close'
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    reportPath = $ReportPath
    blockers = @(
        'Q003 second-subject active drill evidence is not closed.',
        'Cross-subject differences for question types, tags, scoring, export, and analysis are not recorded.',
        'Dynamic-element updates are not mapped back to docs/58 and rollback evidence.'
    )
    nextRequiredEvidence = @(
        'Q003 active drill report',
        'cross-subject question type, tag, scoring, export, and analysis diff report',
        'dynamic elements update for docs/58',
        'teacher-efficiency and maintenance-load review'
    )
    failClosedRules = @(
        'Do not hard-code second-subject differences into product code.',
        'Do not mark Q004 complete without a diff report and dynamic-element mapping.',
        'Do not advance Q005 UI changes before Q004 proves the minimal difference set.'
    )
    boundary = 'cross-subject diff report is not executed in this contract; keep Q004 as todo until Q003 closes and docs evidence is complete'
    rollback = 'revert tools/run-q004-cross-subject-diff-report-preflight-contract.ps1, tasks/backlog.csv, and remove the generated Q004 admission report.'
}

$json = $report | ConvertTo-Json -Depth 8
Write-ContentIfChanged -Path $ReportPath -Content $json
$report | ConvertTo-Json -Depth 8

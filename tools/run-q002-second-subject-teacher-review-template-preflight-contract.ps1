param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/q002-second-subject-teacher-review-template-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-q002-second-subject-teacher-review-template-preflight.md',
    [string] $ReportPath = 'docs/evidence/20260523-q002-second-subject-teacher-review-template-report.json'
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

$report = [ordered]@{
    status = 'pass'
    taskId = 'Q002'
    mode = 'preflight_only'
    checkedAt = (Get-Date).ToString('s')
    q001Status = $q001.status
    q002Status = $q002.status
    closeTaskAllowed = $false
    currentDecision = 'keep_Q002_todo_until_Q001_and_teacher_review_evidence_close'
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    reportPath = $ReportPath
    blockers = @(
        'Q001 second-subject candidate admission is not closed.',
        'Teacher review template has not been applied to real candidate knowledge points, textbook chapters, curriculum standards, and exam points.',
        'Review evidence and teacher-efficiency impact are not recorded.'
    )
    nextRequiredEvidence = @(
        'Q001 candidate admission report',
        'teacher review checklist filled against candidate assets',
        'review evidence for knowledge points, textbook chapters, curriculum standards, and exam points',
        'teacher-efficiency note for review workload'
    )
    failClosedRules = @(
        'Do not mark Q002 complete from a template-only preflight.',
        'Do not advance Q003 active drill without teacher review evidence.',
        'Do not expose additional teacher-facing controls before the review workload is justified.'
    )
    boundary = 'second-subject teacher review template is not executed in this contract; keep Q002 as todo until Q001 closes and review evidence is complete'
    rollback = 'revert tools/run-q002-second-subject-teacher-review-template-preflight-contract.ps1, tasks/backlog.csv, and remove the generated Q002 admission report.'
}

$json = $report | ConvertTo-Json -Depth 8
Write-ContentIfChanged -Path $ReportPath -Content $json
$report | ConvertTo-Json -Depth 8

param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/q005-multi-subject-ui-simplification-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-q005-multi-subject-ui-simplification-preflight.md',
    [string] $ReportPath = 'docs/evidence/20260523-q005-multi-subject-ui-simplification-report.json'
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

Assert-True (Test-Path -LiteralPath $backlogFullPath) "Q005 backlog file missing: $BacklogPath"
Assert-True (Test-Path -LiteralPath $checklistFullPath) "Q005 checklist missing: $ChecklistPath"
Assert-True (Test-Path -LiteralPath $evidenceFullPath) "Q005 evidence markdown missing: $EvidencePath"

$rows = Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8
$byId = @{}
foreach ($row in $rows) { $byId[$row.id] = $row }

foreach ($requiredTaskId in @('Q004', 'Q005')) {
    Assert-True ($byId.ContainsKey($requiredTaskId)) "Q005 prerequisite task missing: $requiredTaskId"
}

$q004 = $byId['Q004']
$q005 = $byId['Q005']

Assert-True ($q005.depends_on -eq 'Q004') 'Q005 must depend on Q004'
Assert-True ($q004.status -eq '待办') 'Q004 still pending; Q005 must remain todo before diff report closes'
Assert-True ($q005.status -eq '待办') 'Q005 must remain todo until multi-subject UI simplification evidence is completed'

$checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
foreach ($keyword in @('四个入口', '学科切换', '默认值', '模板', 'UI smoke', 'teacher efficiency')) {
    Assert-True ($checklistText.Contains($keyword)) "Q005 checklist missing keyword: $keyword"
}

$evidenceText = Get-Content -LiteralPath $evidenceFullPath -Raw
foreach ($keyword in @('preflight', 'Q005', 'platform_na', 'gate_na', 'UI 简化复核', '下一步')) {
    Assert-True ($evidenceText.Contains($keyword)) "Q005 evidence missing keyword: $keyword"
}

$report = [ordered]@{
    status = 'pass'
    taskId = 'Q005'
    mode = 'preflight_only'
    checkedAt = (Get-Date).ToString('s')
    q004Status = $q004.status
    q005Status = $q005.status
    closeTaskAllowed = $false
    currentDecision = 'keep_Q005_todo_until_Q004_and_multi_subject_ui_simplification_evidence_close'
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    reportPath = $ReportPath
    blockers = @(
        'Q004 cross-subject diff report is not closed.',
        'Four teacher entry points with multi-subject defaults/templates are not smoke-tested.',
        'Teacher-efficiency evidence is not recorded for any subject switch UI.'
    )
    nextRequiredEvidence = @(
        'Q004 cross-subject diff report',
        'four-entry UI smoke with subject defaults or templates',
        'teacher-efficiency review for subject switching',
        'proof that multi-subject controls do not add teacher-facing complexity'
    )
    failClosedRules = @(
        'Do not add teacher-facing subject controls without Q004 difference evidence.',
        'Do not mark Q005 complete without four-entry UI smoke and teacher-efficiency evidence.',
        'Do not let multi-subject work expand the ordinary teacher workflow beyond the existing simplified entry points.'
    )
    boundary = 'multi-subject UI simplification review is not executed in this contract; keep Q005 as todo until Q004 closes and UI evidence is complete'
    rollback = 'revert tools/run-q005-multi-subject-ui-simplification-preflight-contract.ps1, tasks/backlog.csv, and remove the generated Q005 admission report.'
}

$json = $report | ConvertTo-Json -Depth 8
Write-ContentIfChanged -Path $ReportPath -Content $json
$report | ConvertTo-Json -Depth 8

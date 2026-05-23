param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/q003-second-subject-active-drill-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-q003-second-subject-active-drill-preflight.md',
    [string] $ReportPath = 'docs/evidence/20260523-q003-second-subject-active-drill-report.json'
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

$report = [ordered]@{
    status = 'pass'
    taskId = 'Q003'
    mode = 'preflight_only'
    checkedAt = (Get-Date).ToString('s')
    q002Status = $q002.status
    q003Status = $q003.status
    closeTaskAllowed = $false
    currentDecision = 'keep_Q003_todo_until_Q002_and_second_subject_active_drill_evidence_close'
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    reportPath = $ReportPath
    blockers = @(
        'Q002 teacher review evidence is not closed.',
        'Second-subject backup readiness, reviewed state, active switch dry-run, and rollback snapshot are not recorded.',
        'No active write is allowed from this preflight contract.'
    )
    nextRequiredEvidence = @(
        'Q002 teacher review evidence',
        'backup readiness report',
        'reviewed-to-active dry-run report',
        'rollback snapshot and restore command'
    )
    failClosedRules = @(
        'Do not perform a second-subject active switch from this preflight contract.',
        'Do not mark Q003 complete without backup, reviewed, active dry-run, and rollback evidence.',
        'Do not advance Q004 until Q003 active drill evidence exists.'
    )
    boundary = 'second-subject active drill is not executed in this contract; keep Q003 as todo until Q002 closes and activation evidence is complete'
    rollback = 'revert tools/run-q003-second-subject-active-drill-preflight-contract.ps1, tasks/backlog.csv, and remove the generated Q003 admission report.'
}

$json = $report | ConvertTo-Json -Depth 8
Write-ContentIfChanged -Path $ReportPath -Content $json
$report | ConvertTo-Json -Depth 8

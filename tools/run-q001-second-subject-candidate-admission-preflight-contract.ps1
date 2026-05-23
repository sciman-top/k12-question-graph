param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/q001-second-subject-candidate-admission-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-q001-second-subject-candidate-admission-preflight.md',
    [string] $ReportPath = 'docs/evidence/20260523-q001-second-subject-candidate-admission-report.json'
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

Assert-True (Test-Path -LiteralPath $backlogFullPath) "Q001 backlog file missing: $BacklogPath"
Assert-True (Test-Path -LiteralPath $checklistFullPath) "Q001 checklist missing: $ChecklistPath"
Assert-True (Test-Path -LiteralPath $evidenceFullPath) "Q001 evidence markdown missing: $EvidencePath"

$rows = Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8
$byId = @{}
foreach ($row in $rows) { $byId[$row.id] = $row }

foreach ($requiredTaskId in @('P006', 'Q001')) {
    Assert-True ($byId.ContainsKey($requiredTaskId)) "Q001 prerequisite task missing: $requiredTaskId"
}

$p006 = $byId['P006']
$q001 = $byId['Q001']

Assert-True ($q001.depends_on -eq 'P006') 'Q001 must depend on P006'
Assert-True ($p006.status -eq '待办') 'P006 still pending; Q001 must remain todo before release decision closes'
Assert-True ($q001.status -eq '待办') 'Q001 must remain todo until second-subject source package admission is completed'

$checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
foreach ($keyword in @('候选', '来源资料', 'candidate', '不直接 active', 'dry-run', 'evidence')) {
    Assert-True ($checklistText.Contains($keyword)) "Q001 checklist missing keyword: $keyword"
}

$evidenceText = Get-Content -LiteralPath $evidenceFullPath -Raw
foreach ($keyword in @('preflight', 'Q001', 'platform_na', 'gate_na', '多学科', '下一步')) {
    Assert-True ($evidenceText.Contains($keyword)) "Q001 evidence missing keyword: $keyword"
}

$report = [ordered]@{
    status = 'pass'
    taskId = 'Q001'
    mode = 'preflight_only'
    checkedAt = (Get-Date).ToString('s')
    p006Status = $p006.status
    q001Status = $q001.status
    closeTaskAllowed = $false
    currentDecision = 'keep_Q001_todo_until_P006_and_second_subject_source_package_close'
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    reportPath = $ReportPath
    blockers = @(
        'P006 release decision is not closed.',
        'Second-subject source package and authorization evidence is not recorded.',
        'Candidate admission manifest is not recorded; no second-subject active switch is allowed.'
    )
    nextRequiredEvidence = @(
        'P006 release decision record',
        'second-subject source package manifest',
        'source authorization and deletion boundary',
        'candidate-only admission report with no active write'
    )
    failClosedRules = @(
        'Do not mark Q001 complete from a preflight-only run.',
        'Do not import or activate a second-subject asset without source package evidence.',
        'Do not advance Q002 until Q001 candidate admission evidence exists.'
    )
    boundary = 'second-subject candidate admission is not executed in this contract; keep Q001 as todo until P006 closes and source package evidence is complete'
    rollback = 'revert tools/run-q001-second-subject-candidate-admission-preflight-contract.ps1, tasks/backlog.csv, and remove the generated Q001 admission report.'
}

$json = $report | ConvertTo-Json -Depth 8
Write-ContentIfChanged -Path $ReportPath -Content $json
$report | ConvertTo-Json -Depth 8

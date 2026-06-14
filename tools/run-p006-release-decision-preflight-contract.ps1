param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $LiveCloseoutPlanPath = 'tasks/live-pilot-closeout-plan.csv',
    [string] $ChecklistPath = 'docs/templates/p006-release-decision-checklist.md',
    [string] $DecisionRecordTemplatePath = 'docs/templates/p006-release-decision-record-template.json',
    [string] $GoNoGoCardPath = 'docs/109_ReleaseGoNoGoCard.md',
    [string] $EvidencePath = 'docs/evidence/20260505-p006-release-decision-preflight.md',
    [string] $ReportPath = 'docs/evidence/20260523-p006-release-decision-admission-report.json'
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
$liveCloseoutPlanFullPath = Resolve-RepoPath $LiveCloseoutPlanPath
$checklistFullPath = Resolve-RepoPath $ChecklistPath
$decisionRecordTemplateFullPath = Resolve-RepoPath $DecisionRecordTemplatePath
$goNoGoCardFullPath = Resolve-RepoPath $GoNoGoCardPath
$evidenceFullPath = Resolve-RepoPath $EvidencePath

Assert-True (Test-Path -LiteralPath $backlogFullPath) "P006 backlog file missing: $BacklogPath"
Assert-True (Test-Path -LiteralPath $liveCloseoutPlanFullPath) "live closeout plan missing: $LiveCloseoutPlanPath"
Assert-True (Test-Path -LiteralPath $checklistFullPath) "P006 checklist missing: $ChecklistPath"
Assert-True (Test-Path -LiteralPath $decisionRecordTemplateFullPath) "P006 decision record template missing: $DecisionRecordTemplatePath"
Assert-True (Test-Path -LiteralPath $goNoGoCardFullPath) "P006 Go/No-Go card missing: $GoNoGoCardPath"
Assert-True (Test-Path -LiteralPath $evidenceFullPath) "P006 evidence markdown missing: $EvidencePath"

$rows = Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8
$closeoutRows = @(Import-Csv -LiteralPath $liveCloseoutPlanFullPath -Encoding UTF8)
$byId = @{}
foreach ($row in $rows) { $byId[$row.id] = $row }

Assert-True ($closeoutRows.Count -eq 26) "live closeout plan row count drift: expected 26 actual $($closeoutRows.Count)"
$p006NextCloseout = @($closeoutRows | Where-Object { [string] $_.parent_id -eq 'P006' -and [string] $_.status -ne '已完成' } | Select-Object -First 1)
Assert-True ($p006NextCloseout.Count -eq 1) 'live closeout plan must expose next P006 slice'
Assert-True ([string] $p006NextCloseout[0].id -eq 'P006A') 'next P006 closeout slice must remain P006A before release decision closes'

foreach ($requiredTaskId in @('P005', 'P006')) {
    Assert-True ($byId.ContainsKey($requiredTaskId)) "P006 prerequisite task missing: $requiredTaskId"
}

$p005 = $byId['P005']
$p006 = $byId['P006']

Assert-True ($p006.depends_on -eq 'P005') 'P006 must depend on P005'
Assert-True ($p005.status -eq '待办') 'P005 still pending; P006 must stay todo before feedback triage closes'
Assert-True ($p006.status -eq '待办') 'P006 must remain todo until release decision record is complete'

$checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
foreach ($keyword in @('门禁', '备份', '恢复', '教师效率', '隐私边界', 'release decision record', 'tag candidate')) {
    Assert-True ($checklistText.Contains($keyword)) "P006 checklist missing keyword: $keyword"
}

$decisionRecordTemplate = Get-Content -LiteralPath $decisionRecordTemplateFullPath -Raw | ConvertFrom-Json
Assert-True ($decisionRecordTemplate.schemaVersion -eq 'p006-release-decision-record.v1') 'P006 decision record template schema mismatch'
foreach ($requiredField in @('decisionContext', 'referenceContext', 'impactedSurfaceIds', 'referencesReviewed', 'adoptionDecision', 'evidenceAnchors', 'gateReview', 'exceptions', 'tagCandidatePlan', 'signoff', 'finalRationale')) {
    Assert-True ($decisionRecordTemplate.PSObject.Properties.Name -contains $requiredField) "P006 decision record template missing field: $requiredField"
}
Assert-True (@($decisionRecordTemplate.impactedSurfaceIds).Count -ge 1) 'P006 decision record template must include impactedSurfaceIds'
Assert-True (@($decisionRecordTemplate.referencesReviewed).Count -ge 1) 'P006 decision record template must include referencesReviewed'
foreach ($requiredReferenceContextField in @('referenceBasisPolicy', 'referenceRequirements', 'referenceModuleMap', 'guardEvidence')) {
    Assert-True ($decisionRecordTemplate.referenceContext.PSObject.Properties.Name -contains $requiredReferenceContextField) "P006 referenceContext missing field: $requiredReferenceContextField"
    Assert-True (-not [string]::IsNullOrWhiteSpace([string] $decisionRecordTemplate.referenceContext.$requiredReferenceContextField)) "P006 referenceContext field is blank: $requiredReferenceContextField"
}
foreach ($requiredAdoptionField in @('summary', 'adopted', 'rejected', 'followUpEvidence')) {
    Assert-True ($decisionRecordTemplate.adoptionDecision.PSObject.Properties.Name -contains $requiredAdoptionField) "P006 adoptionDecision missing field: $requiredAdoptionField"
}

$goNoGoCardText = Get-Content -LiteralPath $goNoGoCardFullPath -Raw
foreach ($keyword in @('No-Go', 'P005', 'P006', 'rollback window', 'tag candidate')) {
    Assert-True ($goNoGoCardText.Contains($keyword)) "P006 Go/No-Go card missing keyword: $keyword"
}

$evidenceText = Get-Content -LiteralPath $evidenceFullPath -Raw
foreach ($keyword in @('preflight', 'P006', 'platform_na', 'gate_na', '发布裁决', '下一步')) {
    Assert-True ($evidenceText.Contains($keyword)) "P006 evidence missing keyword: $keyword"
}

$report = [ordered]@{
    status = 'pass'
    taskId = 'P006'
    mode = 'preflight_only'
    checkedAt = (Get-Date).ToString('s')
    liveCloseoutPlanPath = $LiveCloseoutPlanPath
    p005Status = $p005.status
    p006Status = $p006.status
    closeTaskAllowed = $false
    currentDecision = 'keep_P006_todo_until_release_decision_record_closes'
    checklistPath = $ChecklistPath
    decisionRecordTemplatePath = $DecisionRecordTemplatePath
    goNoGoCardPath = $GoNoGoCardPath
    evidencePath = $EvidencePath
    reportPath = $ReportPath
    closeoutPlan = [ordered]@{
        rowCount = $closeoutRows.Count
        nextOpenP006 = [string] $p006NextCloseout[0].id
    }
    blockers = @(
        'P005 pilot feedback triage is not closed.',
        'Release decision record is not recorded.',
        'Final gate, backup/restore, teacher efficiency, privacy boundary, rollback, and tag-candidate evidence are not complete.'
    )
    nextRequiredEvidence = @(
        'P005 feedback triage result',
        'structured release decision record template',
        'updated go/no-go card',
        'full gate and roadmap guard evidence',
        'backup and restore evidence',
        'teacher efficiency and privacy boundary sign-off',
        'release decision record and tag candidate plan'
    )
    failClosedRules = @(
        'Do not mark P006 complete from a preflight-only run.',
        'Do not create a release tag candidate without release decision evidence.',
        'Do not mark v0.1 release-ready while P001-P005 remain todo.'
    )
    boundary = 'release decision is not executed in this contract; keep P006 as todo until P005 closes and decision evidence is complete, and keep nextOpenP006 explicit while the onsite boundary is still open'
    rollback = 'revert tools/run-p006-release-decision-preflight-contract.ps1, tasks/backlog.csv, and remove the generated P006 admission report.'
}

$json = $report | ConvertTo-Json -Depth 8
Write-ContentIfChanged -Path $ReportPath -Content $json
$report | ConvertTo-Json -Depth 8

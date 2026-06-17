param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $LiveCloseoutPlanPath = 'tasks/live-pilot-closeout-plan.csv',
    [string] $ChecklistPath = 'docs/templates/p005-pilot-feedback-backlog-checklist.md',
    [string] $TriageTemplatePath = 'docs/templates/p005-pilot-feedback-triage-template.json',
    [string] $EvidencePath = 'docs/evidence/20260505-p005-pilot-feedback-backlog-preflight.md',
    [string] $ReportPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runDate = Get-Date -Format 'yyyyMMdd'

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = ('docs/evidence/{0}-p005-pilot-feedback-backlog-admission-report.json' -f $runDate)
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
$liveCloseoutPlanFullPath = Resolve-RepoPath $LiveCloseoutPlanPath
$checklistFullPath = Resolve-RepoPath $ChecklistPath
$triageTemplateFullPath = Resolve-RepoPath $TriageTemplatePath
$evidenceFullPath = Resolve-RepoPath $EvidencePath

Assert-True (Test-Path -LiteralPath $backlogFullPath) "P005 backlog file missing: $BacklogPath"
Assert-True (Test-Path -LiteralPath $liveCloseoutPlanFullPath) "live closeout plan missing: $LiveCloseoutPlanPath"
Assert-True (Test-Path -LiteralPath $checklistFullPath) "P005 checklist missing: $ChecklistPath"
Assert-True (Test-Path -LiteralPath $triageTemplateFullPath) "P005 triage template missing: $TriageTemplatePath"
Assert-True (Test-Path -LiteralPath $evidenceFullPath) "P005 evidence markdown missing: $EvidencePath"

$rows = Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8
$closeoutRows = @(Import-Csv -LiteralPath $liveCloseoutPlanFullPath -Encoding UTF8)
$byId = @{}
foreach ($row in $rows) { $byId[$row.id] = $row }

Assert-True ($closeoutRows.Count -eq 26) "live closeout plan row count drift: expected 26 actual $($closeoutRows.Count)"
$p005NextCloseout = @($closeoutRows | Where-Object { [string] $_.parent_id -eq 'P005' -and [string] $_.status -ne '已完成' } | Select-Object -First 1)
Assert-True ($p005NextCloseout.Count -eq 1) 'live closeout plan must expose next P005 slice'
Assert-True ([string] $p005NextCloseout[0].id -eq 'P005A') 'next P005 closeout slice must remain P005A before feedback triage closes'

foreach ($requiredTaskId in @('P004', 'P005')) {
    Assert-True ($byId.ContainsKey($requiredTaskId)) "P005 prerequisite task missing: $requiredTaskId"
}

$p004 = $byId['P004']
$p005 = $byId['P005']

Assert-True ($p005.depends_on -eq 'P004') 'P005 must depend on P004'
Assert-True ($p004.status -eq '待办') 'P004 still pending; P005 must stay todo before onsite round1 evidence closes'
Assert-True ($p005.status -eq '待办') 'P005 must remain todo until pilot feedback is transformed into backlog decisions'

$checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
foreach ($keyword in @('教师效率', '频率', '风险', '成本', '保留', '修改', '后置', '不做')) {
    Assert-True ($checklistText.Contains($keyword)) "P005 checklist missing keyword: $keyword"
}

$triageTemplate = Get-Content -LiteralPath $triageTemplateFullPath -Raw | ConvertFrom-Json
Assert-True ($triageTemplate.schemaVersion -eq 'p005-pilot-feedback-triage.v1') 'P005 triage template schema mismatch'
foreach ($requiredField in @('pilotContext', 'summary', 'referenceContext', 'impactedSurfaceIds', 'referencesReviewed', 'adoptionDecision', 'items', 'decisionNotes', 'signoff')) {
    Assert-True ($triageTemplate.PSObject.Properties.Name -contains $requiredField) "P005 triage template missing field: $requiredField"
}
Assert-True (@($triageTemplate.items).Count -ge 1) 'P005 triage template must contain at least one sample item'
Assert-True (@($triageTemplate.impactedSurfaceIds).Count -ge 1) 'P005 triage template must include impactedSurfaceIds'
Assert-True (@($triageTemplate.referencesReviewed).Count -ge 1) 'P005 triage template must include referencesReviewed'
foreach ($requiredReferenceContextField in @('referenceBasisPolicy', 'referenceRequirements', 'referenceModuleMap', 'guardEvidence')) {
    Assert-True ($triageTemplate.referenceContext.PSObject.Properties.Name -contains $requiredReferenceContextField) "P005 referenceContext missing field: $requiredReferenceContextField"
    Assert-True (-not [string]::IsNullOrWhiteSpace([string] $triageTemplate.referenceContext.$requiredReferenceContextField)) "P005 referenceContext field is blank: $requiredReferenceContextField"
}
foreach ($requiredAdoptionField in @('summary', 'adopted', 'rejected', 'followUpEvidence')) {
    Assert-True ($triageTemplate.adoptionDecision.PSObject.Properties.Name -contains $requiredAdoptionField) "P005 adoptionDecision missing field: $requiredAdoptionField"
}

$evidenceText = Get-Content -LiteralPath $evidenceFullPath -Raw
foreach ($keyword in @('preflight', 'P005', 'platform_na', 'gate_na', '试点反馈转 backlog', '下一步')) {
    Assert-True ($evidenceText.Contains($keyword)) "P005 evidence missing keyword: $keyword"
}

$report = [ordered]@{
    status = 'pass'
    taskId = 'P005'
    mode = 'preflight_only'
    checkedAt = (Get-Date).ToString('s')
    liveCloseoutPlanPath = $LiveCloseoutPlanPath
    p004Status = $p004.status
    p005Status = $p005.status
    closeTaskAllowed = $false
    currentDecision = 'keep_P005_todo_until_pilot_feedback_triage_evidence_close'
    checklistPath = $ChecklistPath
    triageTemplatePath = $TriageTemplatePath
    evidencePath = $EvidencePath
    reportPath = $ReportPath
    closeoutPlan = [ordered]@{
        rowCount = $closeoutRows.Count
        nextOpenP005 = [string] $p005NextCloseout[0].id
    }
    blockers = @(
        'P004 onsite pilot evidence is not closed.',
        'Feedback items are not classified by teacher efficiency, frequency, risk, and cost.',
        'Backlog decisions are not split into keep, modify, defer, and do-not-do categories.'
    )
    nextRequiredEvidence = @(
        'teacher pilot evidence from P004',
        'structured P005 triage template',
        'feedback item list with frequency and teacher-efficiency impact',
        'risk and cost scoring',
        'backlog triage decisions: keep, modify, defer, do_not_do'
    )
    failClosedRules = @(
        'Do not invent pilot feedback without P004 evidence.',
        'Do not modify roadmap/backlog from untriaged feedback.',
        'Do not advance P006 release decision until P005 triage is complete.'
    )
    boundary = 'pilot feedback triage is not executed in this contract; keep P005 as todo until P004 closes and backlog triage evidence is complete, and keep nextOpenP005 explicit while the onsite boundary is still open'
    rollback = 'revert tools/run-p005-pilot-feedback-backlog-preflight-contract.ps1, tasks/backlog.csv, and remove the generated P005 admission report.'
}

$json = $report | ConvertTo-Json -Depth 8
Write-ContentIfChanged -Path $ReportPath -Content $json
$report | ConvertTo-Json -Depth 8

param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/r003-interop-eval-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-r003-interop-eval-preflight.md',
    [string] $CompletionDashboardPath = 'tasks/completion-state-dashboard.csv',
    [string] $AutomationFirstPath = 'tasks/automation-first-contract.csv',
    [string] $ScopePath = 'docs/02_MVP_Scope_and_ScopeControl.md',
    [string] $TechnologyPath = 'docs/04_TechnologyStack.md',
    [string] $DomainModelPath = 'docs/05_DomainModel.md',
    [string] $R007ReportPath = 'docs/evidence/20260522-r007-interoperability-profile-map-admission-report.json',
    [string] $DecisionPath = 'docs/decisions/ADR-012-interoperability-eval-admission.md',
    [string] $ReportPath = 'docs/evidence/20260522-r003-interoperability-eval-admission-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Resolve-RepoPath([string] $Path) {
    return Join-Path $repoRoot ($Path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
}

function Read-JsonFile([string] $Path) {
    $fullPath = Resolve-RepoPath $Path
    Assert-True (Test-Path -LiteralPath $fullPath) "R003 required JSON evidence missing: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Write-ContentIfChanged([string] $Path, [string] $Content) {
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

$rows = Import-Csv -LiteralPath (Resolve-RepoPath $BacklogPath) -Encoding UTF8
$byId = @{}
foreach ($row in $rows) { $byId[$row.id] = $row }
foreach ($id in @('P006', 'R003', 'R007')) {
    Assert-True ($byId.ContainsKey($id)) "R003 prerequisite task missing: $id"
}

$p006 = $byId['P006']
$r003 = $byId['R003']
$r007 = $byId['R007']
Assert-True ($r003.depends_on -eq 'P006') 'R003 must depend on P006'
Assert-True ($p006.status -eq '待办') 'P006 still pending; R003 must remain todo before release decision closes'
Assert-True ($r003.status -eq '待办') 'R003 must remain todo until interoperability admission evidence is completed'
Assert-True ($r007.status -eq '待办') 'R007 must remain profile-map-only until real integration evidence exists'
Assert-True ($r003.acceptance -match 'QTI' -and $r003.acceptance -match 'CASE' -and $r003.acceptance -match 'OneRoster') 'R003 acceptance must name QTI/CASE/OneRoster admission boundary'

$checklist = Get-Content -LiteralPath (Resolve-RepoPath $ChecklistPath) -Raw
foreach ($keyword in @('QTI', 'CASE', 'OneRoster', 'Caliper', 'admission card', 'integration spike', 'field-difference report', 'privacy review', 'fail-closed')) {
    Assert-True ($checklist.Contains($keyword)) "R003 checklist missing keyword: $keyword"
}

$evidence = Get-Content -LiteralPath (Resolve-RepoPath $EvidencePath) -Raw
foreach ($keyword in @('preflight', 'R003', 'platform_na', 'gate_na', '标准互操作', '下一步', 'fail-closed')) {
    Assert-True ($evidence.Contains($keyword)) "R003 evidence missing keyword: $keyword"
}

$scope = Get-Content -LiteralPath (Resolve-RepoPath $ScopePath) -Raw
foreach ($keyword in @('完整标准互操作', '完整 QTI/CASE/OneRoster 实现', 'QTI', 'CASE', 'OneRoster', 'Caliper')) {
    Assert-True ($scope.Contains($keyword)) "R003 scope evidence missing keyword: $keyword"
}

$technology = Get-Content -LiteralPath (Resolve-RepoPath $TechnologyPath) -Raw
foreach ($keyword in @('参考标准预留', 'QTI', 'CASE', 'OneRoster', 'Caliper', 'profile map 优先', '没有真实对接需求前，不做完整标准实现')) {
    Assert-True ($technology.Contains($keyword)) "R003 technology evidence missing keyword: $keyword"
}

$domainModel = Get-Content -LiteralPath (Resolve-RepoPath $DomainModelPath) -Raw
foreach ($keyword in @('ScoreRecord', 'AnalysisReport', 'ReviewQueueItem', '互操作', 'QTI/CASE/OneRoster/Caliper')) {
    Assert-True ($domainModel.Contains($keyword)) "R003 domain model evidence missing keyword: $keyword"
}

$decision = Get-Content -LiteralPath (Resolve-RepoPath $DecisionPath) -Raw
foreach ($keyword in @('ADR-012', 'fail-closed', 'R007 profile map', 'QTI import/export', 'CASE', 'OneRoster', 'Caliper', 'rollback/disable switch')) {
    Assert-True ($decision.Contains($keyword)) "R003 ADR missing keyword: $keyword"
}

$dashboardRows = Import-Csv -LiteralPath (Resolve-RepoPath $CompletionDashboardPath) -Encoding UTF8
$dashboardByArea = @{}
foreach ($row in $dashboardRows) { $dashboardByArea[$row.area_id] = $row }
foreach ($areaId in @('advanced-platform', 'score-import', 'analysis-report')) {
    Assert-True ($dashboardByArea.ContainsKey($areaId)) "completion dashboard missing area: $areaId"
}
$advancedPlatform = $dashboardByArea['advanced-platform']
$scoreImport = $dashboardByArea['score-import']
$analysisReport = $dashboardByArea['analysis-report']
Assert-True ($advancedPlatform.usable_today -eq '不可使用') 'advanced-platform must remain unavailable'
Assert-True ($advancedPlatform.blocking_gap -match '真实瓶颈|发布后证据') 'advanced-platform must keep real-evidence blocker'
Assert-True ($scoreImport.blocking_gap -match 'P001') 'score-import must keep P001 privacy workflow blocker'
Assert-True ($analysisReport.blocking_gap -match 'P001') 'analysis-report must keep P001 production-history blocker'

$automationRows = Import-Csv -LiteralPath (Resolve-RepoPath $AutomationFirstPath) -Encoding UTF8
$automationById = @{}
foreach ($row in $automationRows) { $automationById[$row.task_id] = $row }
Assert-True ($automationById.ContainsKey('R003')) 'automation-first contract missing R003 row'
$r003Automation = $automationById['R003']
Assert-True ($r003Automation.deterministic_precheck -match 'profile map|demand source|field mapping') 'R003 automation-first deterministic precheck must require profile map, demand source, and field mapping checks'
Assert-True ($r003Automation.exception_policy -match 'real integration need') 'R003 automation-first exception policy must block standard implementation without real integration need'

$r007Report = Read-JsonFile $R007ReportPath
Assert-True ($r007Report.status -eq 'pass') 'R007 profile map admission report must pass before R003 can cite it'
Assert-True ($r007Report.closeTaskAllowed -eq $false) 'R007 must remain not closeable'
Assert-True (@($r007Report.profileMap).Count -ge 5) 'R007 profile map must cover core external profiles'
Assert-True (($r007Report.admissionMatrix | Where-Object { $_.standard -eq 'QTI' -and $_.currentDecision -eq 'profile_map_only' }).Count -gt 0) 'R007 must keep QTI profile_map_only'
Assert-True (($r007Report.admissionMatrix | Where-Object { $_.standard -eq 'OneRoster' -and $_.currentDecision -match 'blocked' }).Count -gt 0) 'R007 must block OneRoster until authorized need'

$admissionMatrix = @(
    [ordered]@{
        standard = 'QTI'
        currentDecision = 'profile_map_only'
        currentEvidence = 'R007 maps QuestionItem/Paper surfaces to QTI item/test profiles, but no authorized package, conformance target, field-difference report, or round-trip proof exists.'
        allowedAction = 'profile map, lossy-field notes, adapter/view-model sketch, and dry-run preview design.'
        blockedAction = 'QTI import/export implementation, certification claim, or direct mutation of internal QuestionItem/Paper models.'
    }
    [ordered]@{
        standard = 'CASE'
        currentDecision = 'profile_map_only'
        currentEvidence = 'R007 maps KnowledgeNode/KnowledgeMapping to CASE profile, while C002 active remains the internal ontology fact source.'
        allowedAction = 'read-only external framework mapping and loss/risk notes.'
        blockedAction = 'CASE sync, treating external standards as ontology trunk, or bypassing C002R version/mapping review.'
    }
    [ordered]@{
        standard = 'OneRoster'
        currentDecision = 'blocked_until_authorized_need'
        currentEvidence = 'ScoreRecord/ItemScore mapping is high privacy risk; no SIS, authorized sample, roster owner, or P001/P006 release evidence exists.'
        allowedAction = 'field-risk mapping and privacy checklist only.'
        blockedAction = 'SIS sync, real roster import/export, student identifier export, or formal score exchange.'
    }
    [ordered]@{
        standard = 'Caliper'
        currentDecision = 'conceptual_only'
        currentEvidence = 'AnalysisReport exists as report output, but no persisted AnalysisEvent stream or privacy admission exists.'
        allowedAction = 'conceptual event profile and privacy-risk notes.'
        blockedAction = 'real-time event stream, student behavior export, or analytics event schema migration.'
    }
)

$blockers = @(
    'R003 remains todo because P006 release decision is not closed.',
    'R007 profile map exists but is explicitly profile-only and not closeable.',
    'No real third-party integration demand source, authorized sample package, conformance target, or adapter owner exists.',
    'No field-difference, lossy round-trip, privacy, dry-run preview, or rollback/disable-switch evidence exists.',
    'OneRoster and Caliper remain high privacy risk because P001/P006 and real data authorization are not complete.'
)

$report = [ordered]@{
    status = 'pass'
    taskId = 'R003'
    mode = 'admission_preflight'
    checkedAt = (Get-Date).ToString('s')
    p006Status = $p006.status
    r003Status = $r003.status
    r007Status = $r007.status
    closeTaskAllowed = $false
    currentDecision = 'keep_R003_todo_use_R007_profile_map_only_fail_closed'
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    referencedEvidence = [ordered]@{
        scope = $ScopePath
        technology = $TechnologyPath
        domainModel = $DomainModelPath
        r007ProfileMapReport = $R007ReportPath
        completionDashboard = $CompletionDashboardPath
        automationFirstContract = $AutomationFirstPath
        decision = $DecisionPath
    }
    currentBaseline = [ordered]@{
        r007ProfileMapCount = @($r007Report.profileMap).Count
        r007CloseTaskAllowed = [bool] $r007Report.closeTaskAllowed
        advancedPlatformUsableToday = [string] $advancedPlatform.usable_today
        scoreImportCurrentState = [string] $scoreImport.current_state
        analysisReportCurrentState = [string] $analysisReport.current_state
        standardsCovered = @('QTI', 'CASE', 'OneRoster', 'Caliper')
    }
    admissionMatrix = $admissionMatrix
    blockers = $blockers
    nextRequiredEvidence = @(
        'P006 release decision record',
        'real third-party integration demand source',
        'authorized sample package and conformance target',
        'field-difference and lossy round-trip report',
        'privacy review for student/score/analytics data',
        'adapter owner, import/export dry-run preview, review UI, rollback/disable switch'
    )
    boundary = 'R003 only refreshes interoperability evaluation admission evidence and ADR-012; it performs no QTI/CASE/OneRoster/Caliper import/export, no SIS sync, no event-stream write, no schema mutation, no production write, and no release-state transition.'
    rollback = 'revert tools/run-r003-interop-eval-preflight-contract.ps1, docs/templates/r003-interop-eval-checklist.md, docs/decisions/ADR-012-interoperability-eval-admission.md, tasks/backlog.csv, and remove the generated R003 admission report.'
}

$json = $report | ConvertTo-Json -Depth 10
Write-ContentIfChanged -Path $ReportPath -Content $json
$report | ConvertTo-Json -Depth 10

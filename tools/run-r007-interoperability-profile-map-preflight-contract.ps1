param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/r007-interoperability-profile-map-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-r007-interoperability-profile-map-preflight.md',
    [string] $CompletionDashboardPath = 'tasks/completion-state-dashboard.csv',
    [string] $AutomationFirstPath = 'tasks/automation-first-contract.csv',
    [string] $ScopePath = 'docs/02_MVP_Scope_and_ScopeControl.md',
    [string] $TechnologyPath = 'docs/04_TechnologyStack.md',
    [string] $DomainModelPath = 'docs/05_DomainModel.md',
    [string] $DomainEntitiesPath = 'apps/api/Domain/P0Entities.cs',
    [string] $DbContextPath = 'apps/api/Data/KqgDbContext.cs',
    [string] $P001ReportPath = 'docs/evidence/20260518-p001-live-pilot-readiness-preflight-report.json',
    [string] $DecisionPath = 'docs/decisions/ADR-009-interoperability-profile-map-admission.md',
    [string] $ReportPath = 'docs/evidence/20260522-r007-interoperability-profile-map-admission-report.json'
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
    Assert-True (Test-Path -LiteralPath $fullPath) "R007 required JSON evidence missing: $Path"
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
foreach ($id in @('P001', 'P006', 'R003', 'R007')) {
    Assert-True ($byId.ContainsKey($id)) "R007 prerequisite task missing: $id"
}

$p001 = $byId['P001']
$p006 = $byId['P006']
$r003 = $byId['R003']
$r007 = $byId['R007']
Assert-True ($r007.depends_on -eq 'P006') 'R007 must depend on P006'
Assert-True ($p001.status -eq '待办') 'P001 still pending; R007 must not skip live release evidence'
Assert-True ($p006.status -eq '待办') 'P006 still pending; R007 must remain todo before release decision closes'
Assert-True ($r003.status -eq '待办') 'R003 standard interop evaluation must remain todo without real integration demand'
Assert-True ($r007.status -eq '待办') 'R007 must remain todo until interoperability profile map evidence is completed'
Assert-True ($r007.acceptance -match 'QuestionItem' -and $r007.acceptance -match 'QTI' -and $r007.acceptance -match 'OneRoster' -and $r007.acceptance -match 'Caliper') 'R007 acceptance must require internal-to-standard profile mapping'

$checklist = Get-Content -LiteralPath (Resolve-RepoPath $ChecklistPath) -Raw
foreach ($keyword in @('QuestionItem', 'QTI', 'CASE', 'OneRoster', 'Caliper', 'profile map', 'round-trip risk', 'adapter owner', 'fail-closed')) {
    Assert-True ($checklist.Contains($keyword)) "R007 checklist missing keyword: $keyword"
}

$evidence = Get-Content -LiteralPath (Resolve-RepoPath $EvidencePath) -Raw
foreach ($keyword in @('preflight', 'R007', 'platform_na', 'gate_na', 'interoperability profile map', '下一步')) {
    Assert-True ($evidence.Contains($keyword)) "R007 evidence missing keyword: $keyword"
}

$scope = Get-Content -LiteralPath (Resolve-RepoPath $ScopePath) -Raw
foreach ($keyword in @('完整 QTI 导入导出和认证', '把课标当成本体主干', '对接 SIS 或正式同步', '建实时学习事件流')) {
    Assert-True ($scope.Contains($keyword)) "R007 scope boundary missing keyword: $keyword"
}

$technology = Get-Content -LiteralPath (Resolve-RepoPath $TechnologyPath) -Raw
foreach ($keyword in @('profile map 优先', '不做完整标准实现', 'QuestionItem', 'ScoreRecord', 'AnalysisEvent')) {
    Assert-True ($technology.Contains($keyword)) "R007 technology evidence missing keyword: $keyword"
}

$domainModel = Get-Content -LiteralPath (Resolve-RepoPath $DomainModelPath) -Raw
foreach ($keyword in @('QuestionItem', 'KnowledgeNode', 'Paper', 'ScoreRecord', 'AnalysisReport', '互操作')) {
    Assert-True ($domainModel.Contains($keyword)) "R007 domain model evidence missing keyword: $keyword"
}

$domainEntities = Get-Content -LiteralPath (Resolve-RepoPath $DomainEntitiesPath) -Raw
foreach ($keyword in @('public sealed class QuestionItem', 'public sealed class KnowledgeNode', 'public sealed class ScoreRecord', 'public sealed class ItemScore', 'public sealed class PaperBasket', 'public sealed class PaperBasketItem')) {
    Assert-True ($domainEntities.Contains($keyword)) "R007 domain entity missing keyword: $keyword"
}

$dbContext = Get-Content -LiteralPath (Resolve-RepoPath $DbContextPath) -Raw
foreach ($keyword in @('DbSet<ScoreRecord>', 'DbSet<QuestionItem>', 'DbSet<KnowledgeNode>', 'DbSet<PaperBasket>', 'DbSet<PaperBasketItem>')) {
    Assert-True ($dbContext.Contains($keyword)) "R007 DbContext missing keyword: $keyword"
}

$decision = Get-Content -LiteralPath (Resolve-RepoPath $DecisionPath) -Raw
foreach ($keyword in @('ADR-009', 'fail-closed', 'adapter/view model', 'QTI import/export', 'OneRoster SIS', 'Caliper', 'rollback/disable switch')) {
    Assert-True ($decision.Contains($keyword)) "R007 ADR missing keyword: $keyword"
}

$dashboardRows = Import-Csv -LiteralPath (Resolve-RepoPath $CompletionDashboardPath) -Encoding UTF8
$dashboardByArea = @{}
foreach ($row in $dashboardRows) { $dashboardByArea[$row.area_id] = $row }
Assert-True ($dashboardByArea.ContainsKey('advanced-platform')) 'completion dashboard missing advanced-platform area'
$advancedDashboard = $dashboardByArea['advanced-platform']
Assert-True ($advancedDashboard.current_state -eq 'contract_done') 'advanced-platform must stay contract_done'
Assert-True ($advancedDashboard.usable_today -eq '不可使用') 'advanced-platform must remain unavailable before real post-release evidence'

$automationRows = Import-Csv -LiteralPath (Resolve-RepoPath $AutomationFirstPath) -Encoding UTF8
$automationById = @{}
foreach ($row in $automationRows) { $automationById[$row.task_id] = $row }
Assert-True ($automationById.ContainsKey('R007')) 'automation-first contract missing R007 row'
$r007Automation = $automationById['R007']
Assert-True ($r007Automation.deterministic_precheck -match 'QuestionItem|Paper|KnowledgeNode|ScoreRecord|AnalysisEvent') 'R007 automation-first deterministic precheck must include internal model mapping checks'
Assert-True ($r007Automation.exception_policy -match 'import/export spike before profile map blocks task') 'R007 automation-first exception policy must block spike before profile map'

$p001Report = Read-JsonFile $P001ReportPath
Assert-True ($p001Report.status -eq 'pass') 'P001 preflight report must pass before R007 can cite release readiness boundary'
Assert-True ($p001Report.p001CanClose -eq $false) 'P001 must not be closeable without isolated-machine proof'

$profileMap = @(
    [ordered]@{
        internalModel = 'QuestionItem + QuestionBlock + QuestionAsset + SourceRegion'
        externalProfile = 'QTI item'
        currentStatus = 'internal_model_available_profile_only'
        keyFields = @('Id', 'Subject', 'Stage', 'QuestionType', 'DefaultScore', 'DifficultyEstimated', 'Status', 'PrimaryKnowledgeId', 'Blocks', 'CustomFields', 'QualitySignals')
        requiredAdapterFields = @('item identifier', 'prompt/body', 'choices/subquestions', 'response declaration', 'correct response', 'rubric/score', 'media assets', 'source evidence')
        privacyRisk = 'low for public/synthetic questions; copyright/source restrictions must be preserved'
        roundTripRisk = 'medium: formulas, tables, source screenshots, and review status may be lossy in generic QTI'
        decision = 'profile_only_no_import_export'
    }
    [ordered]@{
        internalModel = 'PaperBasket + PaperBasketItem + PaperBlueprintReview'
        externalProfile = 'QTI test'
        currentStatus = 'internal_model_available_profile_only'
        keyFields = @('PaperBasket.Id', 'Title', 'Subject', 'Stage', 'Status', 'Structure', 'PaperBasketItem.QuestionNo', 'Score', 'SortOrder', 'Snapshot')
        requiredAdapterFields = @('test identifier', 'sections', 'item references', 'ordering', 'score weights', 'blueprint/review metadata')
        privacyRisk = 'low for paper structure; source/license restrictions inherited from items'
        roundTripRisk = 'medium: local blueprint review and replacement history are adapter metadata, not core QTI'
        decision = 'profile_only_no_export_spike'
    }
    [ordered]@{
        internalModel = 'KnowledgeNode + KnowledgeEdge + KnowledgeMapping'
        externalProfile = 'CASE framework/competency'
        currentStatus = 'internal_model_available_profile_only'
        keyFields = @('Code', 'Title', 'NodeType', 'Level', 'Status', 'Version', 'ParentId', 'QuestionItemId', 'KnowledgeNodeId')
        requiredAdapterFields = @('competency identifier', 'framework identifier', 'parent relation', 'association type', 'version/status', 'source provenance')
        privacyRisk = 'low; source curriculum license and local active/candidate status must be preserved'
        roundTripRisk = 'high if CASE is treated as authoritative ontology instead of mapped external profile'
        decision = 'profile_only_no_case_sync'
    }
    [ordered]@{
        internalModel = 'ScoreRecord + ItemScore'
        externalProfile = 'OneRoster result'
        currentStatus = 'internal_model_available_profile_only'
        keyFields = @('AssessmentId', 'StudentId', 'ImportBatchId', 'StudentKey', 'TotalScore', 'MaxScore', 'SyntheticFixture', 'ContainsStudentPii', 'QuestionNo', 'Score')
        requiredAdapterFields = @('user/sourcedId', 'class/assessment line item', 'result value', 'score scale', 'status', 'import batch')
        privacyRisk = 'high: student identity, class, score and education record boundaries require N001/P001 authorization'
        roundTripRisk = 'high: student identifiers and local anonymization policy may not round-trip safely'
        decision = 'blocked_until_real_authorized_integration_need'
    }
    [ordered]@{
        internalModel = 'AnalysisReport / AnalysisEvent conceptual profile'
        externalProfile = 'Caliper analytics event'
        currentStatus = 'conceptual_only_not_persisted_as_event_stream'
        keyFields = @('analysis status', 'knowledge mastery summary', 'commentary report reference', 'AIJob/FeedbackEvent provenance when available')
        requiredAdapterFields = @('actor', 'action', 'object', 'generated event time', 'edApp', 'federated session/context')
        privacyRisk = 'high: analytics events can reconstruct student behavior or score history'
        roundTripRisk = 'high: no persisted AnalysisEvent stream exists; exporting would imply unsupported semantics'
        decision = 'blocked_until_event_model_and_privacy_admission'
    }
)

$admissionMatrix = @(
    [ordered]@{
        standard = 'QTI'
        currentDecision = 'profile_map_only'
        allowedAction = 'item/test field mapping and lossy-field report'
        blockedAction = 'QTI import/export implementation or certification claim'
    }
    [ordered]@{
        standard = 'CASE'
        currentDecision = 'profile_map_only'
        allowedAction = 'KnowledgeNode/KnowledgeMapping external profile mapping'
        blockedAction = 'CASE sync or treating curriculum standard as internal ontology trunk'
    }
    [ordered]@{
        standard = 'OneRoster'
        currentDecision = 'blocked_until_authorized_need'
        allowedAction = 'ScoreRecord/ItemScore field-risk mapping'
        blockedAction = 'SIS sync, real student export, or formal roster import'
    }
    [ordered]@{
        standard = 'Caliper'
        currentDecision = 'conceptual_only'
        allowedAction = 'AnalysisReport/AnalysisEvent conceptual map'
        blockedAction = 'real-time learning event stream or student behavior export'
    }
)

$blockers = @(
    'R007 remains todo because P006 release decision is not closed.',
    'R003 interop evaluation remains todo because no real third-party integration demand exists.',
    'No authorized third-party sample package or field-difference report exists.',
    'No adapter owner, import/export dry-run preview, privacy review, or rollback/disable switch exists.',
    'AnalysisEvent is conceptual only; no persisted event stream exists.'
)

$report = [ordered]@{
    status = 'pass'
    taskId = 'R007'
    mode = 'profile_map_admission_preflight'
    checkedAt = (Get-Date).ToString('s')
    p001Status = $p001.status
    p006Status = $p006.status
    r003Status = $r003.status
    r007Status = $r007.status
    closeTaskAllowed = $false
    currentDecision = 'keep_R007_todo_profile_map_only_fail_closed'
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    referencedEvidence = [ordered]@{
        scope = $ScopePath
        technology = $TechnologyPath
        domainModel = $DomainModelPath
        domainEntities = $DomainEntitiesPath
        dbContext = $DbContextPath
        p001Report = $P001ReportPath
        completionDashboard = $CompletionDashboardPath
        automationFirstContract = $AutomationFirstPath
        decision = $DecisionPath
    }
    profileMap = $profileMap
    admissionMatrix = $admissionMatrix
    blockers = $blockers
    nextRequiredEvidence = @(
        'P006 release decision record',
        'real third-party integration demand source',
        'authorized sample package for target standard/system',
        'field difference and lossy-field report',
        'privacy review for student/score/analytics data',
        'adapter owner, dry-run preview, review UI, rollback/disable switch'
    )
    boundary = 'R007 only refreshes interoperability profile map admission evidence and ADR-009; it performs no QTI/CASE/OneRoster/Caliper import or export, no SIS sync, no event-stream write, no schema mutation, and no release-state transition.'
    rollback = 'revert tools/run-r007-interoperability-profile-map-preflight-contract.ps1, docs/templates/r007-interoperability-profile-map-checklist.md, docs/decisions/ADR-009-interoperability-profile-map-admission.md, tasks/backlog.csv, and remove the generated R007 admission report.'
}

$json = $report | ConvertTo-Json -Depth 10
Write-ContentIfChanged -Path $ReportPath -Content $json
$report | ConvertTo-Json -Depth 10

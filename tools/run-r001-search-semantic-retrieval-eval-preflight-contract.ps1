param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/r001-search-semantic-retrieval-eval-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-r001-search-semantic-retrieval-eval-preflight.md',
    [string] $CompletionDashboardPath = 'tasks/completion-state-dashboard.csv',
    [string] $AutomationFirstPath = 'tasks/automation-first-contract.csv',
    [string] $ArchitecturePath = 'docs/03_Architecture.md',
    [string] $TechnologyPath = 'docs/04_TechnologyStack.md',
    [string] $S008ReportPath = 'docs/evidence/20260506-s008a-question-search-productization-smoke-report.json',
    [string] $K001ReportPath = 'docs/evidence/k001-active-c002-production-query-report.json',
    [string] $Real012ReportPath = 'docs/evidence/20260518-real012-production-flow-quality-report.json',
    [string] $HostCapabilityPath = 'docs/evidence/o002-host-capability-diagnostic-report.json',
    [string] $DecisionPath = 'docs/decisions/ADR-010-search-semantic-retrieval-admission.md',
    [string] $ReportPath = ''
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
    Assert-True (Test-Path -LiteralPath $fullPath) "R001 required JSON evidence missing: $Path"
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

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = ('docs/evidence/{0}-r001-search-semantic-retrieval-admission-report.json' -f (Get-Date -Format 'yyyyMMdd'))
}

$rows = Import-Csv -LiteralPath (Resolve-RepoPath $BacklogPath) -Encoding UTF8
$byId = @{}
foreach ($row in $rows) { $byId[$row.id] = $row }
foreach ($id in @('P001', 'P006', 'R001')) {
    Assert-True ($byId.ContainsKey($id)) "R001 prerequisite task missing: $id"
}

$p001 = $byId['P001']
$p006 = $byId['P006']
$r001 = $byId['R001']
Assert-True ($r001.depends_on -eq 'P006') 'R001 must depend on P006'
Assert-True ($p001.status -eq '待办') 'P001 still pending; R001 must not skip live pilot evidence'
Assert-True ($p006.status -eq '待办') 'P006 still pending; R001 must remain todo before release decision closes'
Assert-True ($r001.status -eq '待办') 'R001 must remain todo until FTS benchmark + ADR evidence is completed'
Assert-True ($r001.acceptance -match 'PostgreSQL FTS' -and $r001.acceptance -match 'pgvector' -and $r001.acceptance -match '外部搜索') 'R001 acceptance must require FTS insufficiency before pgvector/external search'

$checklist = Get-Content -LiteralPath (Resolve-RepoPath $ChecklistPath) -Raw
foreach ($keyword in @('PostgreSQL FTS', 'pgvector', 'benchmark report', 'ADR', 'latency p50/p95', 'miss case', 'rollback', 'fail-closed')) {
    Assert-True ($checklist.Contains($keyword)) "R001 checklist missing keyword: $keyword"
}

$evidence = Get-Content -LiteralPath (Resolve-RepoPath $EvidencePath) -Raw
foreach ($keyword in @('preflight', 'R001', 'platform_na', 'gate_na', '语义检索', '下一步', 'fail-closed')) {
    Assert-True ($evidence.Contains($keyword)) "R001 evidence missing keyword: $keyword"
}

$architecture = Get-Content -LiteralPath (Resolve-RepoPath $ArchitecturePath) -Raw
foreach ($keyword in @('全文检索', 'pgvector', 'PostgreSQL 表结构、JSONB、FTS、pgvector')) {
    Assert-True ($architecture.Contains($keyword)) "R001 architecture evidence missing keyword: $keyword"
}

$technology = Get-Content -LiteralPath (Resolve-RepoPath $TechnologyPath) -Raw
foreach ($keyword in @('PostgreSQL FTS + `pg_trgm` first', 'pgvector 后置', '无 benchmark 不引入外部搜索引擎')) {
    Assert-True ($technology.Contains($keyword)) "R001 technology evidence missing keyword: $keyword"
}

$decision = Get-Content -LiteralPath (Resolve-RepoPath $DecisionPath) -Raw
foreach ($keyword in @('ADR-010', 'fail-closed', 'PostgreSQL FTS', 'pg_trgm', 'pgvector migration', 'rollback/disable switch')) {
    Assert-True ($decision.Contains($keyword)) "R001 ADR missing keyword: $keyword"
}

$dashboardRows = Import-Csv -LiteralPath (Resolve-RepoPath $CompletionDashboardPath) -Encoding UTF8
$dashboardByArea = @{}
foreach ($row in $dashboardRows) { $dashboardByArea[$row.area_id] = $row }
foreach ($areaId in @('question-search', 'advanced-platform')) {
    Assert-True ($dashboardByArea.ContainsKey($areaId)) "completion dashboard missing area: $areaId"
}
$questionSearch = $dashboardByArea['question-search']
$advancedPlatform = $dashboardByArea['advanced-platform']
Assert-True ($questionSearch.current_state -eq 'teacher_validated') 'question-search must stay teacher_validated'
Assert-True ($questionSearch.blocking_gap -match 'P001') 'question-search must keep P001 field performance/access boundary'
Assert-True ($advancedPlatform.usable_today -eq '不可使用') 'advanced-platform must remain unavailable before real bottleneck evidence'

$automationRows = Import-Csv -LiteralPath (Resolve-RepoPath $AutomationFirstPath) -Encoding UTF8
$automationById = @{}
foreach ($row in $automationRows) { $automationById[$row.task_id] = $row }
Assert-True ($automationById.ContainsKey('R001')) 'automation-first contract missing R001 row'
$r001Automation = $automationById['R001']
Assert-True ($r001Automation.deterministic_precheck -match 'FTS|latency|miss case|baseline') 'R001 automation-first deterministic precheck must include FTS latency/miss/baseline checks'
Assert-True ($r001Automation.exception_policy -match 'pgvector|external search|benchmark') 'R001 automation-first exception policy must block pgvector/external search without benchmark'

$s008 = Read-JsonFile $S008ReportPath
Assert-True ($s008.status -eq 'pass') 'S008A question search report must pass before R001 can cite current search baseline'
Assert-True ($s008.defaultKnowledge.status -eq 'active') 'S008A search must default to active knowledge'
Assert-True ($s008.cardFlags.hasFormula -eq $true -and $s008.cardFlags.hasTable -eq $true -and $s008.cardFlags.hasImage -eq $true) 'S008A question cards must expose formula/table/image flags'

$k001 = Read-JsonFile $K001ReportPath
Assert-True ($k001.status -eq 'pass') 'K001 active query report must pass before R001 can cite active C002 baseline'
Assert-True ($k001.querySurfaces.questionSearch.filtersUseActiveAssetsByDefault -eq $true) 'K001 question search must use active assets by default'
Assert-True ($k001.querySurfaces.questionSearch.candidateAssetsExcludedByDefault -eq $true) 'K001 question search must exclude candidate assets by default'
Assert-True ($k001.compatibility.doesNotMutateActiveAssets -eq $true) 'K001 must not mutate active assets'

$real012 = Read-JsonFile $Real012ReportPath
Assert-True ($real012.status -eq 'pass') 'REAL012 report must pass before R001 can cite real-question search smoke'
Assert-True ($real012.searchProbe.total -ge 3) 'REAL012 search probe must return real questions'
Assert-True ($real012.searchProbe.sortBy -eq 'question_no') 'REAL012 search probe must preserve question number sorting'
Assert-True ($real012.searchProbe.hasImageCount -ge 3) 'REAL012 search probe must include image-backed question cards'
Assert-True ($real012.real005ClosureStatus -eq 'not_closed') 'REAL012 must keep full real-paper closure not_closed'

$hostCapability = Read-JsonFile $HostCapabilityPath
Assert-True ($hostCapability.recommendedProfiles.searchProfile.status -eq 'postgresql_first') 'host capability search profile must be PostgreSQL first'
Assert-True ($hostCapability.recommendedProfiles.searchProfile.recommended -eq 'postgresql_fts_pg_trgm_first_pgvector_only_after_eval') 'host capability must keep pgvector after eval'

$admissionMatrix = @(
    [ordered]@{
        searchKind = 'postgresql_fts_pg_trgm'
        currentDecision = 'current_default'
        currentEvidence = 'S008A/K001/REAL012 prove active C002 question search and sampled real-question ordered search; P001 still needs field performance/access review.'
        allowedAction = 'maintain current search API, collect query logs, and design benchmark.'
        failClosedRule = '不得把非现场 smoke 当现场性能验收。'
    }
    [ordered]@{
        searchKind = 'pgvector_semantic_search'
        currentDecision = 'blocked_until_benchmark'
        currentEvidence = 'no FTS miss-case corpus, latency p95 breach, extension evidence, embedding model/cost/cache/privacy plan, or index rebuild script.'
        requiredBeforeAdmission = @('FTS miss-case corpus', 'latency p50/p95 baseline', 'pgvector extension evidence', 'embedding model card', 'privacy/cache/delete policy', 'index rebuild plan', 'disable switch')
        failClosedRule = '不得新增 pgvector migration、embedding table、default semantic route 或教师可见语义检索承诺。'
    }
    [ordered]@{
        searchKind = 'external_search_engine'
        currentDecision = 'blocked'
        currentEvidence = 'no operational search bottleneck, external index rebuild plan, permission filter proof, backup/restore plan, or ops owner.'
        requiredBeforeAdmission = @('real bottleneck evidence', 'fact-source rebuild strategy', 'permission filter contract', 'backup/restore drill', 'ops owner', 'rollback plan')
        failClosedRule = '不得引入独立搜索服务或外部搜索依赖作为 v0.1 默认路径。'
    }
)

$blockers = @(
    'R001 remains todo because P006 release decision is not closed.',
    'P001 field performance and access review is still pending.',
    'No FTS miss-case corpus, latency p50/p95 benchmark, or teacher search-time baseline exists.',
    'No pgvector extension evidence, embedding model/cost/cache/privacy plan, index rebuild plan, or disable switch exists.',
    'No external search operations owner, permission-filter contract, or rebuild/backup evidence exists.'
)

$report = [ordered]@{
    status = 'pass'
    taskId = 'R001'
    mode = 'admission_preflight'
    checkedAt = (Get-Date).ToString('s')
    p001Status = $p001.status
    p006Status = $p006.status
    r001Status = $r001.status
    closeTaskAllowed = $false
    currentDecision = 'keep_R001_todo_postgresql_first_fail_closed'
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    referencedEvidence = [ordered]@{
        architecture = $ArchitecturePath
        technology = $TechnologyPath
        s008Report = $S008ReportPath
        k001Report = $K001ReportPath
        real012Report = $Real012ReportPath
        hostCapability = $HostCapabilityPath
        completionDashboard = $CompletionDashboardPath
        automationFirstContract = $AutomationFirstPath
        decision = $DecisionPath
    }
    currentBaseline = [ordered]@{
        searchProfile = [string] $hostCapability.recommendedProfiles.searchProfile.recommended
        activeKnowledgeStatus = [string] $s008.defaultKnowledge.status
        activeKnowledgeVersion = [int] $s008.defaultKnowledge.version
        filtersUseActiveAssetsByDefault = [bool] $k001.querySurfaces.questionSearch.filtersUseActiveAssetsByDefault
        candidateAssetsExcludedByDefault = [bool] $k001.querySurfaces.questionSearch.candidateAssetsExcludedByDefault
        real012SearchTotal = [int] $real012.searchProbe.total
        real012SortBy = [string] $real012.searchProbe.sortBy
        real012HasImageCount = [int] $real012.searchProbe.hasImageCount
        real005ClosureStatus = [string] $real012.real005ClosureStatus
    }
    admissionMatrix = $admissionMatrix
    blockers = $blockers
    nextRequiredEvidence = @(
        'P006 release decision record',
        'field search benchmark with real teacher query set',
        'FTS miss-case corpus and latency p50/p95 report',
        'teacher search-time baseline and improvement target',
        'pgvector extension and embedding privacy/cost/cache/delete plan',
        'index rebuild and rollback/disable switch evidence'
    )
    boundary = 'R001 only refreshes search/semantic retrieval admission evidence and ADR-010; it performs no pgvector migration, no embedding generation, no external search setup, no query route mutation, no production write, and no release-state transition.'
    rollback = 'revert tools/run-r001-search-semantic-retrieval-eval-preflight-contract.ps1, docs/templates/r001-search-semantic-retrieval-eval-checklist.md, docs/decisions/ADR-010-search-semantic-retrieval-admission.md, tasks/backlog.csv, and remove the generated R001 admission report.'
}

$json = $report | ConvertTo-Json -Depth 10
Write-ContentIfChanged -Path $ReportPath -Content $json
$report | ConvertTo-Json -Depth 10

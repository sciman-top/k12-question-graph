param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/r006-techdebt-cadence-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-r006-techdebt-cadence-preflight.md',
    [string] $CompletionDashboardPath = 'tasks/completion-state-dashboard.csv',
    [string] $AutomationFirstPath = 'tasks/automation-first-contract.csv',
    [string] $GatesPath = 'tools/run-gates.ps1',
    [string] $RoadmapGuardPath = 'tools/run-roadmap-guard.ps1',
    [string] $G002ReportPath = 'docs/evidence/g002-storage-cleanup-report.json',
    [string] $O005ReportPath = 'docs/evidence/o005-capacity-cost-health-dashboard-report.json',
    [string] $O008ReportPath = 'docs/evidence/technology-refresh-report.json',
    [string] $P001ReportPath = '',
    [string] $DecisionPath = 'docs/decisions/ADR-008-techdebt-cadence-admission.md',
    [string] $ReportPath = 'docs/evidence/20260522-r006-techdebt-cadence-admission-report.json'
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
    Assert-True (Test-Path -LiteralPath $fullPath) "R006 required JSON evidence missing: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}
function Resolve-LatestEvidencePath([string] $Filter) {
    $evidenceRoot = Resolve-RepoPath 'docs/evidence'
    Assert-True (Test-Path -LiteralPath $evidenceRoot) 'R006 missing docs/evidence directory'
    $latest = @(Get-ChildItem -LiteralPath $evidenceRoot -Filter $Filter -File | Sort-Object Name -Descending | Select-Object -First 1)
    Assert-True ($latest.Count -eq 1) "R006 missing evidence matching filter: $Filter"
    return [System.IO.Path]::GetRelativePath($repoRoot, $latest[0].FullName).Replace('\', '/')
}

if ([string]::IsNullOrWhiteSpace($P001ReportPath)) {
    $P001ReportPath = Resolve-LatestEvidencePath '*-p001-live-pilot-readiness-preflight-report.json'
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
foreach ($id in @('P001', 'P006', 'R006')) {
    Assert-True ($byId.ContainsKey($id)) "R006 prerequisite task missing: $id"
}

$p001 = $byId['P001']
$p006 = $byId['P006']
$r006 = $byId['R006']
Assert-True ($r006.depends_on -eq 'P006') 'R006 must depend on P006'
Assert-True ($p001.status -eq '待办') 'P001 still pending; R006 must not skip isolated-machine pilot evidence'
Assert-True ($p006.status -eq '待办') 'P006 still pending; R006 must remain todo before release decision closes'
Assert-True ($r006.status -eq '待办') 'R006 must remain todo until quality dashboard/dependency gate cadence evidence is completed'
Assert-True ($r006.acceptance -match '门禁维护' -and $r006.acceptance -match '依赖升级' -and $r006.acceptance -match '性能基线' -and $r006.acceptance -match '删除无效实验') 'R006 acceptance must require gate/dependency/performance/stale experiment evidence'

$checklist = Get-Content -LiteralPath (Resolve-RepoPath $ChecklistPath) -Raw
foreach ($keyword in @('门禁维护', '依赖升级', '性能基线', 'quality dashboard', 'dependency gate', 'dry-run preview', 'rollback', 'fail-closed')) {
    Assert-True ($checklist.Contains($keyword)) "R006 checklist missing keyword: $keyword"
}

$evidence = Get-Content -LiteralPath (Resolve-RepoPath $EvidencePath) -Raw
foreach ($keyword in @('preflight', 'R006', 'platform_na', 'gate_na', '技术债', '下一步', 'fail-closed')) {
    Assert-True ($evidence.Contains($keyword)) "R006 evidence missing keyword: $keyword"
}

$decision = Get-Content -LiteralPath (Resolve-RepoPath $DecisionPath) -Raw
foreach ($keyword in @('ADR-008', 'fail-closed', 'report-only', 'dry-run', 'stale experiment inventory', 'dependency upgrade plan', 'rollback')) {
    Assert-True ($decision.Contains($keyword)) "R006 ADR missing keyword: $keyword"
}

$gates = Get-Content -LiteralPath (Resolve-RepoPath $GatesPath) -Raw
Assert-True ($gates.Contains('r006 techdebt cadence preflight contract')) 'full gate must include R006 contract'
Assert-True ($gates.Contains('pqr preflight pack contract')) 'full gate must include PQR pack before long-term cadence closeout'
Assert-True (Test-Path -LiteralPath (Resolve-RepoPath $RoadmapGuardPath)) 'roadmap guard script missing'

$dashboardRows = Import-Csv -LiteralPath (Resolve-RepoPath $CompletionDashboardPath) -Encoding UTF8
$dashboardByArea = @{}
foreach ($row in $dashboardRows) { $dashboardByArea[$row.area_id] = $row }
foreach ($areaId in @('backup-restore', 'deployment-install', 'live-pilot')) {
    Assert-True ($dashboardByArea.ContainsKey($areaId)) "completion dashboard missing area: $areaId"
}

$backupDashboard = $dashboardByArea['backup-restore']
$deploymentDashboard = $dashboardByArea['deployment-install']
$livePilotDashboard = $dashboardByArea['live-pilot']
Assert-True ($backupDashboard.blocking_gap -match 'P001') 'backup-restore must keep P001 operational review boundary'
Assert-True ($deploymentDashboard.usable_today -eq '不可发布使用') 'deployment-install must remain not releasable before P001/P006'
Assert-True ($livePilotDashboard.usable_today -eq '不可使用') 'live-pilot must remain unavailable before P001/P006'

$automationRows = Import-Csv -LiteralPath (Resolve-RepoPath $AutomationFirstPath) -Encoding UTF8
$automationById = @{}
foreach ($row in $automationRows) { $automationById[$row.task_id] = $row }
Assert-True ($automationById.ContainsKey('R006')) 'automation-first contract missing R006 row'
$r006Automation = $automationById['R006']
Assert-True ($r006Automation.deterministic_precheck -match 'gate|dependency|performance|stale') 'R006 automation-first deterministic precheck must include gate/dependency/performance/stale checks'
Assert-True ($r006Automation.exception_policy -match 'cleanup|rollback|baseline') 'R006 automation-first exception policy must block cleanup without rollback or baseline'

$g002 = Read-JsonFile $G002ReportPath
Assert-True ($g002.status -eq 'pass') 'G002 storage cleanup report must pass before R006 can cite cleanup evidence'
Assert-True ($g002.productionEligible -eq $false) 'G002 cleanup must not be production eligible'
Assert-True ($g002.cleanupBoundary.configuredCacheRootOnly -eq $true) 'G002 cleanup must be limited to configured cache root'
Assert-True ($g002.cleanupBoundary.dryRunSupported -eq $true) 'G002 cleanup must support dry-run'
Assert-True ($g002.cleanupBoundary.productionDataDeleteAllowed -eq $false) 'G002 cleanup must not allow production data deletion'

$o005 = Read-JsonFile $O005ReportPath
Assert-True ($o005.status -eq 'pass') 'O005 health dashboard report must pass before R006 can cite quality dashboard evidence'
Assert-True ($o005.productionEligible -eq $false) 'O005 dashboard must remain draft/test'
Assert-True ($o005.dependencies.g002 -eq 'pass') 'O005 dashboard must cite G002 cleanup boundary'
Assert-True ($o005.scope.cleanupSuggestion -match 'cache-only') 'O005 cleanup suggestion must remain cache-only'

$o008 = Read-JsonFile $O008ReportPath
Assert-True ($o008.status -eq 'pass') 'O008 technology refresh report must pass before R006 can cite dependency evidence'
Assert-True ($o008.mode -eq 'report_only') 'O008 technology refresh must remain report_only'
Assert-True ($o008.boundaries.noInstall -eq $true) 'O008 must not install dependencies'
Assert-True ($o008.boundaries.noDownload -eq $true) 'O008 must not download models'
Assert-True ($o008.boundaries.noDefaultRouteChange -eq $true) 'O008 must not change default routes'
Assert-True ($o008.boundaries.noProductionWrite -eq $true) 'O008 must not write production config'

$p001Report = Read-JsonFile $P001ReportPath
Assert-True ($p001Report.status -eq 'pass') 'P001 preflight report must pass before R006 can cite release readiness boundary'
Assert-True ($p001Report.p001CanClose -eq $false) 'P001 must not be closeable without isolated-machine proof'

$cadenceMatrix = @(
    [ordered]@{
        cadenceArea = 'gate_maintenance'
        currentDecision = 'allowed_as_evidence_refresh'
        currentEvidence = 'run-gates.ps1 includes R006 and PQR contracts; roadmap guard exists; full gate can be rerun without release-state transition.'
        allowedAction = 'refresh build/test/contract evidence and record failures with owner and rollback note.'
        failClosedRule = '不得跳过 build -> test -> contract/invariant -> hotspot 顺序，也不得把 preflight pass 当发布完成。'
    }
    [ordered]@{
        cadenceArea = 'dependency_refresh'
        currentDecision = 'report_only'
        currentEvidence = 'O008 technology refresh is pass/report_only with no install, no download, no default route change, and no production write.'
        allowedAction = 'trusted-source diff, catalog candidate, and eval-task drafting.'
        failClosedRule = '不得自动安装系统依赖、升级包、下载模型权重或修改默认 OCR/AI 路由。'
    }
    [ordered]@{
        cadenceArea = 'performance_baseline'
        currentDecision = 'blocked_until_baseline'
        currentEvidence = 'no release cadence owner, scenario budget, machine profile, or teacher-efficiency baseline is recorded for post-P006 cadence.'
        requiredBeforeAdmission = @('release cadence owner', 'scenario dataset', 'machine profile', 'budget threshold', 'rollback plan', 'teacher efficiency impact')
        failClosedRule = '无 baseline 不做性能优化；不得用主观体感替代数据。'
    }
    [ordered]@{
        cadenceArea = 'stale_experiment_cleanup'
        currentDecision = 'cache_only_draft_test_allowed'
        currentEvidence = 'G002 allows configured cache root cleanup with dry-run/apply split; O005 repeats cache-only cleanup suggestion.'
        allowedAction = 'cache root dry-run and cache root cleanup generated by dedicated contract only.'
        failClosedRule = '无 inventory、owner、last-used evidence、dry-run preview 和 rollback 不得删除实验、正式资产、题库、备份或配置。'
    }
)

$blockers = @(
    'R006 remains todo because P006 release decision is not closed.',
    'P001 isolated-machine evidence is still missing, so release cadence cannot become operational.',
    'No release cadence owner or periodic maintenance calendar exists.',
    'No post-release performance baseline with dataset, machine profile, budget, and teacher-efficiency impact exists.',
    'No stale experiment inventory with owner, last-used evidence, dry-run preview, and rollback exists.',
    'Dependency refresh remains report_only; no package/model/OCR upgrade is admitted.'
)

$report = [ordered]@{
    status = 'pass'
    taskId = 'R006'
    mode = 'admission_preflight'
    checkedAt = (Get-Date).ToString('s')
    p001Status = $p001.status
    p006Status = $p006.status
    r006Status = $r006.status
    closeTaskAllowed = $false
    currentDecision = 'keep_R006_todo_fail_closed_for_techdebt_cadence'
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    referencedEvidence = [ordered]@{
        gates = $GatesPath
        roadmapGuard = $RoadmapGuardPath
        g002Report = $G002ReportPath
        o005Report = $O005ReportPath
        o008Report = $O008ReportPath
        p001Report = $P001ReportPath
        completionDashboard = $CompletionDashboardPath
        automationFirstContract = $AutomationFirstPath
        decision = $DecisionPath
    }
    currentBoundaries = [ordered]@{
        gateMaintenanceAvailable = $true
        dependencyRefreshMode = [string] $o008.mode
        dependencyInstallAllowed = -not [bool] $o008.boundaries.noInstall
        modelDownloadAllowed = -not [bool] $o008.boundaries.noDownload
        cacheCleanupRootOnly = [bool] $g002.cleanupBoundary.configuredCacheRootOnly
        cacheCleanupDryRunSupported = [bool] $g002.cleanupBoundary.dryRunSupported
        productionDataDeleteAllowed = [bool] $g002.cleanupBoundary.productionDataDeleteAllowed
        p001CanClose = [bool] $p001Report.p001CanClose
    }
    cadenceMatrix = $cadenceMatrix
    blockers = $blockers
    nextRequiredEvidence = @(
        'P006 release decision record',
        'release cadence owner and maintenance calendar',
        'latest full gate, roadmap guard, dependency report, and backup/restore evidence',
        'performance baseline with dataset, machine profile, budget, rollback, and teacher-efficiency impact',
        'stale experiment inventory with owner, last-used evidence, dry-run preview, and rollback',
        'dependency upgrade plan with source, diff, supply-chain risk, compatibility, and rollback evidence'
    )
    boundary = 'R006 only refreshes tech-debt cadence admission evidence and ADR-008; it performs no dependency upgrade, no model download, no performance mutation, no experiment deletion, no production cleanup, and no release-state transition.'
    rollback = 'revert tools/run-r006-techdebt-cadence-preflight-contract.ps1, docs/templates/r006-techdebt-cadence-checklist.md, docs/decisions/ADR-008-techdebt-cadence-admission.md, tasks/backlog.csv, and remove the generated R006 admission report.'
}

$json = $report | ConvertTo-Json -Depth 10
Write-ContentIfChanged -Path $ReportPath -Content $json
$report | ConvertTo-Json -Depth 10

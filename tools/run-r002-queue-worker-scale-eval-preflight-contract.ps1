param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/r002-queue-worker-scale-eval-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-r002-queue-worker-scale-eval-preflight.md',
    [string] $CompletionDashboardPath = 'tasks/completion-state-dashboard.csv',
    [string] $AutomationFirstPath = 'tasks/automation-first-contract.csv',
    [string] $ArchitecturePath = 'docs/03_Architecture.md',
    [string] $TechnologyPath = 'docs/04_TechnologyStack.md',
    [string] $HostCapabilityPath = 'docs/evidence/o002-host-capability-diagnostic-report.json',
    [string] $WorkerProfilePath = 'docs/evidence/worker-profile-diagnostic-report.json',
    [string] $S012BReportPath = 'docs/evidence/20260509-s012b-non-site-e2e-rehearsal-report.json',
    [string] $P001ReportPath = 'docs/evidence/20260518-p001-live-pilot-readiness-preflight-report.json',
    [string] $DecisionPath = 'docs/decisions/ADR-011-queue-worker-scale-admission.md',
    [string] $ReportPath = 'docs/evidence/20260522-r002-queue-worker-scale-admission-report.json'
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
    Assert-True (Test-Path -LiteralPath $fullPath) "R002 required JSON evidence missing: $Path"
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
foreach ($id in @('P001', 'P006', 'R002')) {
    Assert-True ($byId.ContainsKey($id)) "R002 prerequisite task missing: $id"
}

$p001 = $byId['P001']
$p006 = $byId['P006']
$r002 = $byId['R002']
Assert-True ($r002.depends_on -eq 'P006') 'R002 must depend on P006'
Assert-True ($p001.status -eq '待办') 'P001 still pending; R002 must not skip isolated-machine evidence'
Assert-True ($p006.status -eq '待办') 'P006 still pending; R002 must remain todo before release decision closes'
Assert-True ($r002.status -eq '待办') 'R002 must remain todo until queue/worker metrics + ADR evidence is completed'
Assert-True ($r002.acceptance -match 'BackgroundService' -and $r002.acceptance -match 'Hangfire' -and $r002.acceptance -match 'RabbitMQ') 'R002 acceptance must require BackgroundService bottleneck evidence before Hangfire/RabbitMQ'

$checklist = Get-Content -LiteralPath (Resolve-RepoPath $ChecklistPath) -Raw
foreach ($keyword in @('BackgroundService', 'Hangfire', 'RabbitMQ', 'throughput', 'lease', 'retry', 'failure baseline', 'ADR', 'fail-closed')) {
    Assert-True ($checklist.Contains($keyword)) "R002 checklist missing keyword: $keyword"
}

$evidence = Get-Content -LiteralPath (Resolve-RepoPath $EvidencePath) -Raw
foreach ($keyword in @('preflight', 'R002', 'platform_na', 'gate_na', 'Worker 扩展', '下一步', 'fail-closed')) {
    Assert-True ($evidence.Contains($keyword)) "R002 evidence missing keyword: $keyword"
}

$architecture = Get-Content -LiteralPath (Resolve-RepoPath $ArchitecturePath) -Raw
foreach ($keyword in @('BackgroundService', 'PostgreSQL', 'Job Store', 'locked_by', 'locked_until', 'attempt_count', 'Hangfire', 'RabbitMQ')) {
    Assert-True ($architecture.Contains($keyword)) "R002 architecture evidence missing keyword: $keyword"
}

$technology = Get-Content -LiteralPath (Resolve-RepoPath $TechnologyPath) -Raw
foreach ($keyword in @('PostgreSQL job store + BackgroundService', 'Hangfire 后置', 'RabbitMQ 后置', 'queueProfile', '无吞吐瓶颈不引入 Hangfire/RabbitMQ')) {
    Assert-True ($technology.Contains($keyword)) "R002 technology evidence missing keyword: $keyword"
}

$decision = Get-Content -LiteralPath (Resolve-RepoPath $DecisionPath) -Raw
foreach ($keyword in @('ADR-011', 'fail-closed', 'BackgroundService', 'Hangfire', 'RabbitMQ', 'operational metrics', 'rollback/disable switch')) {
    Assert-True ($decision.Contains($keyword)) "R002 ADR missing keyword: $keyword"
}

$dashboardRows = Import-Csv -LiteralPath (Resolve-RepoPath $CompletionDashboardPath) -Encoding UTF8
$dashboardByArea = @{}
foreach ($row in $dashboardRows) { $dashboardByArea[$row.area_id] = $row }
foreach ($areaId in @('core-runtime', 'question-upload', 'document-parsing', 'review-queue')) {
    Assert-True ($dashboardByArea.ContainsKey($areaId)) "completion dashboard missing area: $areaId"
}
$coreRuntime = $dashboardByArea['core-runtime']
$questionUpload = $dashboardByArea['question-upload']
$documentParsing = $dashboardByArea['document-parsing']
$reviewQueue = $dashboardByArea['review-queue']
Assert-True ($coreRuntime.current_state -eq 'db_backed_done') 'core-runtime must remain db_backed_done'
Assert-True ($questionUpload.current_state -eq 'teacher_validated') 'question-upload must remain teacher_validated'
Assert-True ($documentParsing.blocking_gap -match 'P001') 'document-parsing must keep P001 real-material boundary'
Assert-True ($reviewQueue.blocking_gap -match 'P001') 'review-queue must keep P001 concurrency/audit boundary'

$automationRows = Import-Csv -LiteralPath (Resolve-RepoPath $AutomationFirstPath) -Encoding UTF8
$automationById = @{}
foreach ($row in $automationRows) { $automationById[$row.task_id] = $row }
Assert-True ($automationById.ContainsKey('R002')) 'automation-first contract missing R002 row'
$r002Automation = $automationById['R002']
Assert-True ($r002Automation.deterministic_precheck -match 'BackgroundService|throughput|lease|retry|failure') 'R002 automation-first deterministic precheck must include BackgroundService throughput/lease/retry/failure checks'
Assert-True ($r002Automation.exception_policy -match 'Hangfire|RabbitMQ|bottleneck') 'R002 automation-first exception policy must block Hangfire/RabbitMQ without bottleneck evidence'

$hostCapability = Read-JsonFile $HostCapabilityPath
Assert-True ($hostCapability.recommendedProfiles.queueProfile.status -eq 'backgroundservice_ok') 'host capability queue profile must be backgroundservice_ok'
Assert-True ($hostCapability.recommendedProfiles.queueProfile.recommended -eq 'postgresql_job_store_backgroundservice_first') 'host capability queue profile must stay PostgreSQL job store + BackgroundService first'
Assert-True ($hostCapability.recommendedProfiles.queueProfile.fallback -match 'defer_hangfire_rabbitmq') 'host capability must defer Hangfire/RabbitMQ'

$workerProfile = Read-JsonFile $WorkerProfilePath
Assert-True ($workerProfile.schemaVersion -eq 'worker-profile-diagnostic.v1') 'worker profile diagnostic schema mismatch'
Assert-True ($workerProfile.mode -eq 'read_only') 'worker profile diagnostic must be read-only'
Assert-True ($workerProfile.recommendation.recommendedDefaultProfile -eq 'direct_venv_lite') 'worker profile must keep direct_venv_lite default'
Assert-True ($workerProfile.guardrail.noInstallPerformed -eq $true) 'worker profile diagnostic must not install dependencies'
Assert-True ($workerProfile.guardrail.productionDefaultChanged -eq $false) 'worker profile diagnostic must not change production default'

$s012b = Read-JsonFile $S012BReportPath
Assert-True ($s012b.status -eq 'pass') 'S012B non-site E2E rehearsal must pass before R002 can cite workflow throughput evidence'
Assert-True ($s012b.productionEligible -eq $false) 'S012B must remain non-production'
Assert-True ($s012b.elapsed.totalMs -gt 0) 'S012B must include elapsed timing'
Assert-True (($s012b.workflowSteps | Where-Object { $_.workflowStep -eq 'import_cut_review_save' -and $_.status -eq 'pass' }).Count -gt 0) 'S012B must include import/cut/review/save queue path'

$p001Report = Read-JsonFile $P001ReportPath
Assert-True ($p001Report.status -eq 'pass') 'P001 preflight report must pass before R002 can cite field boundary'
Assert-True ($p001Report.p001CanClose -eq $false) 'P001 must remain open'
Assert-True ($p001Report.readyForIsolatedMachineRun -eq $true) 'P001 should be ready for isolated-machine run, not closed'

$admissionMatrix = @(
    [ordered]@{
        queueKind = 'postgresql_job_store_backgroundservice'
        currentDecision = 'current_default'
        currentEvidence = 'Architecture and technology docs define PostgreSQL job store + BackgroundService first; S012B proves a scripted non-site workflow path; host diagnostic keeps queueProfile=postgresql_job_store_backgroundservice_first.'
        allowedAction = 'maintain job table state machine, lease/retry/idempotency contracts, worker smoke, and elapsed evidence capture.'
        failClosedRule = '不得把非现场 rehearsal 当现场吞吐验收；P001/P006 未闭环时不得改变默认队列技术。'
    }
    [ordered]@{
        queueKind = 'hangfire'
        currentDecision = 'blocked_until_operational_need'
        currentEvidence = 'no dashboard need, delayed-recurring scheduling need, retry-policy gap, throughput bottleneck, or migration owner exists.'
        requiredBeforeAdmission = @('P006 release decision', 'operational dashboard requirement', 'retry/delay/recurrent-job gap', 'migration plan', 'rollback/disable switch', 'teacher workflow impact')
        failClosedRule = '不得新增 Hangfire package、schema、dashboard endpoint、默认 job runner 或发布说明承诺。'
    }
    [ordered]@{
        queueKind = 'rabbitmq_or_distributed_queue'
        currentDecision = 'blocked'
        currentEvidence = 'no multi-machine worker need, strict queue isolation requirement, broker ops owner, backup/restore drill, or school deployment proof exists.'
        requiredBeforeAdmission = @('real multi-worker throughput evidence', 'broker ops owner', 'network/firewall plan', 'message durability and idempotency proof', 'backup/restore runbook', 'fallback to PostgreSQL job store')
        failClosedRule = '不得引入 RabbitMQ/Kafka/broker service, distributed worker default, or queue schema split before evidence.'
    }
)

$blockers = @(
    'R002 remains todo because P006 release decision is not closed.',
    'P001 isolated-machine field evidence is still missing; S012B is non-site only.',
    'No BackgroundService throughput p50/p95, queue depth, retry-rate, stuck-job, or worker saturation baseline exists.',
    'No operational dashboard/recurrent-job/retry-policy gap justifies Hangfire.',
    'No multi-machine worker or strict queue isolation evidence justifies RabbitMQ.'
)

$report = [ordered]@{
    status = 'pass'
    taskId = 'R002'
    mode = 'admission_preflight'
    checkedAt = (Get-Date).ToString('s')
    p001Status = $p001.status
    p006Status = $p006.status
    r002Status = $r002.status
    closeTaskAllowed = $false
    currentDecision = 'keep_R002_todo_backgroundservice_first_fail_closed'
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    referencedEvidence = [ordered]@{
        architecture = $ArchitecturePath
        technology = $TechnologyPath
        hostCapability = $HostCapabilityPath
        workerProfile = $WorkerProfilePath
        s012bReport = $S012BReportPath
        p001Report = $P001ReportPath
        completionDashboard = $CompletionDashboardPath
        automationFirstContract = $AutomationFirstPath
        decision = $DecisionPath
    }
    currentBaseline = [ordered]@{
        queueProfile = [string] $hostCapability.recommendedProfiles.queueProfile.recommended
        queueProfileStatus = [string] $hostCapability.recommendedProfiles.queueProfile.status
        queueFallback = [string] $hostCapability.recommendedProfiles.queueProfile.fallback
        workerDefaultProfile = [string] $workerProfile.recommendation.recommendedDefaultProfile
        workerDiagnosticReadOnly = [bool] ($workerProfile.mode -eq 'read_only')
        s012bElapsedMs = [int] $s012b.elapsed.totalMs
        s012bWorkflowStepCount = @($s012b.workflowSteps).Count
        p001CanClose = [bool] $p001Report.p001CanClose
        readyForIsolatedMachineRun = [bool] $p001Report.readyForIsolatedMachineRun
    }
    admissionMatrix = $admissionMatrix
    blockers = $blockers
    nextRequiredEvidence = @(
        'P006 release decision record',
        'P001 isolated-machine run with queue depth, elapsed time, retry and stuck-job evidence',
        'BackgroundService throughput p50/p95 and failure recovery baseline',
        'teacher workflow impact when queue is saturated',
        'Hangfire/RabbitMQ migration owner, rollback and disable-switch plan only if baseline proves need'
    )
    boundary = 'R002 only refreshes queue/worker scale admission evidence and ADR-011; it performs no package install, no broker setup, no Hangfire schema change, no distributed worker route change, no production write, and no release-state transition.'
    rollback = 'revert tools/run-r002-queue-worker-scale-eval-preflight-contract.ps1, docs/templates/r002-queue-worker-scale-eval-checklist.md, docs/decisions/ADR-011-queue-worker-scale-admission.md, tasks/backlog.csv, and remove the generated R002 admission report.'
}

$json = $report | ConvertTo-Json -Depth 10
Write-ContentIfChanged -Path $ReportPath -Content $json
$report | ConvertTo-Json -Depth 10

param(
    [string] $ReportPath = '',
    [string] $NonSitePlanPath = 'tasks/non-site-implementation-plan.csv',
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $R002ReportPath = '',
    [string] $R002DecisionPath = 'docs/decisions/ADR-011-queue-worker-scale-admission.md',
    [string] $R002ChecklistPath = 'docs/templates/r002-queue-worker-scale-eval-checklist.md',
    [string] $R002PreflightEvidencePath = 'docs/evidence/20260505-r002-queue-worker-scale-eval-preflight.md',
    [string] $CompletionDashboardPath = 'tasks/completion-state-dashboard.csv',
    [string] $HostCapabilityPath = 'docs/evidence/o002-host-capability-diagnostic-report.json',
    [string] $WorkerProfilePath = 'docs/evidence/worker-profile-diagnostic-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runDate = Get-Date -Format 'yyyyMMdd'

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = ('docs/evidence/{0}-ns1202-queue-eval.json' -f $runDate)
}

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Resolve-InRepoPath([string] $RelativePath) {
    return Join-Path $repoRoot ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
}

function Read-Json([string] $Path) {
    $fullPath = Resolve-InRepoPath $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing json report: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}
function Resolve-LatestEvidencePath([string] $Filter) {
    $evidenceRoot = Resolve-InRepoPath 'docs/evidence'
    Assert-Condition (Test-Path -LiteralPath $evidenceRoot) 'missing docs/evidence directory'
    $latest = @(Get-ChildItem -LiteralPath $evidenceRoot -Filter $Filter -File | Sort-Object Name -Descending | Select-Object -First 1)
    Assert-Condition ($latest.Count -eq 1) "missing evidence matching filter: $Filter"
    return [System.IO.Path]::GetRelativePath($repoRoot, $latest[0].FullName).Replace('\', '/')
}

if ([string]::IsNullOrWhiteSpace($R002ReportPath)) {
    $R002ReportPath = Resolve-LatestEvidencePath '*-r002-queue-worker-scale-admission-report.json'
}

function Get-RequiredRow([object[]] $Rows, [string] $Id, [string] $Column = 'id') {
    $matches = @($Rows | Where-Object { [string]$_.$Column -eq $Id })
    Assert-Condition ($matches.Count -eq 1) "expected exactly one $Column=$Id row"
    return $matches[0]
}

function Assert-TextContains([string] $Text, [string[]] $Needles, [string] $Label) {
    foreach ($needle in $Needles) {
        Assert-Condition ($Text.Contains($needle)) "$Label missing text: $needle"
    }
}

function Find-CodePatternHits([string[]] $RelativeRoots, [string[]] $Patterns) {
    $hits = @()
    foreach ($relativeRoot in $RelativeRoots) {
        $fullRoot = Resolve-InRepoPath $relativeRoot
        if (-not (Test-Path -LiteralPath $fullRoot)) { continue }

        $files = @(Get-ChildItem -LiteralPath $fullRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $_.FullName -notmatch '\\(bin|obj|node_modules)\\'
        })
        foreach ($file in $files) {
            foreach ($pattern in $Patterns) {
                $matches = @(Select-String -LiteralPath $file.FullName -Pattern $pattern -CaseSensitive:$false -ErrorAction SilentlyContinue)
                foreach ($match in $matches) {
                    $hits += [ordered]@{
                        path = $file.FullName.Substring($repoRoot.Length + 1)
                        line = $match.LineNumber
                        pattern = $pattern
                    }
                }
            }
        }
    }

    return @($hits)
}

Push-Location $repoRoot
try {
    $planFullPath = Resolve-InRepoPath $NonSitePlanPath
    $backlogFullPath = Resolve-InRepoPath $BacklogPath
    $decisionFullPath = Resolve-InRepoPath $R002DecisionPath
    $checklistFullPath = Resolve-InRepoPath $R002ChecklistPath
    $preflightEvidenceFullPath = Resolve-InRepoPath $R002PreflightEvidencePath
    $completionDashboardFullPath = Resolve-InRepoPath $CompletionDashboardPath

    foreach ($requiredPath in @($planFullPath, $backlogFullPath, $decisionFullPath, $checklistFullPath, $preflightEvidenceFullPath, $completionDashboardFullPath)) {
        Assert-Condition (Test-Path -LiteralPath $requiredPath) "missing required file: $requiredPath"
    }

    $planRows = @(Import-Csv -LiteralPath $planFullPath -Encoding UTF8)
    $backlogRows = @(Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8)
    $dashboardRows = @(Import-Csv -LiteralPath $completionDashboardFullPath -Encoding UTF8)

    $ns1005 = Get-RequiredRow $planRows 'NS1005'
    $ns1202 = Get-RequiredRow $planRows 'NS1202'
    Assert-Condition ($ns1005.status -eq 'blocked_by_onsite') 'NS1202 must inherit NS1005 release-decision blocked_by_onsite boundary'
    Assert-Condition ($ns1202.depends_on -eq 'NS1005') 'NS1202 must continue to depend on NS1005'
    Assert-Condition ($ns1202.status -in @('planned','runtime_verified')) "NS1202 has unsupported status: $($ns1202.status)"
    Assert-Condition ($ns1202.acceptance -match 'BackgroundService' -and $ns1202.acceptance -match 'Hangfire' -and $ns1202.acceptance -match 'RabbitMQ') 'NS1202 acceptance must keep BackgroundService-first admission boundary'

    $p006 = Get-RequiredRow $backlogRows 'P006'
    $r002 = Get-RequiredRow $backlogRows 'R002'
    Assert-Condition ($p006.status -eq '待办') 'NS1202 must not skip P006 release decision'
    Assert-Condition ($r002.status -eq '待办') 'NS1202 must not close R002 without real queue/worker metrics'
    Assert-Condition ($r002.depends_on -eq 'P006') 'R002 must continue to depend on P006'

    $r002Report = Read-Json $R002ReportPath
    $hostCapability = Read-Json $HostCapabilityPath
    $workerProfile = Read-Json $WorkerProfilePath

    Assert-Condition ($r002Report.status -eq 'pass') 'NS1202 requires R002 admission report to pass'
    Assert-Condition (-not [bool]$r002Report.closeTaskAllowed) 'R002 closeTaskAllowed must remain false'
    Assert-Condition ($r002Report.currentDecision -eq 'keep_R002_todo_backgroundservice_first_fail_closed') 'R002 decision must remain BackgroundService-first fail-closed'
    Assert-Condition ($r002Report.currentBaseline.queueProfile -eq 'postgresql_job_store_backgroundservice_first') 'R002 baseline must keep PostgreSQL job store + BackgroundService first'
    Assert-Condition ($r002Report.currentBaseline.queueProfileStatus -eq 'backgroundservice_ok') 'R002 baseline must keep queue profile backgroundservice_ok'
    Assert-Condition ($r002Report.currentBaseline.queueFallback -match 'defer_hangfire_rabbitmq') 'R002 baseline must defer Hangfire/RabbitMQ'
    Assert-Condition ($r002Report.currentBaseline.workerDefaultProfile -eq 'direct_venv_lite') 'worker default profile must remain direct_venv_lite'
    Assert-Condition ($r002Report.currentBaseline.p001CanClose -eq $false) 'P001 must remain open through R002 baseline'

    $matrixByKind = @{}
    foreach ($entry in @($r002Report.admissionMatrix)) {
        $matrixByKind[[string]$entry.queueKind] = $entry
    }
    foreach ($kind in @('postgresql_job_store_backgroundservice', 'hangfire', 'rabbitmq_or_distributed_queue')) {
        Assert-Condition ($matrixByKind.ContainsKey($kind)) "R002 admission matrix missing: $kind"
    }
    Assert-Condition ($matrixByKind['postgresql_job_store_backgroundservice'].currentDecision -eq 'current_default') 'PostgreSQL job store + BackgroundService must remain current default'
    Assert-Condition ($matrixByKind['hangfire'].currentDecision -eq 'blocked_until_operational_need') 'Hangfire must remain blocked until operational need'
    Assert-Condition ($matrixByKind['rabbitmq_or_distributed_queue'].currentDecision -eq 'blocked') 'RabbitMQ/distributed queue must remain blocked'

    $decisionText = Get-Content -LiteralPath $decisionFullPath -Raw
    Assert-TextContains $decisionText @(
        'ADR-011',
        'fail-closed',
        'BackgroundService',
        'Hangfire',
        'RabbitMQ',
        'operational metrics',
        'rollback/disable switch'
    ) 'ADR-011'

    $checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
    Assert-TextContains $checklistText @(
        'BackgroundService',
        'Hangfire',
        'RabbitMQ',
        'throughput',
        'queue depth',
        'fail-closed'
    ) 'R002 checklist'

    $preflightText = Get-Content -LiteralPath $preflightEvidenceFullPath -Raw
    Assert-TextContains $preflightText @(
        'R002',
        'platform_na',
        'gate_na',
        'Worker 扩展',
        'fail-closed'
    ) 'R002 preflight evidence'

    $coreRuntimeArea = Get-RequiredRow $dashboardRows 'core-runtime' 'area_id'
    $reviewQueueArea = Get-RequiredRow $dashboardRows 'review-queue' 'area_id'
    $advancedPlatformArea = Get-RequiredRow $dashboardRows 'advanced-platform' 'area_id'
    Assert-Condition ($coreRuntimeArea.current_state -eq 'db_backed_done') 'core-runtime dashboard state must remain db_backed_done'
    Assert-Condition ($reviewQueueArea.blocking_gap -match 'P001') 'review-queue must retain P001 concurrency/audit boundary'
    Assert-Condition ($advancedPlatformArea.usable_today -eq '不可使用') 'advanced-platform must remain unavailable before real bottleneck evidence'
    Assert-Condition ($hostCapability.recommendedProfiles.queueProfile.status -eq 'backgroundservice_ok') 'host capability queue profile must stay backgroundservice_ok'
    Assert-Condition ($workerProfile.mode -eq 'read_only') 'worker profile diagnostic must remain read_only'
    Assert-Condition ([bool]$workerProfile.guardrail.noInstallPerformed) 'worker profile diagnostic must not install dependencies'
    Assert-Condition (-not [bool]$workerProfile.guardrail.productionDefaultChanged) 'worker profile diagnostic must not change production default'

    $codePatternHits = Find-CodePatternHits @('apps/api', 'apps/web/src', 'workers') @(
        'Hangfire',
        'RabbitMQ',
        'MassTransit',
        'Confluent\.Kafka',
        'Kafka',
        'IBackgroundJobClient',
        'UseHangfire',
        'QueueDeclare'
    )
    Assert-Condition ($codePatternHits.Count -eq 0) 'NS1202 found product code that appears to enable Hangfire/RabbitMQ/distributed queue'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS1202'
        checkedAt = (Get-Date).ToString('s')
        mode = 'queue_worker_scale_admission_boundary'
        productionEligible = $false
        nonSiteValidated = $false
        releaseReady = $false
        externalAiCalls = 0
        realStudentDataUsed = $false
        containsStudentPii = $false
        writesProductionHistory = $false
        activeAssetMutation = $false
        dependency = [ordered]@{
            ns1005 = $NonSitePlanPath
            r002Report = $R002ReportPath
            r002Decision = $R002DecisionPath
            r002Checklist = $R002ChecklistPath
            r002PreflightEvidence = $R002PreflightEvidencePath
            completionDashboard = $CompletionDashboardPath
            hostCapability = $HostCapabilityPath
            workerProfile = $WorkerProfilePath
        }
        backlog = [ordered]@{
            p006Status = [string]$p006.status
            r002Status = [string]$r002.status
            r002CloseTaskAllowed = $false
            ns1005Status = [string]$ns1005.status
            ns1202StatusAtCheck = [string]$ns1202.status
            ns1202DependsOn = [string]$ns1202.depends_on
        }
        currentBaseline = [ordered]@{
            queueProfile = [string]$r002Report.currentBaseline.queueProfile
            queueProfileStatus = [string]$r002Report.currentBaseline.queueProfileStatus
            queueFallback = [string]$r002Report.currentBaseline.queueFallback
            workerDefaultProfile = [string]$r002Report.currentBaseline.workerDefaultProfile
            workerDiagnosticReadOnly = [bool]$r002Report.currentBaseline.workerDiagnosticReadOnly
            s012bElapsedMs = [int]$r002Report.currentBaseline.s012bElapsedMs
            p001CanClose = [bool]$r002Report.currentBaseline.p001CanClose
        }
        admissionDecision = [ordered]@{
            postgresqlJobStoreBackgroundService = [string]$matrixByKind['postgresql_job_store_backgroundservice'].currentDecision
            hangfire = [string]$matrixByKind['hangfire'].currentDecision
            rabbitmqOrDistributedQueue = [string]$matrixByKind['rabbitmq_or_distributed_queue'].currentDecision
            currentDecision = [string]$r002Report.currentDecision
        }
        codeScan = [ordered]@{
            searchedRoots = @('apps/api', 'apps/web/src', 'workers')
            blockedPatterns = @('Hangfire', 'RabbitMQ', 'MassTransit', 'Confluent.Kafka', 'Kafka', 'IBackgroundJobClient', 'UseHangfire', 'QueueDeclare')
            hitCount = [int]$codePatternHits.Count
            noHangfirePackageOrRoute = $true
            noRabbitMqOrBrokerRoute = $true
            noDistributedQueueDefault = $true
        }
        acceptance = [ordered]@{
            r002AdmissionReportPassed = $true
            adr011FailClosedAccepted = $true
            backgroundServiceKeptAsDefault = $true
            hangfireBlockedUntilOperationalNeed = $true
            rabbitMqBlocked = $true
            p006RemainsTodo = $true
            ns1005RemainsBlockedByOnsite = $true
            r002RemainsTodo = $true
            noHangfirePackageOrSchema = $true
            noRabbitMqOrBrokerSetup = $true
            noDistributedWorkerRouteChange = $true
            noProductionWrite = $true
        }
        nextRequiredEvidence = @(
            'P006 release decision record',
            'P001 isolated-machine run with queue depth and retry evidence',
            'BackgroundService throughput p50/p95 and failure recovery baseline',
            'teacher workflow impact when queue is saturated',
            'Hangfire/RabbitMQ migration owner and rollback/disable-switch plan only if baseline proves need'
        )
        verification = [ordered]@{
            build = 'gate_na: admission boundary script only; no product code build required'
            test = 'tools/run-r002-queue-worker-scale-eval-preflight-contract.ps1 + tools/run-ns1202-queue-eval.ps1'
            contractInvariant = 'NS1202 keeps PostgreSQL job store + BackgroundService first, leaves R002/P006/NS1005 blocked, and verifies no Hangfire/RabbitMQ/distributed-queue product route was enabled'
            hotspot = 'gate_na: real queue scale benchmark requires post-NS1005 release/field evidence and queue metrics'
        }
        teacherEfficiencyBoundary = 'ordinary teacher workflows are unchanged; NS1202 only prevents premature queue infrastructure until real BackgroundService insufficiency evidence exists'
        boundary = 'NS1202 verifies the queue/worker scale admission boundary only. It does not run a field throughput benchmark, does not close R002, does not install Hangfire, does not configure RabbitMQ or a broker, and does not change default worker routes.'
        rollback = "git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1 tools/README.md; git clean -f -- tools/run-ns1202-queue-eval.ps1 $ReportPath"
        next = 'NS1203 can continue interoperability profile-map boundary; real queue technology upgrade remains blocked until P006/NS1005 and metrics evidence exist.'
    }

    $jsonText = $report | ConvertTo-Json -Depth 12
    $reportFullPath = Resolve-InRepoPath $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $jsonText | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $jsonText
}
finally {
    Pop-Location
}

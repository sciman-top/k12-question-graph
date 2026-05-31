param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $ReportPath = 'docs/evidence/20260530-ns805-health-dashboard.json',
    [string] $O005ReportPath = 'docs/evidence/o005-capacity-cost-health-dashboard-report.json',
    [switch] $SkipO005Refresh
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Read-Json([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing report: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Convert-OutputToJson([object[]] $Output, [string] $Label) {
    $lines = @($Output | ForEach-Object { [string]$_ })
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].TrimStart().StartsWith('{')) {
            $start = $i
            break
        }
    }

    Assert-Condition ($start -ge 0) "$Label did not emit a JSON object"
    $jsonText = ($lines[$start..($lines.Count - 1)] -join [Environment]::NewLine)
    return $jsonText | ConvertFrom-Json
}

function Assert-NoSecretInText([string] $Text, [string] $Secret, [string] $Label) {
    if ([string]::IsNullOrWhiteSpace($Secret)) {
        return
    }

    Assert-Condition (-not $Text.Contains($Secret)) "$Label leaked the database password"
}

Push-Location $repoRoot
try {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'DatabasePassword or PGPASSWORD is required for NS805 health dashboard.'

    $ns801 = Read-Json 'docs/evidence/20260530-ns801-backup-manifest-report.json'
    $ns802 = Read-Json 'docs/evidence/20260530-ns802-restore-drill-report.json'
    $ns803 = Read-Json 'docs/evidence/20260530-ns803-installer-host.json'
    $ns804 = Read-Json 'docs/evidence/20260530-ns804-windows-service.json'
    $ns503 = Read-Json 'docs/evidence/20260530-ns503-model-router-budget-report.json'
    $k006 = Read-Json 'docs/evidence/k006-knowledge-asset-health-dashboard-report.json'

    Assert-Condition ($ns801.status -eq 'pass') 'NS805 dependency NS801 report did not pass'
    Assert-Condition ($ns802.status -eq 'pass') 'NS805 dependency NS802 report did not pass'
    Assert-Condition ($ns803.status -eq 'pass') 'NS805 dependency NS803 report did not pass'
    Assert-Condition ($ns804.status -eq 'pass') 'NS805 dependency NS804 report did not pass'
    Assert-Condition ($ns503.status -eq 'pass') 'NS805 dependency NS503 report did not pass'
    Assert-Condition ($k006.status -eq 'pass') 'NS805 dependency K006 report did not pass'

    Assert-Condition ([bool]$ns801.acceptance.fileStoreInManifest) 'NS805 requires file store backup manifest evidence'
    Assert-Condition ([bool]$ns801.acceptance.noPlaintextDatabasePasswordInManifest) 'NS805 requires backup manifest secret guard'
    Assert-Condition ([bool]$ns802.acceptance.productionDatabaseUntouched) 'NS805 requires restore drill to leave production database untouched'
    Assert-Condition ([bool]$ns802.acceptance.productionFileStoreUntouched) 'NS805 requires restore drill to leave production file store untouched'
    Assert-Condition ([bool]$ns803.acceptance.hostCapabilityDiagnosticReadOnly) 'NS805 requires NS803 read-only host diagnostic evidence'
    Assert-Condition ([bool]$ns804.acceptance.healthReadinessPassed) 'NS805 requires NS804 package health/readiness evidence'
    Assert-Condition ([bool]$ns503.acceptance.tokenAndCostRecorded) 'NS805 requires AI token/cost evidence'
    Assert-Condition ([bool]$ns503.acceptance.realModelCallsStillDisabled) 'NS805 requires real model calls to stay disabled'
    Assert-Condition (-not [bool]$k006.activeWriteAllowed) 'NS805 knowledge dashboard must not allow active writes'
    Assert-Condition (-not [bool]$k006.migrationApplyAllowed) 'NS805 knowledge dashboard must not apply migrations'

    if (-not $SkipO005Refresh) {
        $o005Output = .\tools\run-o005-capacity-cost-health-dashboard-contract.ps1 `
            -DatabaseName $DatabaseName `
            -DatabaseUser $DatabaseUser `
            -DatabaseHost $DatabaseHost `
            -DatabasePort $DatabasePort `
            -DatabasePassword $DatabasePassword `
            -PgBin $PgBin `
            -Report $O005ReportPath
        $o005 = Convert-OutputToJson $o005Output 'O005 capacity cost health dashboard contract'
    }
    else {
        $o005 = Read-Json $O005ReportPath
    }

    Assert-Condition ($o005.status -eq 'pass') 'NS805 dependency O005 report did not pass'
    Assert-Condition ($o005.dependencies.g002 -eq 'pass') 'NS805 requires O005 G002 dependency to pass'
    Assert-Condition ($o005.dependencies.d002 -eq 'pass') 'NS805 requires O005 D002 dependency to pass'
    Assert-Condition ($o005.dependencies.l006Evidence -eq 'present') 'NS805 requires L006 dashboard pilot evidence'

    $g002 = Read-Json 'docs/evidence/g002-storage-cleanup-report.json'
    Assert-Condition ($g002.status -eq 'pass') 'NS805 dependency G002 report did not pass'
    Assert-Condition ([bool]$g002.cleanupBoundary.configuredCacheRootOnly) 'NS805 cache cleanup must be restricted to configured cache root'
    Assert-Condition ([bool]$g002.cleanupBoundary.dryRunSupported) 'NS805 cache cleanup must support dry-run'
    Assert-Condition ([bool]$g002.cleanupBoundary.protectedFileStoreUntouched) 'NS805 cleanup must leave file store untouched'
    Assert-Condition (-not [bool]$g002.cleanupBoundary.productionDataDeleteAllowed) 'NS805 cleanup must not allow production data delete'

    foreach ($contract in @(
        'admin-storage-dashboard',
        'storage-summary',
        'cache-cleanup-configured-root',
        'no-production-data-delete',
        'knowledge-asset-health-dashboard',
        'failed-task-state-signal'
    )) {
        Assert-Condition (@($o005.uiContracts) -contains $contract) "NS805 missing O005 UI contract: $contract"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS805'
        checkedAt = (Get-Date).ToString('s')
        mode = 'capacity_cost_health_dashboard'
        productionEligible = $false
        externalAiCalls = 0
        realStudentDataUsed = $false
        writesProductionHistory = $false
        activeAssetMutation = $false
        dependency = [ordered]@{
            ns801 = 'docs/evidence/20260530-ns801-backup-manifest-report.json'
            ns802 = 'docs/evidence/20260530-ns802-restore-drill-report.json'
            ns803 = 'docs/evidence/20260530-ns803-installer-host.json'
            ns804 = 'docs/evidence/20260530-ns804-windows-service.json'
            ns503 = 'docs/evidence/20260530-ns503-model-router-budget-report.json'
            g002 = 'docs/evidence/g002-storage-cleanup-report.json'
            k006 = 'docs/evidence/k006-knowledge-asset-health-dashboard-report.json'
            o005 = $O005ReportPath
        }
        dashboard = [ordered]@{
            storageAreas = @($g002.summary.areas | ForEach-Object {
                [ordered]@{
                    name = [string]$_.name
                    bytes = [long]$_.bytes
                    fileCount = [int]$_.fileCount
                    cleanupAllowed = [bool]$_.cleanupAllowed
                }
            })
            backup = [ordered]@{
                manifest = [string]$ns801.backup.manifest
                fileCount = [int]$ns801.backup.fileCount
                databaseDumpInManifest = [bool]$ns801.acceptance.databaseDumpInManifest
                sha256Verified = [bool]$ns801.acceptance.sha256Verified
            }
            restore = [ordered]@{
                isolatedRoot = [string]$ns802.restore.isolatedRoot
                fileStoreRestoredCount = [int]$ns802.restore.fileStoreRestoredCount
                productionDatabaseUntouched = [bool]$ns802.acceptance.productionDatabaseUntouched
                productionFileStoreUntouched = [bool]$ns802.acceptance.productionFileStoreUntouched
            }
            cache = [ordered]@{
                cleanupRoot = [string]$g002.summary.cacheCleanupRoot
                dryRunSupported = [bool]$g002.cleanupBoundary.dryRunSupported
                configuredCacheRootOnly = [bool]$g002.cleanupBoundary.configuredCacheRootOnly
                previewMatchedFileCount = [int]$g002.preview.matchedFileCount
                cleanupDeletedFileCount = [int]$g002.cleanup.deletedFileCount
                protectedFileStoreUntouched = [bool]$g002.cleanupBoundary.protectedFileStoreUntouched
            }
            aiCost = [ordered]@{
                source = 'NS503 model router budget + O005 D002 dependency'
                jobId = [string]$ns503.aiJobCost.jobId
                provider = [string]$ns503.aiJobCost.modelProvider
                model = [string]$ns503.aiJobCost.modelName
                inputTokens = [int]$ns503.aiJobCost.inputTokens
                outputTokens = [int]$ns503.aiJobCost.outputTokens
                cachedTokens = [int]$ns503.cache.d002CachedTokens
                actualCost = [decimal]$ns503.aiJobCost.actualCost
                reviewStatus = [string]$ns503.aiJobCost.reviewStatus
                realModelCallsDefault = [bool]$ns503.routing.realModelCallsDefault
            }
            failureAndKnowledgeHealth = [ordered]@{
                failedTaskSignal = 'failed-task-state-signal'
                knowledgeDashboard = [string]$k006.dashboard
                coveredStatusFields = @($k006.coveredStatusFields)
                readonlyActions = @($k006.readonlyActions)
            }
            uiContracts = @($o005.uiContracts)
        }
        acceptance = [ordered]@{
            ns803InstallerHostEvidencePassed = $true
            ns804PackageHealthEvidencePassed = $true
            fileStoreCapacityVisible = $true
            backupManifestVisible = $true
            restoreHealthVisible = $true
            cacheCapacityVisible = $true
            aiTokenAndCostVisible = $true
            failedTaskSignalVisible = $true
            cleanupSuggestionCacheOnly = $true
            knowledgeAssetHealthVisible = $true
            noProductionDataDelete = $true
            noExternalAiCall = $true
            noRealStudentData = $true
            noActiveWrite = $true
            noWindowsServiceInstalled = [bool]$ns804.acceptance.noWindowsServiceInstalled
        }
        verification = [ordered]@{
            build = 'outer gate: dotnet build apps/api/K12QuestionGraph.Api.csproj before run-gates'
            test = 'O005 API/UI smoke via storage summary, cache cleanup, D002 AI cost dependency, L006 evidence, and UI contract markers'
            contractInvariant = 'NS805 aggregates file-store/backup/cache/AI-cost/failed-task/cleanup/knowledge-health signals without production delete, active write, external AI, or real student data'
            hotspot = 'gate_na: no live operator dashboard session or isolated teacher-machine install; NS1001/P001 own live install and pilot validation'
        }
        boundary = 'NS805 proves a non-site administrator capacity/cost/health dashboard contract using draft/test API smoke and existing UI markers. It is not a live production monitoring rollout, and it does not install services, delete production data, call external AI, or change active assets.'
        rollback = "git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1 tools/README.md; git clean -f -- tools/run-ns805-health-dashboard.ps1 $ReportPath"
        next = 'NS806 can continue EF migration bundle and upgrade rehearsal.'
    }

    $jsonText = $report | ConvertTo-Json -Depth 12
    Assert-NoSecretInText $jsonText $DatabasePassword 'NS805 report'

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $jsonText | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $jsonText
}
finally {
    Pop-Location
}

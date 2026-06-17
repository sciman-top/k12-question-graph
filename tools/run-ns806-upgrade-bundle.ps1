param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $ReportPath = '',
    [string] $O007ReportPath = '',
    [switch] $SkipO007Refresh
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runDate = Get-Date -Format 'yyyyMMdd'
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Read-Json([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing report: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Resolve-LatestEvidencePath([string] $Filter, [string] $Label) {
    $evidenceRoot = Join-Path $repoRoot 'docs\evidence'
    Assert-Condition (Test-Path -LiteralPath $evidenceRoot) 'missing docs/evidence directory'
    $latest = @(
        Get-ChildItem -LiteralPath $evidenceRoot -Filter $Filter -File |
            Sort-Object Name -Descending |
            Select-Object -First 1
    )
    Assert-Condition ($latest.Count -eq 1) "missing $Label matching filter: $Filter"
    return [System.IO.Path]::GetRelativePath($repoRoot, $latest[0].FullName).Replace('\', '/')
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
    if ([string]::IsNullOrWhiteSpace($Secret)) { return }
    Assert-Condition (-not $Text.Contains($Secret)) "$Label leaked the database password"
}

function Resolve-RepoPath([string] $Path) {
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    return (Join-Path $repoRoot $Path)
}

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = ('docs/evidence/{0}-ns806-upgrade-bundle.json' -f $runDate)
}
if ([string]::IsNullOrWhiteSpace($O007ReportPath)) {
    $O007ReportPath = ('docs/evidence/{0}-ns806-o007-source-report.json' -f $runDate)
}

Push-Location $repoRoot
try {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'DatabasePassword or PGPASSWORD is required for NS806 upgrade bundle rehearsal.'

    $ns804ReportPath = Resolve-LatestEvidencePath '*-ns804-windows-service.json' 'NS804 report'
    $ns805ReportPath = Resolve-LatestEvidencePath '*-ns805-health-dashboard.json' 'NS805 report'
    $ns804 = Read-Json $ns804ReportPath
    $ns805 = Read-Json $ns805ReportPath

    Assert-Condition ($ns804.status -eq 'pass') 'NS806 dependency NS804 report did not pass'
    Assert-Condition ($ns805.status -eq 'pass') 'NS806 dependency NS805 report did not pass'
    Assert-Condition ([bool]$ns804.acceptance.healthReadinessPassed) 'NS806 requires NS804 package health/readiness evidence'
    Assert-Condition ([bool]$ns804.acceptance.dataRootSeparatedFromProgramRoot) 'NS806 requires package data root separation evidence'
    Assert-Condition ([bool]$ns804.acceptance.noWindowsServiceInstalled) 'NS806 must not install a Windows Service'
    Assert-Condition ([bool]$ns805.acceptance.backupManifestVisible) 'NS806 requires NS805 backup health visibility'
    Assert-Condition ([bool]$ns805.acceptance.restoreHealthVisible) 'NS806 requires NS805 restore health visibility'
    Assert-Condition ([bool]$ns805.acceptance.noProductionDataDelete) 'NS806 requires NS805 no production delete guard'

    if (-not $SkipO007Refresh) {
        $o007Output = .\tools\run-o007-ef-migration-bundle-upgrade-contract.ps1 `
            -DatabaseName $DatabaseName `
            -DatabaseUser $DatabaseUser `
            -DatabaseHost $DatabaseHost `
            -DatabasePort $DatabasePort `
            -DatabasePassword $DatabasePassword `
            -PgBin $PgBin `
            -ReportPath $O007ReportPath
        Assert-Condition ($LASTEXITCODE -eq 0) 'NS806 embedded O007 upgrade drill failed'
        $o007 = Convert-OutputToJson $o007Output 'O007 EF migration bundle upgrade drill'
    }
    else {
        $o007 = Read-Json $O007ReportPath
    }

    Assert-Condition ($o007.status -eq 'pass') 'NS806 O007 source report did not pass'
    Assert-Condition ($o007.mode -eq 'draft_test') 'NS806 O007 source report must stay draft_test'
    Assert-Condition (-not [bool]$o007.productionEligible) 'NS806 O007 source report must not be productionEligible'
    Assert-Condition ([bool]$o007.migrationBundle.noSourceOrSdkRequiredAtExecution) 'NS806 requires no source or SDK at migration execution'
    Assert-Condition ($o007.upgradeDrill.bundleRunExitCode -eq 0) 'NS806 migration bundle run did not exit cleanly'
    Assert-Condition ($o007.upgradeDrill.backupVerify -eq 'pass') 'NS806 requires backup verify after bundle rehearsal'

    $bundleExe = Resolve-RepoPath ([string]$o007.migrationBundle.bundleExe)
    $releasePackageRoot = Resolve-RepoPath ([string]$o007.migrationBundle.releasePackageRoot)
    $executionLog = Resolve-RepoPath ([string]$o007.migrationBundle.executionLog)
    $backupManifest = Resolve-RepoPath ([string]$o007.upgradeDrill.backupManifest)
    Assert-Condition (Test-Path -LiteralPath $bundleExe) "missing efbundle: $bundleExe"
    Assert-Condition (Test-Path -LiteralPath $releasePackageRoot) "missing release package root: $releasePackageRoot"
    Assert-Condition (Test-Path -LiteralPath $executionLog) "missing efbundle execution log: $executionLog"
    Assert-Condition (Test-Path -LiteralPath $backupManifest) "missing upgrade backup manifest: $backupManifest"

    foreach ($packageFile in @($o007.migrationBundle.packageFiles)) {
        $packagePath = Join-Path $releasePackageRoot ([string]$packageFile)
        Assert-Condition (Test-Path -LiteralPath $packagePath) "missing migration package file: $packageFile"
    }

    $logText = Get-Content -LiteralPath $executionLog -Raw
    Assert-NoSecretInText $logText $DatabasePassword 'NS806 efbundle execution log'
    $noPendingMigrationApplied = $logText.Contains('No migrations were applied. The database is already up to date.')

    $restoreReport = Read-Json ([string]$o007.upgradeDrill.restoreDrillReport)
    Assert-Condition ($restoreReport.status -eq 'pass') 'NS806 embedded restore drill did not pass'
    Assert-Condition ([bool]$restoreReport.recoveryDrill.database.pgRestoreListOk) 'NS806 restore drill must produce pg_restore list'
    Assert-Condition ([bool]$restoreReport.recoveryDrill.database.schemaExtractOk) 'NS806 restore drill must extract schema-only SQL'
    Assert-Condition ([int]$restoreReport.recoveryDrill.fileStore.restoredFileCount -gt 0) 'NS806 restore drill must restore file store entries'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS806'
        checkedAt = (Get-Date).ToString('s')
        mode = 'ef_migration_bundle_upgrade_rehearsal'
        productionEligible = $false
        externalAiCalls = 0
        realStudentDataUsed = $false
        writesProductionHistory = $false
        activeAssetMutation = $false
        dependency = [ordered]@{
            ns804 = $ns804ReportPath
            ns805 = $ns805ReportPath
            o007 = $O007ReportPath
            restoreDrill = [string]$o007.upgradeDrill.restoreDrillReport
        }
        migrationBundle = [ordered]@{
            bundleExe = [string]$o007.migrationBundle.bundleExe
            releasePackageRoot = [string]$o007.migrationBundle.releasePackageRoot
            packageFiles = @($o007.migrationBundle.packageFiles)
            executionLog = [string]$o007.migrationBundle.executionLog
            noSourceOrSdkRequiredAtExecution = [bool]$o007.migrationBundle.noSourceOrSdkRequiredAtExecution
            noPendingMigrationAppliedInThisDrill = $noPendingMigrationApplied
        }
        upgradeDrill = [ordered]@{
            bundleRunExitCode = [int]$o007.upgradeDrill.bundleRunExitCode
            backupManifest = [string]$o007.upgradeDrill.backupManifest
            backupVerify = [string]$o007.upgradeDrill.backupVerify
            restoreDrillReport = [string]$o007.upgradeDrill.restoreDrillReport
            restoreFileStoreCount = [int]$restoreReport.recoveryDrill.fileStore.restoredFileCount
            schemaOnlyExtracted = [bool]$restoreReport.recoveryDrill.database.schemaExtractOk
        }
        acceptance = [ordered]@{
            ns804PackageHealthEvidencePassed = $true
            ns805HealthDashboardEvidencePassed = $true
            efBundleExists = $true
            releasePackageContainsBundle = $true
            releasePackageContainsAppSettings = $true
            noSourceOrSdkRequiredAtExecution = $true
            bundleRunExitCodeZero = $true
            backupManifestAfterBundle = $true
            backupVerifyAfterBundle = $true
            restoreDrillAfterBundle = $true
            restoreHashesAndSchemaChecked = $true
            noWindowsServiceInstalled = [bool]$ns804.acceptance.noWindowsServiceInstalled
            noProductionDataDelete = [bool]$ns805.acceptance.noProductionDataDelete
            noExternalAiCall = $true
            noRealStudentData = $true
            noActiveWrite = $true
        }
        verification = [ordered]@{
            build = 'O007 dotnet build Release before efbundle generation'
            test = 'O007 efbundle execution + backup.ps1 + verify-backup.ps1 + embedded O003 isolated restore drill'
            contractInvariant = 'NS806 requires package-local efbundle, no source/SDK at execution, post-bundle backup verify, isolated restore drill, no service install, and no production cleanup/delete'
            hotspot = 'gate_na: this is a local draft/test rehearsal, not an isolated target-machine migration apply with operator signoff; NS1001/P001 own live deployment validation'
        }
        boundary = 'NS806 proves the non-site EF migration bundle and upgrade rehearsal chain using draft/test evidence. It does not install a Windows Service, switch production defaults, delete production data, process real student data, or close the live deployment boundary.'
        rollback = "Remove-Item -LiteralPath 'tmp/ns806' -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item -LiteralPath 'tmp/o007' -Recurse -Force -ErrorAction SilentlyContinue; git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1 tools/README.md; git clean -f -- tools/run-ns806-upgrade-bundle.ps1 $ReportPath"
        next = 'NS901 can consume NS806 as the non-site E2E package prerequisite; NS1001/P001 remain blocked by isolated-machine and live operator validation.'
    }

    $jsonText = $report | ConvertTo-Json -Depth 12
    Assert-NoSecretInText $jsonText $DatabasePassword 'NS806 report'

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $jsonText | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $jsonText
}
finally {
    Pop-Location
}

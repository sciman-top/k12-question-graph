param(
    [string]$ManifestPath = 'D:\KQG_Backups\20260730-232646\manifest.json',
    [string]$ReportPath = 'docs/evidence/cek034-curriculum-exam-knowledge-evidence-suite.json',
    [string]$PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string]$DatabaseHost = '127.0.0.1',
    [int]$DatabasePort = 5432,
    [string]$DatabaseUser = 'postgres',
    [string]$DatabasePassword = $env:PGPASSWORD
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$reportFullPath = Join-Path $repoRoot $ReportPath
$runId = [Guid]::NewGuid().ToString('N')
$temporaryDatabase = "kqg_cek034_$($runId.Substring(0, 12))"
$temporaryRoot = Join-Path $repoRoot "tmp\cek034-$runId"
$logRoot = Join-Path $temporaryRoot 'logs'
$steps = [System.Collections.Generic.List[object]]::new()
$cleanup = [ordered]@{
    database = $temporaryDatabase
    databaseDropped = $false
    temporaryRoot = $temporaryRoot
    temporaryRootDeleted = $false
}
$isolatedDrill = $null
$supplyChain = $null
$evidenceInventory = $null
$failure = $null

. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

function Assert-Condition([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Convert-ToRelative([string]$Path) {
    return [System.IO.Path]::GetRelativePath($repoRoot, $Path).Replace('\', '/')
}

function Invoke-CheckedNative {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$LogPath
    )

    $parent = Split-Path -Parent $LogPath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $FilePath @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    $output | ForEach-Object { [string]$_ } | Set-Content -LiteralPath $LogPath -Encoding UTF8
    $output | ForEach-Object { Write-Host ([string]$_) }
    if ($exitCode -ne 0) {
        throw "$FilePath failed with exit code $exitCode; log=$LogPath"
    }

    return ($output | ForEach-Object { [string]$_ })
}

function Invoke-SuiteStep {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Phase,
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    Write-Host "[CEK-34][$Phase] $Name"
    $startedAt = (Get-Date).ToUniversalTime()
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $detail = & $Action
        $stopwatch.Stop()
        $steps.Add([ordered]@{
            name = $Name
            phase = $Phase
            status = 'pass'
            command = $Command
            startedAt = $startedAt.ToString('o')
            durationMs = $stopwatch.ElapsedMilliseconds
            detail = $detail
        }) | Out-Null
    }
    catch {
        $stopwatch.Stop()
        $steps.Add([ordered]@{
            name = $Name
            phase = $Phase
            status = 'fail'
            command = $Command
            startedAt = $startedAt.ToString('o')
            durationMs = $stopwatch.ElapsedMilliseconds
            error = $_.Exception.Message
        }) | Out-Null
        throw
    }
}

function Invoke-PsqlScalar {
    param(
        [Parameter(Mandatory)][string]$Database,
        [Parameter(Mandatory)][string]$Sql,
        [Parameter(Mandatory)][string]$LogName
    )

    $psql = Join-Path $PgBin 'psql.exe'
    $output = Invoke-CheckedNative -FilePath $psql -Arguments @(
        '-h', $DatabaseHost,
        '-p', [string]$DatabasePort,
        '-U', $DatabaseUser,
        '-d', $Database,
        '-v', 'ON_ERROR_STOP=1',
        '-tAc', $Sql
    ) -LogPath (Join-Path $logRoot $LogName)
    return (($output -join "`n").Trim())
}

function Assert-TableState {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Present,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Absent,
        [Parameter(Mandatory)][string]$Stage
    )

    foreach ($table in $Present) {
        $value = Invoke-PsqlScalar -Database $temporaryDatabase -Sql "select coalesce(to_regclass('public.$table')::text, '');" -LogName "$Stage-$table-present.log"
        Assert-Condition ($value -eq $table) "$Stage expected table to exist: $table (actual=$value)"
    }
    foreach ($table in $Absent) {
        $value = Invoke-PsqlScalar -Database $temporaryDatabase -Sql "select coalesce(to_regclass('public.$table')::text, '');" -LogName "$Stage-$table-absent.log"
        Assert-Condition ([string]::IsNullOrWhiteSpace($value)) "$Stage expected table to be absent: $table (actual=$value)"
    }
}

function Get-VulnerabilityCount($Document) {
    $count = 0
    foreach ($project in @($Document.projects)) {
        if ($null -eq $project) { continue }
        $frameworksProperty = $project.PSObject.Properties['frameworks']
        if ($null -eq $frameworksProperty -or $null -eq $frameworksProperty.Value) { continue }
        foreach ($framework in @($frameworksProperty.Value)) {
            if ($null -eq $framework) { continue }
            foreach ($packageGroup in @('topLevelPackages', 'transitivePackages')) {
                $packagesProperty = $framework.PSObject.Properties[$packageGroup]
                if ($null -eq $packagesProperty -or $null -eq $packagesProperty.Value) { continue }
                foreach ($package in @($packagesProperty.Value)) {
                    if ($null -eq $package) { continue }
                    $vulnerabilitiesProperty = $package.PSObject.Properties['vulnerabilities']
                    if ($null -eq $vulnerabilitiesProperty -or $null -eq $vulnerabilitiesProperty.Value) { continue }
                    $count += @($vulnerabilitiesProperty.Value).Count
                }
            }
        }
    }
    return $count
}

function Assert-TemporaryRootSafe {
    $allowedRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'tmp'))
    $resolvedTarget = [System.IO.Path]::GetFullPath($temporaryRoot)
    Assert-Condition ($resolvedTarget.StartsWith($allowedRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) "unsafe temporary root: $resolvedTarget"
    Assert-Condition ((Split-Path -Leaf $resolvedTarget).StartsWith('cek034-', [System.StringComparison]::OrdinalIgnoreCase)) "unexpected temporary root leaf: $resolvedTarget"
}

$previousPgPassword = $env:PGPASSWORD
$previousConnectionString = $env:KQG_CONNECTION_STRING

try {
    Assert-Condition (Test-Path -LiteralPath $ManifestPath) "backup manifest missing: $ManifestPath"
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'DatabasePassword or PGPASSWORD is required for the isolated restore drill'
    Assert-Condition ($temporaryDatabase -match '^kqg_cek034_[0-9a-f]{12}$') "unsafe temporary database name: $temporaryDatabase"
    Assert-TemporaryRootSafe
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $env:PGPASSWORD = $DatabasePassword

    Invoke-SuiteStep -Name 'api-build' -Phase 'build' -Command 'dotnet restore/build apps/api/K12QuestionGraph.Api.csproj' -Action {
        Invoke-CheckedNative -FilePath 'dotnet' -Arguments @('restore', 'apps/api/K12QuestionGraph.Api.csproj') -LogPath (Join-Path $logRoot 'api-restore.log') | Out-Null
        Invoke-CheckedNative -FilePath 'dotnet' -Arguments @('build', 'apps/api/K12QuestionGraph.Api.csproj', '--no-restore') -LogPath (Join-Path $logRoot 'api-build.log') | Out-Null
        return [ordered]@{ project = 'apps/api/K12QuestionGraph.Api.csproj'; warnings = 0; errors = 0 }
    }

    Invoke-SuiteStep -Name 'web-build' -Phase 'build' -Command 'npm run build (apps/web)' -Action {
        Push-Location (Join-Path $repoRoot 'apps/web')
        try {
            Invoke-CheckedNative -FilePath 'npm.cmd' -Arguments @('run', 'build') -LogPath (Join-Path $logRoot 'web-build.log') | Out-Null
        }
        finally { Pop-Location }
        return [ordered]@{ project = 'apps/web'; build = 'pass' }
    }

    Invoke-SuiteStep -Name 'api-tests' -Phase 'test' -Command 'dotnet test tests/api/K12QuestionGraph.Api.Tests/K12QuestionGraph.Api.Tests.csproj' -Action {
        $output = (Invoke-CheckedNative -FilePath 'dotnet' -Arguments @('test', 'tests/api/K12QuestionGraph.Api.Tests/K12QuestionGraph.Api.Tests.csproj') -LogPath (Join-Path $logRoot 'api-tests.log')) -join "`n"
        $match = [regex]::Match($output, '(?:总计|Total tests):\s*(\d+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        Assert-Condition $match.Success 'could not parse API test total'
        $total = [int]$match.Groups[1].Value
        Assert-Condition ($total -ge 78) "API test total regressed below 78: $total"
        return [ordered]@{ suite = 'api'; total = $total; failed = 0 }
    }

    Invoke-SuiteStep -Name 'worker-tests' -Phase 'test' -Command 'python -m pytest -q tests/workers' -Action {
        $output = (Invoke-CheckedNative -FilePath 'python' -Arguments @('-m', 'pytest', '-q', 'tests/workers') -LogPath (Join-Path $logRoot 'worker-tests.log')) -join "`n"
        $match = [regex]::Match($output, '(\d+)\s+passed', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        Assert-Condition $match.Success 'could not parse worker test total'
        $total = [int]$match.Groups[1].Value
        Assert-Condition ($total -ge 177) "worker test total regressed below 177: $total"
        return [ordered]@{ suite = 'workers'; total = $total; failed = 0 }
    }

    Invoke-SuiteStep -Name 'web-tests-and-lint' -Phase 'test' -Command 'npm test; npm run lint (apps/web)' -Action {
        Push-Location (Join-Path $repoRoot 'apps/web')
        try {
            $output = (Invoke-CheckedNative -FilePath 'npm.cmd' -Arguments @('test') -LogPath (Join-Path $logRoot 'web-tests.log')) -join "`n"
            Invoke-CheckedNative -FilePath 'npm.cmd' -Arguments @('run', 'lint') -LogPath (Join-Path $logRoot 'web-lint.log') | Out-Null
        }
        finally { Pop-Location }
        $match = [regex]::Match($output, 'Tests\s+(\d+)\s+passed', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        Assert-Condition $match.Success 'could not parse Web test total'
        $total = [int]$match.Groups[1].Value
        Assert-Condition ($total -ge 36) "Web test total regressed below 36: $total"
        return [ordered]@{ suite = 'web'; total = $total; failed = 0; lint = 'pass' }
    }

    Invoke-SuiteStep -Name 'schema-and-evidence-contracts' -Phase 'contract/invariant' -Command 'parse CEK schemas/configs and verify CEK-01..33 evidence references' -Action {
        $jsonPaths = @(
            'schemas/curriculum_requirement.schema.json',
            'schemas/curriculum_alignment.schema.json',
            'schemas/assessment_target.schema.json',
            'schemas/observed_performance_evidence.schema.json',
            'schemas/observed_error_evidence.schema.json',
            'schemas/regional_exam_point_profile.schema.json',
            'configs/knowledge/curriculum-standard-regimes.json',
            'configs/knowledge/guangzhou-exam-source-role-map.json',
            'configs/knowledge/guangzhou-profile-comparability.json',
            'configs/knowledge/error-pattern-taxonomy.json'
        )
        foreach ($path in $jsonPaths) {
            $fullPath = Join-Path $repoRoot $path
            Assert-Condition (Test-Path -LiteralPath $fullPath) "missing JSON contract: $path"
            Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json | Out-Null
        }

        $todoPath = Join-Path $repoRoot 'tasks/curriculum-exam-knowledge-extraction-todo.md'
        $todoText = Get-Content -LiteralPath $todoPath -Raw
        $references = [regex]::Matches($todoText, '`(docs/evidence/[^`]+)`') |
            ForEach-Object { $_.Groups[1].Value } |
            Sort-Object -Unique
        $missing = @($references | Where-Object { -not (Test-Path -LiteralPath (Join-Path $repoRoot $_)) })
        Assert-Condition ($missing.Count -eq 0) "missing CEK evidence references: $($missing -join ', ')"
        Assert-Condition ($todoText -match 'REAL005=not_closed') 'CEK task list lost REAL005=not_closed boundary'
        Assert-Condition ($todoText -match 'productionEligible=false') 'CEK task list lost productionEligible=false boundary'
        $script:evidenceInventory = [ordered]@{ jsonContracts = $jsonPaths.Count; referencedEvidence = @($references).Count; missing = $missing }
        return $script:evidenceInventory
    }

    Invoke-SuiteStep -Name 'roadmap-guard' -Phase 'contract/invariant' -Command 'pwsh -File tools/run-roadmap-guard.ps1' -Action {
        Invoke-CheckedNative -FilePath 'pwsh' -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools/run-roadmap-guard.ps1') -LogPath (Join-Path $logRoot 'roadmap-guard.log') | Out-Null
        return [ordered]@{ guard = 'roadmap'; result = 'pass' }
    }

    Invoke-SuiteStep -Name 'reference-basis-guard' -Phase 'contract/invariant' -Command 'pwsh -File tools/run-reference-basis-guard.ps1' -Action {
        Invoke-CheckedNative -FilePath 'pwsh' -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools/run-reference-basis-guard.ps1') -LogPath (Join-Path $logRoot 'reference-basis-guard.log') | Out-Null
        return [ordered]@{ guard = 'reference-basis'; result = 'pass' }
    }

    Invoke-SuiteStep -Name 'isolated-backup-restore-and-migrations' -Phase 'contract/invariant' -Command 'verify manifest; restore unique DB/FileStore; CEK-15/19 Down/Up; verify hashes; cleanup' -Action {
        $verifyOutput = & (Join-Path $PSScriptRoot 'verify-backup.ps1') -ManifestPath $ManifestPath | ConvertFrom-Json
        Assert-Condition ($verifyOutput.status -eq 'ok') 'verify-backup.ps1 did not return status=ok'
        $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json

        $productionBefore = Invoke-PsqlScalar -Database ([string]$manifest.database.databaseName) -Sql "select json_build_object('activeAssets',(select count(*) from domain_asset_versions where status='active'),'eligibleTargets',(select count(*) from assessment_targets where production_eligible),'eligibleObserved',(select count(*) from observed_performance_evidence where production_eligible),'pendingTargets',(select count(*) from assessment_targets where review_status='pending_review'))::text;" -LogName 'production-before.log'

        Invoke-PsqlScalar -Database 'postgres' -Sql "create database $temporaryDatabase;" -LogName 'create-temporary-database.log' | Out-Null
        $env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$temporaryDatabase;Username=$DatabaseUser;Password=$DatabasePassword"

        $restoreOutput = & (Join-Path $PSScriptRoot 'restore.ps1') -ManifestPath $ManifestPath -TargetDataRoot $temporaryRoot -PgBin $PgBin -DatabaseName $temporaryDatabase -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabaseUser $DatabaseUser -ApplyDatabase -ApplyFileStore -DryRun:$false | ConvertFrom-Json
        Assert-Condition ($restoreOutput.status -eq 'ok') 'restore.ps1 did not return status=ok'

        $restoredFileRoot = Join-Path $temporaryRoot 'file_store'
        $verifiedFiles = 0
        foreach ($file in @($manifest.fileStore.files)) {
            $target = Join-Path $restoredFileRoot ([string]$file.path)
            Assert-Condition (Test-Path -LiteralPath $target) "restored FileStore file missing: $($file.path)"
            $actualHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
            Assert-Condition ($actualHash -eq [string]$file.sha256) "restored FileStore hash mismatch: $($file.path)"
            $verifiedFiles++
        }

        $allTables = @('assessment_targets', 'assessment_target_knowledge_mappings', 'curriculum_alignments', 'observed_performance_evidence', 'observed_error_evidence', 'teaching_recommendations')
        Assert-TableState -Present $allTables -Absent @() -Stage 'restored-latest'

        Invoke-CheckedNative -FilePath 'dotnet' -Arguments @('ef', 'database', 'update', '20260728122942_AddEvidenceAnchorMetadataForCEK004', '--project', 'apps/api/K12QuestionGraph.Api.csproj', '--startup-project', 'apps/api/K12QuestionGraph.Api.csproj', '--no-build') -LogPath (Join-Path $logRoot 'migration-down-to-cek004.log') | Out-Null
        Assert-TableState -Present @() -Absent $allTables -Stage 'down-cek004'

        Invoke-CheckedNative -FilePath 'dotnet' -Arguments @('ef', 'database', 'update', '20260729035809_AddAssessmentTargetEvidenceModelForCEK015', '--project', 'apps/api/K12QuestionGraph.Api.csproj', '--startup-project', 'apps/api/K12QuestionGraph.Api.csproj', '--no-build') -LogPath (Join-Path $logRoot 'migration-up-cek015.log') | Out-Null
        Assert-TableState -Present @('assessment_targets', 'assessment_target_knowledge_mappings', 'curriculum_alignments') -Absent @('observed_performance_evidence', 'observed_error_evidence', 'teaching_recommendations') -Stage 'up-cek015'

        Invoke-CheckedNative -FilePath 'dotnet' -Arguments @('ef', 'database', 'update', '20260729142258_AddObservedExamEvidenceModelForCEK019', '--project', 'apps/api/K12QuestionGraph.Api.csproj', '--startup-project', 'apps/api/K12QuestionGraph.Api.csproj', '--no-build') -LogPath (Join-Path $logRoot 'migration-up-cek019.log') | Out-Null
        Assert-TableState -Present $allTables -Absent @() -Stage 'up-cek019'

        $migrationHead = Invoke-PsqlScalar -Database $temporaryDatabase -Sql 'select max(migration_id) from "__EFMigrationsHistory";' -LogName 'migration-head.log'
        Assert-Condition ($migrationHead -eq '20260729142258_AddObservedExamEvidenceModelForCEK019') "unexpected migration head: $migrationHead"

        $productionAfter = Invoke-PsqlScalar -Database ([string]$manifest.database.databaseName) -Sql "select json_build_object('activeAssets',(select count(*) from domain_asset_versions where status='active'),'eligibleTargets',(select count(*) from assessment_targets where production_eligible),'eligibleObserved',(select count(*) from observed_performance_evidence where production_eligible),'pendingTargets',(select count(*) from assessment_targets where review_status='pending_review'))::text;" -LogName 'production-after.log'
        Assert-Condition ($productionBefore -eq $productionAfter) 'production boundary counters changed during isolated drill'

        $script:isolatedDrill = [ordered]@{
            sourceManifest = $ManifestPath
            sourceDatabase = [string]$manifest.database.databaseName
            temporaryDatabase = $temporaryDatabase
            databaseDumpSha256 = [string]$manifest.database.sha256
            restoredFileCount = $verifiedFiles
            restoredFileBytes = (@($manifest.fileStore.files) | Measure-Object -Property bytes -Sum).Sum
            restoredHashesVerified = $true
            migrationDownTarget = '20260728122942_AddEvidenceAnchorMetadataForCEK004'
            migrationUpTargets = @('20260729035809_AddAssessmentTargetEvidenceModelForCEK015', '20260729142258_AddObservedExamEvidenceModelForCEK019')
            migrationHead = $migrationHead
            productionBoundaryBefore = ($productionBefore | ConvertFrom-Json)
            productionBoundaryAfter = ($productionAfter | ConvertFrom-Json)
            activeWrite = $false
            productionEligible = $false
        }
        return $script:isolatedDrill
    }

    Invoke-SuiteStep -Name 'supply-chain' -Phase 'contract/invariant' -Command 'dotnet list --vulnerable (API/tests); npm audit --omit=dev; verify Microsoft.OpenApi package metadata' -Action {
        $apiJsonText = (Invoke-CheckedNative -FilePath 'dotnet' -Arguments @('list', 'apps/api/K12QuestionGraph.Api.csproj', 'package', '--include-transitive', '--vulnerable', '--format', 'json') -LogPath (Join-Path $logRoot 'api-vulnerabilities.json')) -join "`n"
        $testJsonText = (Invoke-CheckedNative -FilePath 'dotnet' -Arguments @('list', 'tests/api/K12QuestionGraph.Api.Tests/K12QuestionGraph.Api.Tests.csproj', 'package', '--include-transitive', '--vulnerable', '--format', 'json') -LogPath (Join-Path $logRoot 'test-vulnerabilities.json')) -join "`n"
        $apiVulnerabilities = Get-VulnerabilityCount ($apiJsonText | ConvertFrom-Json)
        $testVulnerabilities = Get-VulnerabilityCount ($testJsonText | ConvertFrom-Json)
        Assert-Condition ($apiVulnerabilities -eq 0) "API NuGet vulnerabilities remain: $apiVulnerabilities"
        Assert-Condition ($testVulnerabilities -eq 0) "test NuGet vulnerabilities remain: $testVulnerabilities"

        Push-Location (Join-Path $repoRoot 'apps/web')
        try {
            $npmAuditText = (Invoke-CheckedNative -FilePath 'npm.cmd' -Arguments @('audit', '--omit=dev', '--json') -LogPath (Join-Path $logRoot 'npm-audit.json')) -join "`n"
        }
        finally { Pop-Location }
        $npmAudit = $npmAuditText | ConvertFrom-Json
        $npmVulnerabilities = [int]$npmAudit.metadata.vulnerabilities.total
        Assert-Condition ($npmVulnerabilities -eq 0) "npm production vulnerabilities remain: $npmVulnerabilities"

        $nuspecPath = Join-Path $env:USERPROFILE '.nuget\packages\microsoft.openapi\2.7.5\microsoft.openapi.nuspec'
        Assert-Condition (Test-Path -LiteralPath $nuspecPath) "offline package cache missing: $nuspecPath"
        [xml]$nuspec = Get-Content -LiteralPath $nuspecPath -Raw
        $license = [string]$nuspec.package.metadata.license.InnerText
        Assert-Condition ($license -eq 'MIT') "unexpected Microsoft.OpenApi license: $license"
        $script:supplyChain = [ordered]@{
            dependencyChange = $true
            package = 'Microsoft.OpenApi'
            previousResolvedVersion = '2.0.0'
            resolvedVersion = '2.7.5'
            advisory = 'GHSA-v5pm-xwqc-g5wc'
            apiVulnerabilities = $apiVulnerabilities
            testVulnerabilities = $testVulnerabilities
            npmProductionVulnerabilities = $npmVulnerabilities
            license = $license
            windowsCompatibility = 'API build, 78+ API tests, and isolated Windows runtime OpenAPI probe are required evidence; suite build/tests passed.'
            offline = [ordered]@{ cachePresent = $true; nuspec = $nuspecPath }
            rollback = 'Remove the explicit Microsoft.OpenApi PackageReference only after a patched compatible transitive version is resolved, then restore/build/test and rerun vulnerability scans.'
        }
        return $script:supplyChain
    }

    $steps.Add([ordered]@{
        name = 'hotspot-manual-boundary'
        phase = 'hotspot'
        status = 'pass_with_open_external_acceptance'
        reviewed = @('CEK-33 desktop/mobile browser evidence', 'candidate preview cannot enter active paper basket', 'review undo returns candidates to pending_review', 'source page links and analysis fail-closed states')
        open = @('real teacher sign-off', 'identity authorization', 'school network', 'isolated machine', 'production active switch', 'REAL005 closure')
    }) | Out-Null
}
catch {
    $failure = $_.Exception.Message
}
finally {
    $env:KQG_CONNECTION_STRING = $previousConnectionString

    try {
        $psql = Join-Path $PgBin 'psql.exe'
        $dropdb = Join-Path $PgBin 'dropdb.exe'
        if (Test-Path -LiteralPath $psql) {
            & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d postgres -v ON_ERROR_STOP=1 -tAc "select pg_terminate_backend(pid) from pg_stat_activity where datname='$temporaryDatabase' and pid <> pg_backend_pid();" 2>&1 | Out-Null
        }
        if (Test-Path -LiteralPath $dropdb) {
            & $dropdb -h $DatabaseHost -p $DatabasePort -U $DatabaseUser --if-exists $temporaryDatabase 2>&1 | Out-Null
            $cleanup.databaseDropped = ($LASTEXITCODE -eq 0)
        }
    }
    catch {
        $cleanup.databaseDropError = $_.Exception.Message
    }

    try {
        Assert-TemporaryRootSafe
        if (Test-Path -LiteralPath $temporaryRoot) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
        }
        $cleanup.temporaryRootDeleted = -not (Test-Path -LiteralPath $temporaryRoot)
    }
    catch {
        $cleanup.temporaryRootDeleteError = $_.Exception.Message
    }

    $env:PGPASSWORD = $previousPgPassword

    if (-not $cleanup.databaseDropped -and $null -eq $failure) {
        $failure = "failed to drop isolated database: $temporaryDatabase"
    }
    if (-not $cleanup.temporaryRootDeleted -and $null -eq $failure) {
        $failure = "failed to delete isolated temporary root: $temporaryRoot"
    }

    $status = if ($null -ne $failure) { 'fail' } else { 'pass' }
    $report = [ordered]@{
        schemaVersion = 1
        taskId = 'CEK-34'
        generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        status = $status
        cek34Complete = ($status -eq 'pass')
        failure = $failure
        fixedOrder = @('build', 'test/full', 'contract/invariant', 'hotspot')
        steps = $steps
        evidenceInventory = $evidenceInventory
        isolatedDrill = $isolatedDrill
        supplyChain = $supplyChain
        cleanup = $cleanup
        truthBoundary = [ordered]@{
            candidateStatus = 'pending_review'
            productionEligible = $false
            productionActiveSwitched = $false
            realTeacherSignoff = $false
            identityAuthorization = $false
            isolatedMachineAccepted = $false
            schoolNetworkAccepted = $false
            real005 = 'not_closed'
            release = 'No-Go'
        }
        next = if ($status -eq 'pass') { 'CEK domain verification passed. Run the canonical Release verifier separately only when release authorization is required.' } else { 'Fix the failed step, confirm cleanup, and rerun the suite.' }
        rollback = [ordered]@{
            code = 'Revert only the CEK-34 suite and explicit dependency override after restoring a secure compatible dependency graph.'
            data = 'The unique temporary database and FileStore root are deleted in finally; production data is not a rollback target for this suite.'
        }
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 12
}

if ($null -ne $failure) {
    throw "CEK-34 suite failed: $failure"
}

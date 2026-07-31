param(
    [Parameter(Mandatory)]
    [string] $BackupManifest,
    [string] $ReportPath = 'docs\evidence\cek027-curriculum-exam-c002r-isolated-drill.json',
    [string] $PlanPath = 'docs\evidence\cek024-curriculum-exam-c002r-plan.json',
    [string] $IsolationRoot = 'D:\KQG_Data\isolated',
    [string] $Reviewer = 'cek027_drill_reviewer',
    [string] $Reason = 'CEK-27 isolated rollback rehearsal; not teacher acceptance',
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabaseUser = 'postgres',
    [string] $ProductionDatabaseName = 'k12_question_graph',
    [string] $DatabasePassword = $env:PGPASSWORD
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$verifyBackupScript = Join-Path $PSScriptRoot 'verify-backup.ps1'
$restoreScript = Join-Path $PSScriptRoot 'restore.ps1'
$drillScript = Join-Path $PSScriptRoot 'curriculum_exam_c002r_drill.py'
$expectedIsolationRoot = [System.IO.Path]::GetFullPath('D:\KQG_Data\isolated').TrimEnd('\')
$resolvedIsolationRoot = [System.IO.Path]::GetFullPath($IsolationRoot).TrimEnd('\')

. (Join-Path $PSScriptRoot 'dotenv.ps1')
. (Join-Path $PSScriptRoot 'database-env.ps1')
Import-KqgDotEnv -RepoRoot $repoRoot
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Resolve-RepoPath([string] $Path) {
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
}

Assert-Condition ($resolvedIsolationRoot -ieq $expectedIsolationRoot) 'CEK-27 isolation root must be exactly D:\KQG_Data\isolated.'
Assert-Condition (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'PGPASSWORD/DatabasePassword is required for the isolated database lifecycle.'
Assert-Condition (-not [string]::IsNullOrWhiteSpace($Reviewer)) 'CEK-27 drill reviewer is required.'
Assert-Condition (-not [string]::IsNullOrWhiteSpace($Reason)) 'CEK-27 drill reason is required.'

$backupManifestPath = (Get-Item -LiteralPath $BackupManifest).FullName
$planFile = Resolve-RepoPath $PlanPath
$reportFile = Resolve-RepoPath $ReportPath
$manifest = Get-Content -LiteralPath $backupManifestPath -Raw | ConvertFrom-Json
$manifestRoot = Split-Path -Parent $backupManifestPath
$databaseDumpPath = Join-Path $manifestRoot ([string]$manifest.database.dump)

Assert-Condition (Test-Path -LiteralPath $planFile) "CEK-24 plan is missing: $planFile"
Assert-Condition (Test-Path -LiteralPath $databaseDumpPath) "backup database dump is missing: $databaseDumpPath"

$createdb = Join-Path $PgBin 'createdb.exe'
$dropdb = Join-Path $PgBin 'dropdb.exe'
$pgRestore = Join-Path $PgBin 'pg_restore.exe'
$psql = Join-Path $PgBin 'psql.exe'
foreach ($tool in @($createdb, $dropdb, $pgRestore, $psql)) {
    Assert-Condition (Test-Path -LiteralPath $tool) "PostgreSQL tool is missing: $tool"
}

& $verifyBackupScript -ManifestPath $backupManifestPath | Out-Null

$runToken = "{0}_{1}" -f (Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss'), $PID
$isolatedDatabaseName = "kqg_cek027_$runToken"
$isolatedDataRoot = Join-Path $resolvedIsolationRoot "cek027-$runToken"
$isolatedFileStore = Join-Path $isolatedDataRoot 'file_store'
$isolationMarker = Join-Path $isolatedDataRoot '.cek027-isolated'
$isolatedDataRootFull = [System.IO.Path]::GetFullPath($isolatedDataRoot)

Assert-Condition ($isolatedDatabaseName -match '^kqg_cek027_\d{8}_\d{6}_\d+$') 'generated isolated database name failed the CEK-27 allowlist.'
Assert-Condition ($isolatedDataRootFull.StartsWith("$resolvedIsolationRoot\", [System.StringComparison]::OrdinalIgnoreCase)) 'generated isolated data root escaped the isolation root.'
Assert-Condition ((Split-Path -Leaf $isolatedDataRootFull) -like 'cek027-*') 'generated isolated data root failed the CEK-27 prefix guard.'

function Get-ProductionFingerprint {
    $query = @'
select md5(coalesce(string_agg(scope || ':' || row_id || ':' || payload, E'\n' order by scope,row_id),''))
from (
  select 'asset' as scope, id::text as row_id, to_jsonb(t)::text as payload
  from domain_asset_versions t
  where status='active' or source_evidence->>'importKey' in ('cek009_curriculum_requirements_2022_2025_v1','cek023_regional_exam_profile_candidate_v1')
  union all
  select 'mapping', id::text, to_jsonb(t)::text from domain_asset_mappings t
  where evidence->>'importKey'='cek009_curriculum_requirements_2022_2025_v1'
  union all
  select 'target', id::text, to_jsonb(t)::text from assessment_targets t
  where metadata->>'importKey'='cek016_guangzhou_assessment_targets_v1'
  union all
  select 'alignment', id::text, to_jsonb(t)::text from curriculum_alignments t
  where evidence->>'importKey'='cek016_guangzhou_assessment_targets_v1'
  union all
  select 'migration', id::text, to_jsonb(t)::text from domain_asset_migrations t
  where migration_key in ('cek009_curriculum_requirements_2022_2025_v1','cek023_regional_exam_profile_candidate_v1')
  union all
  select 'question', id::text, to_jsonb(t)::text from question_items t
) rows;
'@
    $result = $query | & $psql `
        -h $DatabaseHost `
        -p $DatabasePort `
        -U $DatabaseUser `
        -d $ProductionDatabaseName `
        -v ON_ERROR_STOP=1 `
        -At
    if ($LASTEXITCODE -ne 0) {
        throw "failed to read the production baseline fingerprint with exit code $LASTEXITCODE"
    }
    return ([string]$result).Trim()
}

$productionFingerprintBefore = Get-ProductionFingerprint
$databaseCreated = $false
$dataRootCreated = $false
$drillError = $null
$cleanup = [ordered]@{
    databaseDropped = $false
    dataRootRemoved = $false
}

try {
    New-Item -ItemType Directory -Path $isolatedDataRootFull -Force | Out-Null
    $dataRootCreated = $true
    Set-Content -LiteralPath $isolationMarker -Value "CEK-27:$isolatedDatabaseName" -Encoding ASCII

    $existsQuery = "select count(*) from pg_database where datname='$isolatedDatabaseName';"
    $existingCount = $existsQuery | & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d postgres -v ON_ERROR_STOP=1 -At
    Assert-Condition (([string]$existingCount).Trim() -eq '0') "isolated database already exists: $isolatedDatabaseName"

    & $createdb -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -T template0 -E UTF8 $isolatedDatabaseName
    if ($LASTEXITCODE -ne 0) {
        throw "createdb failed with exit code $LASTEXITCODE"
    }
    $databaseCreated = $true

    & $pgRestore `
        -h $DatabaseHost `
        -p $DatabasePort `
        -U $DatabaseUser `
        -d $isolatedDatabaseName `
        --no-owner `
        --no-privileges `
        --exit-on-error `
        $databaseDumpPath
    if ($LASTEXITCODE -ne 0) {
        throw "pg_restore failed with exit code $LASTEXITCODE"
    }

    & $restoreScript `
        -ManifestPath $backupManifestPath `
        -TargetDataRoot $isolatedDataRootFull `
        -PgBin $PgBin `
        -DatabaseName $isolatedDatabaseName `
        -DatabaseHost $DatabaseHost `
        -DatabasePort $DatabasePort `
        -DatabaseUser $DatabaseUser `
        -ApplyFileStore `
        -DryRun:$false | Out-Null

    Assert-Condition (Test-Path -LiteralPath $isolatedFileStore) 'isolated FileStore restore did not create the target root.'

    $connectionString = "host=$DatabaseHost port=$DatabasePort dbname=$isolatedDatabaseName user=$DatabaseUser"
    $pythonArgs = @(
        $drillScript,
        '--connection-string', $connectionString,
        '--database-name', $isolatedDatabaseName,
        '--file-store-root', $isolatedFileStore,
        '--backup-manifest', $backupManifestPath,
        '--plan-path', $planFile,
        '--report-path', $reportFile,
        '--reviewer', $Reviewer,
        '--reason', $Reason
    )
    $pythonOutput = @(& python @pythonArgs 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "CEK-27 Python drill failed: $($pythonOutput -join [Environment]::NewLine)"
    }
}
catch {
    $drillError = $_
}
finally {
    if ($databaseCreated) {
        Assert-Condition ($isolatedDatabaseName -match '^kqg_cek027_\d{8}_\d{6}_\d+$') 'refusing to drop a database outside the CEK-27 allowlist.'
        & $dropdb -h $DatabaseHost -p $DatabasePort -U $DatabaseUser --force $isolatedDatabaseName
        if ($LASTEXITCODE -ne 0) {
            if ($null -eq $drillError) {
                $drillError = [System.InvalidOperationException]::new("dropdb failed with exit code $LASTEXITCODE")
            }
        }
        else {
            $cleanup.databaseDropped = $true
        }
    }

    if ($dataRootCreated -and (Test-Path -LiteralPath $isolatedDataRootFull)) {
        $cleanupPath = [System.IO.Path]::GetFullPath($isolatedDataRootFull)
        $cleanupAllowed = $cleanupPath.StartsWith("$resolvedIsolationRoot\", [System.StringComparison]::OrdinalIgnoreCase) -and
            (Split-Path -Leaf $cleanupPath) -like 'cek027-*' -and
            (Test-Path -LiteralPath $isolationMarker)
        Assert-Condition $cleanupAllowed 'refusing recursive cleanup outside a marked CEK-27 isolation directory.'
        Remove-Item -LiteralPath $cleanupPath -Recurse -Force
        $cleanup.dataRootRemoved = -not (Test-Path -LiteralPath $cleanupPath)
    }
}

$productionFingerprintAfter = Get-ProductionFingerprint
Assert-Condition ($productionFingerprintBefore -eq $productionFingerprintAfter) 'production database fingerprint changed during CEK-27 isolation drill.'

if ($null -ne $drillError) {
    throw $drillError
}

Assert-Condition (Test-Path -LiteralPath $reportFile) "CEK-27 report was not written: $reportFile"
$report = Get-Content -LiteralPath $reportFile -Raw | ConvertFrom-Json
$report | Add-Member -NotePropertyName isolationLifecycle -NotePropertyValue ([ordered]@{
    generatedDatabase = $isolatedDatabaseName
    generatedDataRoot = $isolatedDataRootFull
    databaseDropped = $cleanup.databaseDropped
    dataRootRemoved = $cleanup.dataRootRemoved
    productionFingerprintBefore = $productionFingerprintBefore
    productionFingerprintAfter = $productionFingerprintAfter
    productionFingerprintUnchanged = ($productionFingerprintBefore -eq $productionFingerprintAfter)
}) -Force
$report | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $reportFile -Encoding UTF8

Assert-Condition ($report.status -eq 'pass') 'CEK-27 report status is not pass.'
Assert-Condition ($report.fingerprints.rollbackParity -eq $true) 'CEK-27 database rollback parity failed.'
Assert-Condition ($report.fileStore.parity -eq $true) 'CEK-27 FileStore parity failed.'
Assert-Condition ($report.productionDecision.decision -eq 'no_go') 'CEK-27 must not emit a production Go decision.'
Assert-Condition ($cleanup.databaseDropped -and $cleanup.dataRootRemoved) 'CEK-27 temporary isolation cleanup is incomplete.'

[ordered]@{
    status = 'pass'
    taskId = 'CEK-27'
    report = $reportFile
    reviewedAssets = $report.stages.reviewed.reviewed_assets
    activeAssets = $report.stages.active.revision_active_assets
    activeTargets = $report.stages.active.active_targets
    activeAlignments = $report.stages.active.active_alignments
    approvedMappings = $report.stages.active.approved_mappings
    rollbackParity = $report.fingerprints.rollbackParity
    fileStoreParity = $report.fileStore.parity
    productionDecision = $report.productionDecision.decision
    productionFingerprintUnchanged = $report.isolationLifecycle.productionFingerprintUnchanged
    temporaryDatabaseDropped = $report.isolationLifecycle.databaseDropped
    temporaryDataRootRemoved = $report.isolationLifecycle.dataRootRemoved
} | ConvertTo-Json -Depth 6

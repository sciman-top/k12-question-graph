param(
    [Parameter(Mandatory)]
    [string] $BackupManifest,
    [string] $StageReport = 'docs\evidence\20260726-guangzhou-physics-source-batch-stage.json',
    [string] $Output = 'docs\evidence\20260726-guangzhou-physics-v2-prewrite-backup.json',
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabaseUser = 'postgres',
    [string] $DatabasePassword = $env:PGPASSWORD
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

function Get-LowerSha256([string] $Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-Json([object] $Value, [string] $Path) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for the prewrite source mapping snapshot'
}

$manifestItem = Get-Item -LiteralPath $BackupManifest
$backupDir = $manifestItem.DirectoryName
$manifest = Get-Content -LiteralPath $manifestItem.FullName -Raw | ConvertFrom-Json
$databaseDump = Join-Path $backupDir ([string] $manifest.database.dump)
$stageReportPath = Join-Path $repoRoot $StageReport
$stage = Get-Content -LiteralPath $stageReportPath -Raw | ConvertFrom-Json
if ($stage.status -ne 'pass' -or $stage.mode -notin @('dry_run', 'apply') -or $stage.physicalFileCount -ne 32) {
    throw 'T1 source stage evidence is missing or invalid'
}

Push-Location $repoRoot
try {
    $verification = & (Join-Path $PSScriptRoot 'verify-backup.ps1') -ManifestPath $manifestItem.FullName | ConvertFrom-Json
    $restoreDryRun = & (Join-Path $PSScriptRoot 'restore.ps1') `
        -ManifestPath $manifestItem.FullName `
        -ApplyDatabase `
        -ApplyFileStore | ConvertFrom-Json
}
finally {
    Pop-Location
}
if ($verification.status -ne 'ok' -or $restoreDryRun.status -ne 'ok' -or $restoreDryRun.mode -ne 'dry_run') {
    throw 'Backup verification or restore dry-run did not pass'
}

$psql = Join-Path $PgBin 'psql.exe'
if (-not (Test-Path -LiteralPath $psql)) {
    throw "psql not found: $psql"
}

$sql = @'
select json_build_object(
  'schemaVersion', '1.0',
  'capturedAt', current_timestamp,
  'database', current_database(),
  'relevantSourceDocumentCount', count(*),
  'sourceDocuments', coalesce(
    json_agg(
      json_build_object(
        'sourceDocumentId', sd.id,
        'fileAssetId', fa.id,
        'materialBatchKey', sd.material_batch_key,
        'sourceType', sd.source_type,
        'sourceTitle', sd.source_title,
        'region', sd.region,
        'year', sd.year,
        'originalFileName', fa.original_file_name,
        'relativePath', fa.relative_path,
        'sha256', fa.sha256,
        'sizeBytes', fa.size_bytes,
        'createdAt', sd.created_at
      ) order by sd.year, sd.source_type, sd.source_title, sd.id
    ) filter (where sd.id is not null),
    '[]'::json
  )
)
from source_documents sd
join file_assets fa on fa.id = sd.file_asset_id
where (sd.region = 'Guangzhou' and sd.year between 2015 and 2025)
   or sd.material_batch_key like 'guangzhou_physics%';
'@
$snapshotJson = & $psql `
    -h $DatabaseHost `
    -p $DatabasePort `
    -U $DatabaseUser `
    -d $DatabaseName `
    -At `
    -v ON_ERROR_STOP=1 `
    -c $sql
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string] $snapshotJson)) {
    throw 'Failed to export the existing Guangzhou source mapping snapshot'
}
$snapshot = ($snapshotJson -join "`n") | ConvertFrom-Json

$snapshotPath = Join-Path $backupDir 'guangzhou-physics-v2-source-mapping-before.json'
Write-Json -Value $snapshot -Path $snapshotPath
$restoreCommand = "pwsh -NoProfile -ExecutionPolicy Bypass -File tools\restore.ps1 -ManifestPath '$($manifestItem.FullName)' -ApplyDatabase -ApplyFileStore -DryRun:`$false"
$sourceBatchRollbackCommand = 'pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-guangzhou-physics-source-batch-stage.ps1 -Rollback'
$supplementalManifest = [ordered]@{
    schemaVersion = '1.0'
    createdAt = (Get-Date).ToUniversalTime().ToString('o')
    batchKey = $stage.batchKey
    baseManifest = [ordered]@{
        path = $manifestItem.FullName
        sha256 = Get-LowerSha256 -Path $manifestItem.FullName
    }
    databaseDump = [ordered]@{
        path = $databaseDump
        sha256 = Get-LowerSha256 -Path $databaseDump
    }
    sourceMappingSnapshot = [ordered]@{
        path = $snapshotPath
        sha256 = Get-LowerSha256 -Path $snapshotPath
        sourceDocumentCount = $snapshot.relevantSourceDocumentCount
    }
    sourceBatchInventory = [ordered]@{
        report = $stageReportPath
        digest = $stage.inventoryDigest
        physicalFileCount = $stage.physicalFileCount
        logicalSourceCount = $stage.logicalSourceCount
    }
    restoreCommand = $restoreCommand
    sourceBatchRollbackCommand = $sourceBatchRollbackCommand
}
$supplementalPath = Join-Path $backupDir 'guangzhou-physics-v2-prewrite-manifest.json'
Write-Json -Value $supplementalManifest -Path $supplementalPath

$evidence = [ordered]@{
    status = 'pass'
    checkedAt = (Get-Date).ToUniversalTime().ToString('o')
    task = 'Guangzhou physics 2015-2025 v2 prewrite backup'
    batchKey = $stage.batchKey
    backupDir = $backupDir
    baseManifest = $supplementalManifest.baseManifest
    databaseDump = $supplementalManifest.databaseDump
    fileStoreFileCount = $verification.fileCount
    backupVerification = [ordered]@{ status = $verification.status }
    restoreDryRun = [ordered]@{
        status = $restoreDryRun.status
        mode = $restoreDryRun.mode
        actionAreas = @($restoreDryRun.actions | ForEach-Object { $_.area })
    }
    sourceMappingSnapshot = $supplementalManifest.sourceMappingSnapshot
    supplementalManifest = [ordered]@{
        path = $supplementalPath
        sha256 = Get-LowerSha256 -Path $supplementalPath
    }
    sourceBatchInventory = $supplementalManifest.sourceBatchInventory
    restoreCommand = $restoreCommand
    sourceBatchRollbackCommand = $sourceBatchRollbackCommand
    activeWrite = $false
    completionBoundary = 'This evidence proves a verified prewrite backup and restore dry-run; it does not apply a restore or import source data.'
}
$outputPath = Join-Path $repoRoot $Output
Write-Json -Value $evidence -Path $outputPath
$evidence | ConvertTo-Json -Depth 12

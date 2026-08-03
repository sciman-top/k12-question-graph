param(
    [string] $MaterialBatchKey = 'guangzhou_physics_2015_2025_20260726_v2',
    [string] $InventoryCsv = 'docs\evidence\20260726-guangzhou-physics-source-batch-inventory.csv',
    [string] $ImportReport = 'docs\evidence\20260726-guangzhou-physics-v2-source-import-idempotency.json',
    [string] $Output = 'docs\evidence\20260726-guangzhou-physics-v2-source-import-invariants.json',
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
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
if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for source import invariants'
}
if ($MaterialBatchKey -notmatch '^[a-z0-9_]+$') {
    throw 'MaterialBatchKey must use normalized lowercase letters, digits, and underscores only'
}

$psql = Join-Path $PgBin 'psql.exe'
if (-not (Test-Path -LiteralPath $psql)) {
    throw "psql not found: $psql"
}
$sql = @"
select json_build_object(
  'batchDocumentCount', (select count(*) from source_documents where material_batch_key = '$MaterialBatchKey'),
  'batchFileAssetCount', (select count(distinct file_asset_id) from source_documents where material_batch_key = '$MaterialBatchKey'),
  'roleCounts', (select json_object_agg(source_type, count) from (select source_type, count(*) as count from source_documents where material_batch_key = '$MaterialBatchKey' group by source_type) roles),
  'yearCount', (select count(distinct year) from source_documents where material_batch_key = '$MaterialBatchKey'),
  'yearRoleCoveragePass', (select bool_and(role_count = 3) from (select year, count(distinct source_type) as role_count from source_documents where material_batch_key = '$MaterialBatchKey' group by year) years),
  'split2020DocumentCount', (select count(*) from source_documents where material_batch_key = '$MaterialBatchKey' and year = 2020 and source_type in ('local_exam_paper','answer_or_solution')),
  'split2020FileAssetCount', (select count(distinct file_asset_id) from source_documents where material_batch_key = '$MaterialBatchKey' and year = 2020 and source_type in ('local_exam_paper','answer_or_solution')),
  'orphanDocumentCount', (select count(*) from source_documents sd left join file_assets fa on fa.id = sd.file_asset_id where sd.material_batch_key = '$MaterialBatchKey' and fa.id is null),
  'duplicateLogicalIdentityCount', (
    select count(*) from (
      select file_asset_id, source_type, source_title, region, year, grade_or_scope, edition_or_version, material_batch_key, count(*)
      from source_documents
      where material_batch_key = '$MaterialBatchKey'
      group by file_asset_id, source_type, source_title, region, year, grade_or_scope, edition_or_version, material_batch_key
      having count(*) > 1
    ) duplicates
  ),
  'activeDomainAssetCount', (select count(*) from domain_asset_versions where status = 'active'),
  'files', (
    select json_agg(json_build_object('fileAssetId', fa.id, 'relativePath', fa.relative_path, 'sha256', fa.sha256, 'sizeBytes', fa.size_bytes) order by fa.relative_path)
    from file_assets fa
    where fa.id in (select distinct file_asset_id from source_documents where material_batch_key = '$MaterialBatchKey')
  )
);
"@
$databaseJson = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -At -v ON_ERROR_STOP=1 -c $sql
if ($LASTEXITCODE -ne 0) {
    throw 'Source import invariant SQL failed'
}
$database = ($databaseJson -join "`n") | ConvertFrom-Json
$inventory = @(Import-Csv -LiteralPath (Join-Path $repoRoot $InventoryCsv))
$import = Get-Content -LiteralPath (Join-Path $repoRoot $ImportReport) -Raw | ConvertFrom-Json

$blobFailures = [System.Collections.Generic.List[object]]::new()
foreach ($file in @($database.files)) {
    $path = Join-Path $FileStoreRoot ([string] $file.relativePath)
    if (-not (Test-Path -LiteralPath $path)) {
        $blobFailures.Add([ordered]@{ relativePath = $file.relativePath; reason = 'missing' }) | Out-Null
        continue
    }
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne [string] $file.sha256) {
        $blobFailures.Add([ordered]@{ relativePath = $file.relativePath; reason = 'hash_mismatch' }) | Out-Null
    }
}

$inventoryHashes = @($inventory.sha256 | Sort-Object -Unique)
$databaseHashes = @($database.files.sha256 | Sort-Object -Unique)
$hashCoveragePass = (Compare-Object $inventoryHashes $databaseHashes).Count -eq 0
$sourceIds = @($import.uploaded.sourceDocumentId | Sort-Object -Unique)
$fileAssetIds = @($import.uploaded.fileAssetId | Sort-Object -Unique)
$checks = [ordered]@{
    batchDocumentCount = $database.batchDocumentCount -eq 33
    batchFileAssetCount = $database.batchFileAssetCount -eq 33
    paperCount = $database.roleCounts.local_exam_paper -eq 11
    answerCount = $database.roleCounts.answer_or_solution -eq 11
    reportCount = $database.roleCounts.exam_analysis_report -eq 11
    yearCoverage = $database.yearCount -eq 11 -and $database.yearRoleCoveragePass -eq $true
    split2020DistinctFiles = $database.split2020DocumentCount -eq 2 -and $database.split2020FileAssetCount -eq 2
    noOrphanDocuments = $database.orphanDocumentCount -eq 0
    noDuplicateLogicalIdentities = $database.duplicateLogicalIdentityCount -eq 0
    fileStoreHashes = $blobFailures.Count -eq 0 -and @($database.files).Count -eq 33
    inventoryHashCoverage = $hashCoveragePass
    idempotentSourceIds = $sourceIds.Count -eq 33 -and @($import.uploaded | Where-Object { $_.isDuplicate -ne $true }).Count -eq 0
    idempotentFileAssetIds = $fileAssetIds.Count -eq 33
    c002ActiveUnchanged = $database.activeDomainAssetCount -eq 452
    noC002ActiveWrite = $import.c002ActiveWrite -eq $false
}
$failedChecks = @($checks.GetEnumerator() | Where-Object { $_.Value -ne $true } | ForEach-Object { $_.Key })
$report = [ordered]@{
    status = if ($failedChecks.Count -eq 0) { 'pass' } else { 'fail' }
    checkedAt = (Get-Date).ToUniversalTime().ToString('o')
    task = 'Guangzhou physics v2 source import invariants'
    materialBatchKey = $MaterialBatchKey
    checks = $checks
    failedChecks = $failedChecks
    database = $database
    fileStoreFailures = $blobFailures
    backupManifest = $import.backupManifest
    restoreCommand = $import.restoreCommand
    activeWriteScope = 'SourceDocument/FileAsset only'
    c002ActiveWrite = $false
    completionBoundary = 'This report proves source registration, idempotency, blob integrity, and no C002 active change; it does not prove parsing or teacher review.'
}
$outputPath = Join-Path $repoRoot $Output
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outputPath -Encoding UTF8
$report | ConvertTo-Json -Depth 12
if ($failedChecks.Count -gt 0) {
    throw "Source import invariants failed: $($failedChecks -join ', ')"
}

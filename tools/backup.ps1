param(
    [string] $BackupRoot = 'D:\KQG_Backups',
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabaseUser = 'postgres'
)

$ErrorActionPreference = 'Stop'

function Get-RelativePath([string] $BasePath, [string] $Path) {
    return [System.IO.Path]::GetRelativePath((Resolve-Path -LiteralPath $BasePath), (Resolve-Path -LiteralPath $Path)).Replace('\', '/')
}

function Get-FileEntry([string] $RelativePath, [string] $Path) {
    $item = Get-Item -LiteralPath $Path
    $hash = Get-FileHash -LiteralPath $Path -Algorithm SHA256
    [ordered]@{
        path = $RelativePath.Replace('\', '/')
        bytes = $item.Length
        sha256 = $hash.Hash.ToLowerInvariant()
    }
}

function Copy-RepoFilesToSnapshot([string[]] $Paths, [string] $SnapshotRoot) {
    $entries = @()
    foreach ($relativePath in $Paths) {
        $sourcePath = Join-Path (Get-Location).Path $relativePath
        if (-not (Test-Path -LiteralPath $sourcePath)) {
            continue
        }

        $targetPath = Join-Path $SnapshotRoot $relativePath
        $targetDir = Split-Path -Parent $targetPath
        if (-not (Test-Path -LiteralPath $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }

        Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
        $entries += Get-FileEntry -RelativePath $relativePath -Path $targetPath
    }

    return $entries
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $BackupRoot $timestamp
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$fileStoreSnapshotRelativeRoot = 'file_store'
$fileStoreSnapshotRoot = Join-Path $backupDir $fileStoreSnapshotRelativeRoot
$configSnapshotRelativeRoot = 'configs'
$configSnapshotRoot = Join-Path $backupDir $configSnapshotRelativeRoot
$templateSnapshotRelativeRoot = 'templates'
$templateSnapshotRoot = Join-Path $backupDir $templateSnapshotRelativeRoot
$evidenceSnapshotRelativeRoot = 'evidence'
$evidenceSnapshotRoot = Join-Path $backupDir $evidenceSnapshotRelativeRoot

$pgDump = Join-Path $PgBin 'pg_dump.exe'
if (-not (Test-Path -LiteralPath $pgDump)) {
    throw "pg_dump not found: $pgDump"
}

$databaseDump = Join-Path $backupDir 'database.dump'
& $pgDump -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -Fc -f $databaseDump $DatabaseName
if ($LASTEXITCODE -ne 0) {
    throw "pg_dump failed with exit code $LASTEXITCODE"
}

$fileEntries = @()
if (Test-Path -LiteralPath $FileStoreRoot) {
    New-Item -ItemType Directory -Path $fileStoreSnapshotRoot -Force | Out-Null
    $sourceFiles = Get-ChildItem -LiteralPath $FileStoreRoot -File -Recurse
    foreach ($sourceFile in $sourceFiles) {
        $relativePath = Get-RelativePath -BasePath $FileStoreRoot -Path $sourceFile.FullName
        $destinationPath = Join-Path $fileStoreSnapshotRoot $relativePath
        $destinationDir = Split-Path -Parent $destinationPath
        if (-not (Test-Path -LiteralPath $destinationDir)) {
            New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $sourceFile.FullName -Destination $destinationPath -Force
        $fileEntries += Get-FileEntry -RelativePath $relativePath -Path $destinationPath
    }
}

$configFiles = @(
    'apps/api/appsettings.json',
    'apps/api/appsettings.Development.json',
    'tasks/backlog.csv'
)
$configEntries = Copy-RepoFilesToSnapshot -Paths $configFiles -SnapshotRoot $configSnapshotRoot

$templateFiles = @(
    'tests/golden-import/registry.json',
    'tests/golden-import/privacy_and_license.md',
    'docs/templates/p001-live-pilot-release-checklist.md',
    'docs/templates/p006-release-decision-checklist.md'
)
$templateEntries = Copy-RepoFilesToSnapshot -Paths $templateFiles -SnapshotRoot $templateSnapshotRoot

$evidenceFiles = @(
    'docs/evidence/20260530-ns701-score-template-mapping-report.json',
    'docs/evidence/20260530-ns702-item-score-mapping-report.json',
    'docs/evidence/20260530-ns703-analysis-metrics-report.json',
    'docs/evidence/20260530-ns704-commentary-report.json',
    'docs/evidence/20260530-ns705-student-data-privacy-report.json',
    'docs/evidence/20260529-ns004-non-site-plan-guard-report.json'
)
$evidenceEntries = Copy-RepoFilesToSnapshot -Paths $evidenceFiles -SnapshotRoot $evidenceSnapshotRoot

$databaseHash = Get-FileHash -LiteralPath $databaseDump -Algorithm SHA256
$manifest = [ordered]@{
    version = 1
    createdAt = (Get-Date).ToUniversalTime().ToString('o')
    database = [ordered]@{
        engine = 'postgresql'
        databaseName = $DatabaseName
        dump = 'database.dump'
        sha256 = $databaseHash.Hash.ToLowerInvariant()
    }
    fileStore = [ordered]@{
        snapshotRoot = $fileStoreSnapshotRelativeRoot
        sourceRoot = $FileStoreRoot
        root = $FileStoreRoot
        files = $fileEntries
    }
    configsSnapshotRoot = $configSnapshotRelativeRoot
    configs = $configEntries
    templatesSnapshotRoot = $templateSnapshotRelativeRoot
    templates = $templateEntries
    evidenceSnapshotRoot = $evidenceSnapshotRelativeRoot
    evidence = $evidenceEntries
}

$manifestPath = Join-Path $backupDir 'manifest.json'
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

[pscustomobject]@{
    backupDir = $backupDir
    manifest = $manifestPath
    databaseDump = $databaseDump
    fileCount = @($fileEntries).Count
    configCount = @($configEntries).Count
    templateCount = @($templateEntries).Count
    evidenceCount = @($evidenceEntries).Count
} | ConvertTo-Json -Compress

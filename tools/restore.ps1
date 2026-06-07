param(
    [Parameter(Mandatory)]
    [string] $ManifestPath,
    [string] $TargetDataRoot = 'D:\KQG_Data',
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabaseUser = 'postgres',
    [switch] $ApplyDatabase,
    [switch] $ApplyFileStore,
    [switch] $ApplyConfigs,
    [switch] $DryRun = $true
)

$ErrorActionPreference = 'Stop'

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Compute-Sha256([string] $Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Resolve-FileStoreBackupRoot($Manifest, [string] $ManifestRoot) {
    if ($Manifest.fileStore.PSObject.Properties.Name -contains 'snapshotRoot' -and
        -not [string]::IsNullOrWhiteSpace([string]$Manifest.fileStore.snapshotRoot)) {
        return Join-Path $ManifestRoot ([string]$Manifest.fileStore.snapshotRoot)
    }

    return [string]$Manifest.fileStore.root
}

function Resolve-ManifestGroupRoot($Manifest, [string] $ManifestRoot, [string] $SnapshotPropertyName, [string] $FallbackRoot) {
    if ($Manifest.PSObject.Properties.Name -contains $SnapshotPropertyName) {
        $snapshotRelativeRoot = [string]$Manifest.$SnapshotPropertyName
        if (-not [string]::IsNullOrWhiteSpace($snapshotRelativeRoot)) {
            return Join-Path $ManifestRoot $snapshotRelativeRoot
        }
    }

    return $FallbackRoot
}

$manifestFile = Get-Item -LiteralPath $ManifestPath
$manifestRoot = $manifestFile.DirectoryName
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json

$databaseDumpPath = Join-Path $manifestRoot $manifest.database.dump
Assert-Condition (Test-Path -LiteralPath $databaseDumpPath) "missing database dump: $databaseDumpPath"
Assert-Condition ((Compute-Sha256 $databaseDumpPath) -eq [string]$manifest.database.sha256) 'database dump hash mismatch'

$fileStoreBackupRoot = Resolve-FileStoreBackupRoot -Manifest $manifest -ManifestRoot $manifestRoot
$fileChecks = @()
foreach ($file in @($manifest.fileStore.files)) {
    $src = Join-Path $fileStoreBackupRoot $file.path
    Assert-Condition (Test-Path -LiteralPath $src) "missing file store source file: $src"
    $sha = Compute-Sha256 $src
    Assert-Condition ($sha -eq [string]$file.sha256) "file store hash mismatch: $src"
    $fileChecks += $src
}

$configBackupRoot = Resolve-ManifestGroupRoot -Manifest $manifest -ManifestRoot $manifestRoot -SnapshotPropertyName 'configsSnapshotRoot' -FallbackRoot (Get-Location).Path
$configChecks = @()
foreach ($config in @($manifest.configs)) {
    $src = Join-Path $configBackupRoot $config.path
    Assert-Condition (Test-Path -LiteralPath $src) "missing config source file: $src"
    $sha = Compute-Sha256 $src
    Assert-Condition ($sha -eq [string]$config.sha256) "config hash mismatch: $src"
    $configChecks += $src
}

$actions = [System.Collections.Generic.List[object]]::new()

if ($ApplyFileStore) {
    $targetFileStoreRoot = Join-Path $TargetDataRoot 'file_store'
    $actions.Add([ordered]@{ area = 'file_store'; mode = $(if($DryRun){'dry_run'}else{'apply'}); target = $targetFileStoreRoot; fileCount = @($manifest.fileStore.files).Count }) | Out-Null
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $targetFileStoreRoot -Force | Out-Null
        foreach ($file in @($manifest.fileStore.files)) {
            $src = Join-Path $fileStoreBackupRoot $file.path
            $dst = Join-Path $targetFileStoreRoot $file.path
            $dstDir = Split-Path -Parent $dst
            if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
    }
}

if ($ApplyConfigs) {
    $targetConfigRoot = Join-Path $TargetDataRoot 'recovery/configs'
    $actions.Add([ordered]@{ area = 'configs'; mode = $(if($DryRun){'dry_run'}else{'apply'}); target = $targetConfigRoot; fileCount = @($manifest.configs).Count }) | Out-Null
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $targetConfigRoot -Force | Out-Null
        foreach ($config in @($manifest.configs)) {
            $src = Join-Path $configBackupRoot $config.path
            $dst = Join-Path $targetConfigRoot $config.path
            $dstDir = Split-Path -Parent $dst
            if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
    }
}

if ($ApplyDatabase) {
    $pgRestore = Join-Path $PgBin 'pg_restore.exe'
    Assert-Condition (Test-Path -LiteralPath $pgRestore) "pg_restore not found: $pgRestore"
    $actions.Add([ordered]@{ area = 'database'; mode = $(if($DryRun){'dry_run'}else{'apply'}); host = $DatabaseHost; port = $DatabasePort; database = $DatabaseName; user = $DatabaseUser; dump = $databaseDumpPath }) | Out-Null
    if (-not $DryRun) {
        & $pgRestore -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName --clean --if-exists $databaseDumpPath
        if ($LASTEXITCODE -ne 0) {
            throw "pg_restore failed with exit code $LASTEXITCODE"
        }
    }
}

[ordered]@{
    status = 'ok'
    mode = $(if($DryRun){'dry_run'}else{'apply'})
    manifest = $ManifestPath
    validated = [ordered]@{
        databaseDump = $databaseDumpPath
        fileStoreCount = @($manifest.fileStore.files).Count
        configCount = @($manifest.configs).Count
    }
    actions = $actions
} | ConvertTo-Json -Depth 8

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
    [switch] $AllowOverlay,
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

function Resolve-ContainedPath(
    [string] $Root,
    [string] $RelativePath,
    [string] $Description
) {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($RelativePath)) "$Description path is required"
    Assert-Condition (-not [System.IO.Path]::IsPathRooted($RelativePath)) "$Description must be a relative path: $RelativePath"

    $fullRoot = [System.IO.Path]::GetFullPath($Root)
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $fullRoot $RelativePath))
    $rootPrefix = $fullRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $comparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    Assert-Condition ($candidate.StartsWith($rootPrefix, $comparison)) "$Description escapes its allowed root: $RelativePath"

    $current = $fullRoot
    foreach ($segment in [System.IO.Path]::GetRelativePath($fullRoot, $candidate).Split([System.IO.Path]::DirectorySeparatorChar, [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $current = Join-Path $current $segment
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            Assert-Condition (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) "$Description traverses a reparse point: $current"
        }
    }
    return $candidate
}

function Assert-UniqueEntryPaths($Entries, [string] $Description) {
    $paths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($Entries)) {
        Assert-Condition ($null -ne $entry) "$Description contains a null entry"
        $path = [string]$entry.path
        Assert-Condition ($paths.Add($path.Replace('\', '/'))) "$Description contains a duplicate path: $path"
    }
}

function Resolve-ManifestGroupRoot($Manifest, [string] $ManifestRoot, [string] $SnapshotPropertyName) {
    $snapshotRelativeRoot = [string]$Manifest.$SnapshotPropertyName
    return Resolve-ContainedPath -Root $ManifestRoot -RelativePath $snapshotRelativeRoot -Description $SnapshotPropertyName
}

function Assert-EmptyTargetOrOverlayAuthorized([string] $TargetRoot, [bool] $OverlayAuthorized) {
    if (-not (Test-Path -LiteralPath $TargetRoot)) {
        return
    }

    $hasEntries = $null -ne (Get-ChildItem -LiteralPath $TargetRoot -Force | Select-Object -First 1)
    Assert-Condition (-not $hasEntries -or $OverlayAuthorized) "restore target is not empty; use -AllowOverlay only after taking a pre-restore snapshot: $TargetRoot"
}

$manifestFile = Get-Item -LiteralPath $ManifestPath
$manifestRoot = $manifestFile.DirectoryName
$manifestJson = Get-Content -LiteralPath $ManifestPath -Raw
$schemaPath = Join-Path $PSScriptRoot '..\schemas\backup_manifest.schema.json'
Assert-Condition (Test-Path -LiteralPath $schemaPath) "backup manifest schema not found: $schemaPath"
Assert-Condition (Test-Json -Json $manifestJson -SchemaFile $schemaPath -ErrorAction SilentlyContinue) 'backup manifest schema validation failed'
$manifest = $manifestJson | ConvertFrom-Json

Assert-UniqueEntryPaths -Entries $manifest.fileStore.files -Description 'fileStore.files'
Assert-UniqueEntryPaths -Entries $manifest.configs -Description 'configs'

$databaseDumpPath = Resolve-ContainedPath -Root $manifestRoot -RelativePath ([string]$manifest.database.dump) -Description 'database.dump'
Assert-Condition (Test-Path -LiteralPath $databaseDumpPath) "missing database dump: $databaseDumpPath"
Assert-Condition ((Compute-Sha256 $databaseDumpPath) -eq [string]$manifest.database.sha256) 'database dump hash mismatch'

$fileStoreBackupRoot = Resolve-ContainedPath -Root $manifestRoot -RelativePath ([string]$manifest.fileStore.snapshotRoot) -Description 'fileStore.snapshotRoot'
$fileChecks = @()
foreach ($file in @($manifest.fileStore.files)) {
    $src = Resolve-ContainedPath -Root $fileStoreBackupRoot -RelativePath ([string]$file.path) -Description 'fileStore.files.path'
    Assert-Condition (Test-Path -LiteralPath $src) "missing file store source file: $src"
    $sha = Compute-Sha256 $src
    Assert-Condition ($sha -eq [string]$file.sha256) "file store hash mismatch: $src"
    $fileChecks += $src
}

$configBackupRoot = Resolve-ManifestGroupRoot -Manifest $manifest -ManifestRoot $manifestRoot -SnapshotPropertyName 'configsSnapshotRoot'
$configChecks = @()
foreach ($config in @($manifest.configs)) {
    $src = Resolve-ContainedPath -Root $configBackupRoot -RelativePath ([string]$config.path) -Description 'configs.path'
    Assert-Condition (Test-Path -LiteralPath $src) "missing config source file: $src"
    $sha = Compute-Sha256 $src
    Assert-Condition ($sha -eq [string]$config.sha256) "config hash mismatch: $src"
    $configChecks += $src
}

$actions = [System.Collections.Generic.List[object]]::new()

if ($ApplyFileStore) {
    $targetDataRootFull = [System.IO.Path]::GetFullPath($TargetDataRoot)
    $targetFileStoreRoot = Resolve-ContainedPath -Root $targetDataRootFull -RelativePath 'file_store' -Description 'file store target'
    $actions.Add([ordered]@{ area = 'file_store'; mode = $(if($DryRun){'dry_run'}else{'apply'}); target = $targetFileStoreRoot; fileCount = @($manifest.fileStore.files).Count }) | Out-Null
    if (-not $DryRun) {
        Assert-EmptyTargetOrOverlayAuthorized -TargetRoot $targetFileStoreRoot -OverlayAuthorized $AllowOverlay
        New-Item -ItemType Directory -Path $targetFileStoreRoot -Force | Out-Null
        foreach ($file in @($manifest.fileStore.files)) {
            $src = Resolve-ContainedPath -Root $fileStoreBackupRoot -RelativePath ([string]$file.path) -Description 'fileStore.files.path'
            $dst = Resolve-ContainedPath -Root $targetFileStoreRoot -RelativePath ([string]$file.path) -Description 'file store destination'
            $dstDir = Split-Path -Parent $dst
            if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
    }
}

if ($ApplyConfigs) {
    $targetDataRootFull = [System.IO.Path]::GetFullPath($TargetDataRoot)
    $targetConfigRoot = Resolve-ContainedPath -Root $targetDataRootFull -RelativePath 'recovery/configs' -Description 'config target'
    $actions.Add([ordered]@{ area = 'configs'; mode = $(if($DryRun){'dry_run'}else{'apply'}); target = $targetConfigRoot; fileCount = @($manifest.configs).Count }) | Out-Null
    if (-not $DryRun) {
        Assert-EmptyTargetOrOverlayAuthorized -TargetRoot $targetConfigRoot -OverlayAuthorized $AllowOverlay
        New-Item -ItemType Directory -Path $targetConfigRoot -Force | Out-Null
        foreach ($config in @($manifest.configs)) {
            $src = Resolve-ContainedPath -Root $configBackupRoot -RelativePath ([string]$config.path) -Description 'configs.path'
            $dst = Resolve-ContainedPath -Root $targetConfigRoot -RelativePath ([string]$config.path) -Description 'config destination'
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

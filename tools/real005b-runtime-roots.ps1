$ErrorActionPreference = 'Stop'

function Get-Real005bFullPath {
    param(
        [string] $BasePath,
        [string] $Path
    )

    $fullPath = if ([System.IO.Path]::IsPathRooted($Path)) {
        [System.IO.Path]::GetFullPath($Path)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $BasePath $Path))
    }

    return $fullPath.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
}

function Test-Real005bSamePath {
    param(
        [string] $Left,
        [string] $Right
    )

    return [string]::Equals(
        (Get-Real005bFullPath -BasePath (Get-Location).Path -Path $Left),
        (Get-Real005bFullPath -BasePath (Get-Location).Path -Path $Right),
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

function Initialize-Real005bRuntimeRoots {
    param(
        [string] $RepoRoot,
        [string] $RuntimeFileStoreRoot,
        [AllowNull()]
        [string] $SourceFileStoreRoot
    )

    $resolvedRepoRoot = Get-Real005bFullPath -BasePath (Get-Location).Path -Path $RepoRoot
    $resolvedFileStoreRoot = Get-Real005bFullPath -BasePath $resolvedRepoRoot -Path $RuntimeFileStoreRoot
    $resolvedSourceFileStoreRoot = if ([string]::IsNullOrWhiteSpace($SourceFileStoreRoot)) {
        Get-Real005bFullPath -BasePath $resolvedRepoRoot -Path (
            Resolve-Real005bSourceFileStoreRoot -RepoRoot $resolvedRepoRoot
        )
    }
    else {
        Get-Real005bFullPath -BasePath $resolvedRepoRoot -Path $SourceFileStoreRoot
    }

    $runtimeDataRoot = Split-Path -Parent $resolvedFileStoreRoot
    $runtimeRoot = Split-Path -Parent $runtimeDataRoot
    $runtimeBackupRoot = Join-Path $runtimeRoot 'backups'
    $runtimeLogsRoot = Join-Path $runtimeDataRoot 'logs'
    $runtimeCacheRoot = Join-Path $runtimeDataRoot 'cache'
    $reusesSourceFileStore = Test-Real005bSamePath `
        -Left $resolvedFileStoreRoot `
        -Right $resolvedSourceFileStoreRoot

    foreach ($directoryName in @('original', 'generated')) {
        $sourceDirectory = Join-Path $resolvedSourceFileStoreRoot $directoryName
        if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) {
            throw "REAL005B source file store directory missing: $sourceDirectory"
        }
    }

    if (-not $reusesSourceFileStore) {
        $controlledRuntimeRoot = Get-Real005bFullPath -BasePath $resolvedRepoRoot -Path 'tmp'
        $controlledPrefix = $controlledRuntimeRoot + [System.IO.Path]::DirectorySeparatorChar
        if (-not $resolvedFileStoreRoot.StartsWith(
            $controlledPrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            throw "REAL005B runtime FileStoreRoot must stay under $controlledRuntimeRoot when linking source assets: $resolvedFileStoreRoot"
        }

        foreach ($path in @($runtimeDataRoot, $resolvedFileStoreRoot, $runtimeBackupRoot, $runtimeLogsRoot, $runtimeCacheRoot)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }

        foreach ($directoryName in @('original', 'generated')) {
            $sourceDirectory = Join-Path $resolvedSourceFileStoreRoot $directoryName
            $runtimeDirectory = Join-Path $resolvedFileStoreRoot $directoryName
            if (Test-Path -LiteralPath $runtimeDirectory) {
                Remove-Item -LiteralPath $runtimeDirectory -Recurse -Force
            }
            New-Item -ItemType Junction -Path $runtimeDirectory -Target $sourceDirectory | Out-Null
        }
    }

    return [pscustomobject]@{
        RuntimeRoot = $runtimeRoot
        DataRoot = $runtimeDataRoot
        FileStoreRoot = $resolvedFileStoreRoot
        BackupRoot = $runtimeBackupRoot
        LogsRoot = $runtimeLogsRoot
        CacheRoot = $runtimeCacheRoot
        SourceFileStoreRoot = $resolvedSourceFileStoreRoot
        ReusesSourceFileStore = $reusesSourceFileStore
    }
}

param(
    [Parameter(Mandatory)]
    [string] $ManifestPath
)

$ErrorActionPreference = 'Stop'

function Assert-Hash([string] $Path, [string] $ExpectedHash) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "missing file: $Path"
    }

    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $ExpectedHash) {
        throw "hash mismatch: $Path"
    }
}

function Resolve-ContainedPath([string] $Root, [string] $RelativePath, [string] $Description) {
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [System.IO.Path]::IsPathRooted($RelativePath)) {
        throw "$Description must be a non-empty relative path: $RelativePath"
    }

    $fullRoot = [System.IO.Path]::GetFullPath($Root)
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $fullRoot $RelativePath))
    $rootPrefix = $fullRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $comparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    if (-not $candidate.StartsWith($rootPrefix, $comparison)) {
        throw "$Description escapes its allowed root: $RelativePath"
    }

    $current = $fullRoot
    foreach ($segment in [System.IO.Path]::GetRelativePath($fullRoot, $candidate).Split([System.IO.Path]::DirectorySeparatorChar, [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $current = Join-Path $current $segment
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "$Description traverses a reparse point: $current"
            }
        }
    }
    return $candidate
}

function Resolve-ManifestGroupRoot($Manifest, [string] $ManifestDir, [string] $SnapshotPropertyName) {
    return Resolve-ContainedPath -Root $ManifestDir -RelativePath ([string]$Manifest.$SnapshotPropertyName) -Description $SnapshotPropertyName
}

function Get-ManifestEntries($Manifest, [string] $PropertyName) {
    if (-not ($Manifest.PSObject.Properties.Name -contains $PropertyName)) {
        return @()
    }

    $entries = @($Manifest.$PropertyName | Where-Object { $null -ne $_ })
    foreach ($entry in $entries) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.path) -or
            [string]::IsNullOrWhiteSpace([string]$entry.sha256)) {
            throw "invalid manifest entry in '$PropertyName': path and sha256 are required"
        }
    }

    return $entries
}

$manifestItem = Get-Item -LiteralPath $ManifestPath
$manifestDir = $manifestItem.DirectoryName
$manifestJson = Get-Content -LiteralPath $ManifestPath -Raw
$schemaPath = Join-Path $PSScriptRoot '..\schemas\backup_manifest.schema.json'
if (-not (Test-Json -Json $manifestJson -SchemaFile $schemaPath -ErrorAction SilentlyContinue)) {
    throw 'backup manifest schema validation failed'
}
$manifest = $manifestJson | ConvertFrom-Json

Assert-Hash -Path (Resolve-ContainedPath -Root $manifestDir -RelativePath ([string]$manifest.database.dump) -Description 'database.dump') -ExpectedHash $manifest.database.sha256

$fileStoreBackupRoot = Resolve-ContainedPath -Root $manifestDir -RelativePath ([string]$manifest.fileStore.snapshotRoot) -Description 'fileStore.snapshotRoot'
$fileStoreEntries = @($manifest.fileStore.files | Where-Object { $null -ne $_ })
foreach ($file in $fileStoreEntries) {
    Assert-Hash -Path (Resolve-ContainedPath -Root $fileStoreBackupRoot -RelativePath ([string]$file.path) -Description 'fileStore.files.path') -ExpectedHash $file.sha256
}

$configBackupRoot = Resolve-ManifestGroupRoot -Manifest $manifest -ManifestDir $manifestDir -SnapshotPropertyName 'configsSnapshotRoot'
$configEntries = @(Get-ManifestEntries -Manifest $manifest -PropertyName 'configs')
foreach ($config in $configEntries) {
    Assert-Hash -Path (Resolve-ContainedPath -Root $configBackupRoot -RelativePath ([string]$config.path) -Description 'configs.path') -ExpectedHash $config.sha256
}

$templateBackupRoot = Resolve-ManifestGroupRoot -Manifest $manifest -ManifestDir $manifestDir -SnapshotPropertyName 'templatesSnapshotRoot'
$templateEntries = @(Get-ManifestEntries -Manifest $manifest -PropertyName 'templates')
foreach ($template in $templateEntries) {
    Assert-Hash -Path (Resolve-ContainedPath -Root $templateBackupRoot -RelativePath ([string]$template.path) -Description 'templates.path') -ExpectedHash $template.sha256
}

$evidenceEntries = @(Get-ManifestEntries -Manifest $manifest -PropertyName 'evidence')
if ($evidenceEntries.Count -gt 0) {
    $evidenceBackupRoot = Resolve-ManifestGroupRoot -Manifest $manifest -ManifestDir $manifestDir -SnapshotPropertyName 'evidenceSnapshotRoot'
    foreach ($evidence in $evidenceEntries) {
        Assert-Hash -Path (Resolve-ContainedPath -Root $evidenceBackupRoot -RelativePath ([string]$evidence.path) -Description 'evidence.path') -ExpectedHash $evidence.sha256
    }
}

[pscustomobject]@{
    status = 'ok'
    manifest = $ManifestPath
    fileCount = $fileStoreEntries.Count
    configCount = $configEntries.Count
    templateCount = $templateEntries.Count
    evidenceCount = $evidenceEntries.Count
} | ConvertTo-Json -Compress

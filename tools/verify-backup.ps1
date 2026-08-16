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

function Resolve-FileStoreBackupRoot($Manifest, [string] $ManifestDir) {
    if ($Manifest.fileStore.PSObject.Properties.Name -contains 'snapshotRoot' -and
        -not [string]::IsNullOrWhiteSpace([string]$Manifest.fileStore.snapshotRoot)) {
        return Join-Path $ManifestDir ([string]$Manifest.fileStore.snapshotRoot)
    }

    return [string]$Manifest.fileStore.root
}

function Resolve-ManifestGroupRoot($Manifest, [string] $ManifestDir, [string] $SnapshotPropertyName, [string] $FallbackRoot) {
    if ($Manifest.PSObject.Properties.Name -contains $SnapshotPropertyName) {
        $snapshotRelativeRoot = [string]$Manifest.$SnapshotPropertyName
        if (-not [string]::IsNullOrWhiteSpace($snapshotRelativeRoot)) {
            return Join-Path $ManifestDir $snapshotRelativeRoot
        }
    }

    return $FallbackRoot
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
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$repoRoot = (Get-Location).Path

Assert-Hash -Path (Join-Path $manifestDir $manifest.database.dump) -ExpectedHash $manifest.database.sha256

$fileStoreBackupRoot = Resolve-FileStoreBackupRoot -Manifest $manifest -ManifestDir $manifestDir
$fileStoreEntries = @($manifest.fileStore.files | Where-Object { $null -ne $_ })
foreach ($file in $fileStoreEntries) {
    Assert-Hash -Path (Join-Path $fileStoreBackupRoot $file.path) -ExpectedHash $file.sha256
}

$configBackupRoot = Resolve-ManifestGroupRoot -Manifest $manifest -ManifestDir $manifestDir -SnapshotPropertyName 'configsSnapshotRoot' -FallbackRoot $repoRoot
$configEntries = @(Get-ManifestEntries -Manifest $manifest -PropertyName 'configs')
foreach ($config in $configEntries) {
    Assert-Hash -Path (Join-Path $configBackupRoot $config.path) -ExpectedHash $config.sha256
}

$templateBackupRoot = Resolve-ManifestGroupRoot -Manifest $manifest -ManifestDir $manifestDir -SnapshotPropertyName 'templatesSnapshotRoot' -FallbackRoot $repoRoot
$templateEntries = @(Get-ManifestEntries -Manifest $manifest -PropertyName 'templates')
foreach ($template in $templateEntries) {
    Assert-Hash -Path (Join-Path $templateBackupRoot $template.path) -ExpectedHash $template.sha256
}

$evidenceBackupRoot = Resolve-ManifestGroupRoot -Manifest $manifest -ManifestDir $manifestDir -SnapshotPropertyName 'evidenceSnapshotRoot' -FallbackRoot $repoRoot
$evidenceEntries = @(Get-ManifestEntries -Manifest $manifest -PropertyName 'evidence')
foreach ($evidence in $evidenceEntries) {
    Assert-Hash -Path (Join-Path $evidenceBackupRoot $evidence.path) -ExpectedHash $evidence.sha256
}

[pscustomobject]@{
    status = 'ok'
    manifest = $ManifestPath
    fileCount = $fileStoreEntries.Count
    configCount = $configEntries.Count
    templateCount = $templateEntries.Count
    evidenceCount = $evidenceEntries.Count
} | ConvertTo-Json -Compress

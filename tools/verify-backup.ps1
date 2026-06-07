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

$manifestItem = Get-Item -LiteralPath $ManifestPath
$manifestDir = $manifestItem.DirectoryName
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$repoRoot = (Get-Location).Path

Assert-Hash -Path (Join-Path $manifestDir $manifest.database.dump) -ExpectedHash $manifest.database.sha256

$fileStoreBackupRoot = Resolve-FileStoreBackupRoot -Manifest $manifest -ManifestDir $manifestDir
foreach ($file in @($manifest.fileStore.files)) {
    Assert-Hash -Path (Join-Path $fileStoreBackupRoot $file.path) -ExpectedHash $file.sha256
}

$configBackupRoot = Resolve-ManifestGroupRoot -Manifest $manifest -ManifestDir $manifestDir -SnapshotPropertyName 'configsSnapshotRoot' -FallbackRoot $repoRoot
foreach ($config in @($manifest.configs)) {
    Assert-Hash -Path (Join-Path $configBackupRoot $config.path) -ExpectedHash $config.sha256
}

$templateBackupRoot = Resolve-ManifestGroupRoot -Manifest $manifest -ManifestDir $manifestDir -SnapshotPropertyName 'templatesSnapshotRoot' -FallbackRoot $repoRoot
foreach ($template in @($manifest.templates)) {
    Assert-Hash -Path (Join-Path $templateBackupRoot $template.path) -ExpectedHash $template.sha256
}

$evidenceBackupRoot = Resolve-ManifestGroupRoot -Manifest $manifest -ManifestDir $manifestDir -SnapshotPropertyName 'evidenceSnapshotRoot' -FallbackRoot $repoRoot
foreach ($evidence in @($manifest.evidence)) {
    Assert-Hash -Path (Join-Path $evidenceBackupRoot $evidence.path) -ExpectedHash $evidence.sha256
}

[pscustomobject]@{
    status = 'ok'
    manifest = $ManifestPath
    fileCount = @($manifest.fileStore.files).Count
    configCount = @($manifest.configs).Count
    templateCount = @($manifest.templates).Count
    evidenceCount = @($manifest.evidence).Count
} | ConvertTo-Json -Compress

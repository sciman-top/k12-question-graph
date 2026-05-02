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

$manifestItem = Get-Item -LiteralPath $ManifestPath
$manifestDir = $manifestItem.DirectoryName
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json

Assert-Hash -Path (Join-Path $manifestDir $manifest.database.dump) -ExpectedHash $manifest.database.sha256

foreach ($file in @($manifest.fileStore.files)) {
    Assert-Hash -Path (Join-Path $manifest.fileStore.root $file.path) -ExpectedHash $file.sha256
}

foreach ($config in @($manifest.configs)) {
    Assert-Hash -Path (Join-Path (Get-Location).Path $config.path) -ExpectedHash $config.sha256
}

[pscustomobject]@{
    status = 'ok'
    manifest = $ManifestPath
    fileCount = @($manifest.fileStore.files).Count
    configCount = @($manifest.configs).Count
} | ConvertTo-Json -Compress

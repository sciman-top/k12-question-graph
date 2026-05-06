param(
    [string] $RegistryPath = 'tests/golden-import/registry.json',
    [string] $SamplesPath = 'tests/golden-import/samples.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$registryFullPath = Join-Path $repoRoot $RegistryPath
$samplesFullPath = Join-Path $repoRoot $SamplesPath
$licenseFullPath = Join-Path $repoRoot 'tests/golden-import/privacy_and_license.md'

if (-not (Test-Path -LiteralPath $registryFullPath)) { throw "S004A registry missing: $RegistryPath" }
if (-not (Test-Path -LiteralPath $samplesFullPath)) { throw "S004A samples missing: $SamplesPath" }
if (-not (Test-Path -LiteralPath $licenseFullPath)) { throw 'S004A privacy/license file missing' }

$registry = Get-Content -Raw -LiteralPath $registryFullPath | ConvertFrom-Json -Depth 20
$samples = Get-Content -Raw -LiteralPath $samplesFullPath | ConvertFrom-Json -Depth 20

if ($registry.registryVersion -ne 'golden-import-registry.v1') {
    throw "unexpected registryVersion: $($registry.registryVersion)"
}

$actualHash = (Get-FileHash -LiteralPath $samplesFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ([string]$registry.fixtureSource.samplesSha256 -ne $actualHash) {
    throw 'samplesSha256 mismatch between registry and samples.json'
}

$sampleIds = @($samples | ForEach-Object { [string]$_.id })
$registryIds = @($registry.entries | ForEach-Object { [string]$_.sampleId })

foreach ($id in $sampleIds) {
    if ($registryIds -notcontains $id) {
        throw "registry missing sampleId mapping: $id"
    }
}

$requiredFormats = @('docx','text_pdf','scanned_pdf')
$registryFormats = @($registry.entries | ForEach-Object { [string]$_.format })
foreach ($f in $requiredFormats) {
    if ($registryFormats -notcontains $f) {
        throw "registry missing required format coverage: $f"
    }
}

foreach ($entry in $registry.entries) {
    if ([string]$entry.sourceType -ne 'synthetic') {
        throw "entry $($entry.sampleId) must remain synthetic"
    }
    if ([string]$entry.authorization -ne 'synthetic_local_regression_allowed') {
        throw "entry $($entry.sampleId) has unexpected authorization"
    }
    if (-not $entry.expectedOutput.sourceRegionRequired) {
        throw "entry $($entry.sampleId) must require source regions"
    }
    if ([string]$entry.sampleId -eq 'scanned' -and @($entry.takeoverPoints).Count -lt 3) {
        throw 'scanned sample must define takeover points for fail-closed path'
    }
}

[ordered]@{
    status = 'pass'
    taskId = 'S004A'
    task = 'golden set registry guard'
    checkedAt = (Get-Date).ToString('s')
    registryPath = $RegistryPath
    samplesPath = $SamplesPath
    sampleCount = $sampleIds.Count
    formatCoverage = $requiredFormats
    samplesSha256 = $actualHash
} | ConvertTo-Json -Depth 6

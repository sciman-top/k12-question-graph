param(
    [string] $Id = '',
    [string] $IndexPath = 'docs/evidence/index.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if ($Id -eq 'current-truth') {
    Import-Module (Join-Path $PSScriptRoot 'verification/CurrentTruth.psm1') -Force
    Get-CurrentTruth -RepoRoot $repoRoot -IndexPath $IndexPath | ConvertTo-Json -Depth 8
    exit 0
}

$index = Get-Content -LiteralPath (Join-Path $repoRoot $IndexPath) -Raw -Encoding UTF8 | ConvertFrom-Json
$entries = if ([string]::IsNullOrWhiteSpace($Id)) {
    @($index.entries)
}
else {
    @($index.entries | Where-Object id -eq $Id)
}
if (-not [string]::IsNullOrWhiteSpace($Id) -and $entries.Count -ne 1) {
    throw "current evidence id not found or duplicated: $Id"
}
$entries | ConvertTo-Json -Depth 6

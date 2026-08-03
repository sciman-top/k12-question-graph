param(
    [string] $Id = '',
    [string] $IndexPath = 'docs/evidence/index.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
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

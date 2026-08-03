param(
    [string] $BudgetPath = 'configs/verification/product-hotspot-budgets.json',
    [string] $JsonReportPath = 'tmp/verification/product-hotspot-budget.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$budget = Get-Content -LiteralPath (Join-Path $repoRoot $BudgetPath) -Raw -Encoding UTF8 | ConvertFrom-Json
if ($budget.schemaVersion -ne 1) { throw 'unknown product hotspot budget schema version' }

$rows = New-Object System.Collections.Generic.List[object]
foreach ($entry in @($budget.files)) {
    $fullPath = Join-Path $repoRoot $entry.path
    if (-not (Test-Path -LiteralPath $fullPath)) { throw "hotspot path missing: $($entry.path)" }
    $lines = @(Get-Content -LiteralPath $fullPath).Count
    if ($lines -gt [int]$entry.maxLines) { throw "hotspot budget exceeded: $($entry.path) lines=$lines max=$($entry.maxLines)" }
    $source = Get-Content -LiteralPath $fullPath -Raw
    foreach ($marker in @($entry.requiredMarkers)) {
        if (-not $source.Contains([string]$marker)) { throw "hotspot boundary marker missing: $($entry.path) -> $marker" }
    }
    $rows.Add([pscustomobject]@{
        path = [string]$entry.path
        lines = $lines
        maxLines = [int]$entry.maxLines
        remainingLines = [int]$entry.maxLines - $lines
        boundary = [string]$entry.boundary
    })
}

$report = [ordered]@{
    schemaVersion = 1
    status = 'pass'
    policy = [string]$budget.policy
    fileCount = $rows.Count
    files = $rows.ToArray()
    decision = 'clear endpoint seams extracted; existing workflow and UI modules retained; future growth fails closed'
}
$fullReportPath = Join-Path $repoRoot $JsonReportPath
New-Item -ItemType Directory -Path (Split-Path -Parent $fullReportPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $fullReportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 6

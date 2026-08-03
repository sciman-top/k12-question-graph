param(
    [string] $MigrationPath = 'tasks/ui-contract-migration.csv',
    [string] $JsonReportPath = 'tmp/verification/ui-behavior-contract.json',
    [switch] $SkipTests
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$rows = @(Import-Csv -LiteralPath (Join-Path $repoRoot $MigrationPath) -Encoding UTF8)
$required = @('legacy_id', 'legacy_script', 'classification', 'new_authority', 'parity_status', 'new_default_profile', 'reason')
if ($rows.Count -eq 0) { throw 'UI contract migration map must not be empty' }
foreach ($column in $required) {
    if ($rows[0].PSObject.Properties.Name -notcontains $column) { throw "UI contract migration map missing column: $column" }
}

$seen = @{}
foreach ($row in $rows) {
    if ($seen.ContainsKey($row.legacy_id)) { throw "duplicate UI legacy id: $($row.legacy_id)" }
    $seen[$row.legacy_id] = $true
    if (@('keep', 'replace', 'delete_after_parity') -notcontains $row.classification) { throw "unknown UI migration classification: $($row.legacy_id)" }
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $row.legacy_script))) { throw "missing legacy UI contract: $($row.legacy_script)" }
    foreach ($authority in ($row.new_authority -split ';')) {
        if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $authority))) { throw "missing UI behavior authority: $authority" }
    }
    if ($row.classification -eq 'replace' -and ($row.parity_status -ne 'passed' -or $row.new_default_profile -ne 'Slice')) {
        throw "replaced UI contract lacks behavior parity or Slice routing: $($row.legacy_id)"
    }
    if ($row.classification -eq 'keep' -and $row.new_default_profile -ne 'Release') {
        throw "security/boundary UI contract must remain Release: $($row.legacy_id)"
    }
}

if (-not $SkipTests) {
    Push-Location $repoRoot
    try {
        & npm --prefix apps/web run test
        if ($LASTEXITCODE -ne 0) { throw 'UI behavior tests failed' }
    }
    finally { Pop-Location }
}

$report = [ordered]@{
    schemaVersion = 1
    status = 'pass'
    migrationPath = $MigrationPath
    rowCount = $rows.Count
    replaced = @($rows | Where-Object classification -eq 'replace').legacy_id
    keptRelease = @($rows | Where-Object classification -eq 'keep').legacy_id
    testsExecuted = -not [bool]$SkipTests
    defaultProfileAuthority = 'behavior tests'
}
$fullReportPath = Join-Path $repoRoot $JsonReportPath
New-Item -ItemType Directory -Path (Split-Path -Parent $fullReportPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $fullReportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 6

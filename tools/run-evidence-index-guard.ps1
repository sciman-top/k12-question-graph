param(
    [string] $IndexPath = 'docs/evidence/index.json',
    [string] $SchemaPath = 'schemas/verification/evidence-index.schema.json',
    [string] $JsonReportPath = 'tmp/verification/evidence-index-guard.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$index = Get-Content -LiteralPath (Join-Path $repoRoot $IndexPath) -Raw -Encoding UTF8 | ConvertFrom-Json
$schema = Get-Content -LiteralPath (Join-Path $repoRoot $SchemaPath) -Raw -Encoding UTF8 | ConvertFrom-Json

if ($index.schemaVersion -ne 1 -or $schema.properties.schemaVersion.const -ne 1) { throw 'evidence index schema version mismatch' }
if ($index.scope -ne 'curated_current_only') { throw 'evidence index must remain a curated current pointer, not a second evidence database' }
if ($index.policy.quickSliceRoot -ne 'tmp/verification') { throw 'Quick/Slice artifacts must route to tmp/verification' }
if ($index.policy.trackedRoot -ne 'docs/evidence') { throw 'tracked evidence root must remain docs/evidence' }

$allowedAuthority = @('repo-side', 'release-side', 'onsite-manual', 'live-accepted')
$seenIds = @{}
$seenCurrentPaths = @{}
$supersededCount = 0
foreach ($entry in @($index.entries)) {
    if ([string]::IsNullOrWhiteSpace($entry.id)) { throw 'evidence entry id is required' }
    if ($seenIds.ContainsKey($entry.id)) { throw "duplicate evidence entry id: $($entry.id)" }
    if ($seenCurrentPaths.ContainsKey($entry.currentPath)) { throw "duplicate current evidence path: $($entry.currentPath)" }
    $seenIds[$entry.id] = $true
    $seenCurrentPaths[$entry.currentPath] = $true
    if ($entry.state -ne 'current') { throw "indexed evidence must be current: $($entry.id)" }
    if ($allowedAuthority -notcontains $entry.authorityLevel) { throw "unknown evidence authority: $($entry.id)" }
    if (-not $entry.currentPath.StartsWith('docs/evidence/')) { throw "current evidence must be tracked: $($entry.id)" }
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $entry.currentPath))) { throw "dangling current evidence path: $($entry.currentPath)" }
    if ([string]::IsNullOrWhiteSpace($entry.claimBoundary)) { throw "claim boundary is required: $($entry.id)" }
    foreach ($path in @($entry.supersededPaths)) {
        $supersededCount++
        if ($path -eq $entry.currentPath) { throw "current path cannot supersede itself: $($entry.id)" }
        if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $path))) { throw "dangling superseded evidence path: $path" }
    }
}

$real005Entry = @($index.entries | Where-Object id -eq 'real005-closure-standard')
if ($real005Entry.Count -ne 1) { throw 'REAL005 current evidence entry is required' }
$real005 = Get-Content -LiteralPath (Join-Path $repoRoot $real005Entry[0].currentPath) -Raw -Encoding UTF8 | ConvertFrom-Json
if ($real005.closureStatus -ne 'not_closed' -or $real005.fullClosureAllowed -ne $false) {
    throw 'REAL005 evidence index must preserve not_closed/fullClosureAllowed=false'
}

$report = [ordered]@{
    schemaVersion = 1
    status = 'pass'
    indexPath = $IndexPath
    entryCount = @($index.entries).Count
    supersededPathCount = $supersededCount
    authorityCounts = [ordered]@{
        repoSide = @($index.entries | Where-Object authorityLevel -eq 'repo-side').Count
        releaseSide = @($index.entries | Where-Object authorityLevel -eq 'release-side').Count
        onsiteManual = @($index.entries | Where-Object authorityLevel -eq 'onsite-manual').Count
        liveAccepted = @($index.entries | Where-Object authorityLevel -eq 'live-accepted').Count
    }
    real005ClosureStatus = $real005.closureStatus
    historicalFileCount = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'docs/evidence') -File).Count
    policy = $index.policy
}
$fullReportPath = Join-Path $repoRoot $JsonReportPath
New-Item -ItemType Directory -Path (Split-Path -Parent $fullReportPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $fullReportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 6

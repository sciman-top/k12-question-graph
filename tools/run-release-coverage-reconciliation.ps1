param(
    [string] $JsonReportPath = 'tmp/verification/release-coverage-reconciliation.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Import-Module (Join-Path $PSScriptRoot 'verification/VerificationProfile.psm1') -Force

$inventory = Get-LegacyGateInventory -RepoRoot $repoRoot
$validation = Test-LegacyGateInventory -Steps $inventory.steps -ExpectedStepCount ([int]$inventory.rules.expectedStepCount)
$quick = @($inventory.steps | Where-Object profile -eq 'Quick')
$release = @($inventory.steps | Where-Object profile -eq 'Release')
$onsite = @($inventory.steps | Where-Object profile -eq 'Onsite')
$unmapped = @($inventory.steps | Where-Object profile -notin @('Quick', 'Slice', 'Release', 'Onsite'))
if ($unmapped.Count -gt 0) { throw "unmapped legacy steps: $($unmapped.Count)" }

$runner = Get-Content -LiteralPath (Join-Path $repoRoot 'tools/run-verification.ps1') -Raw
$legacy = Get-Content -LiteralPath (Join-Path $repoRoot 'tools/run-gates.ps1') -Raw
foreach ($marker in @('AuthorizeStateful', "'Release'", 'run-gates.ps1', 'get-release-state-fingerprint.ps1')) {
    if (-not $runner.Contains($marker)) { throw "Release runner missing marker: $marker" }
}
if (-not $legacy.Contains('LEGACY_RELEASE_COMPATIBILITY_ENTRY')) {
    throw 'run-gates.ps1 must be explicitly marked as the legacy Release compatibility entry'
}

$uiRows = @(Import-Csv -LiteralPath (Join-Path $repoRoot 'tasks/ui-contract-migration.csv') -Encoding UTF8)
$replacedWithoutParity = @($uiRows | Where-Object classification -eq 'replace' | Where-Object parity_status -ne 'passed')
if ($replacedWithoutParity.Count -gt 0) { throw 'UI legacy contracts cannot leave the default profile before behavior parity' }
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot 'tools/run-evidence-index-guard.ps1'))) { throw 'evidence lifecycle guard is missing' }

$futureQuick = @($quick | Where-Object trigger_only)
if ($futureQuick.Count -gt 0) { throw 'future Q/R admission leaked into Quick' }
$futureTriggerOnly = @($inventory.steps | Where-Object trigger_only)
$pureStateless = @($inventory.steps | Where-Object {
    $_.profile -eq 'Release' -and
    -not $_.requires_database -and
    -not $_.stops_process -and
    -not $_.writes_filestore -and
    -not $_.requires_external_tool
})
foreach ($marker in @('Invoke-ReleaseCoreProfile', 'IncludeLegacyCompatibility', 'release-contracts', 'release-upgrade-recovery', 'release-closure-invariants')) {
    if (-not $runner.Contains($marker)) { throw "focused Release core missing marker: $marker" }
}
if ($runner -notmatch 'if \(\$IncludeLegacyCompatibility\)\s*\{[\s\S]*?run-gates\.ps1') {
    throw 'legacy compatibility audit must remain explicit opt-in'
}

$report = [ordered]@{
    schemaVersion = 2
    status = 'pass'
    legacyStepCount = $validation.stepCount
    coverage = [ordered]@{
        quick = $quick.Count
        slice = @($inventory.steps | Where-Object profile -eq 'Slice').Count
        release = $release.Count
        onsite = $onsite.Count
        unmapped = $unmapped.Count
    }
    defaultRelease = [ordered]@{
        entry = 'tools/run-verification.ps1 -Profile Release -AuthorizeStateful'
        coreSteps = @('Quick', 'release-contracts', 'release-upgrade-recovery', 'release-closure-invariants', 'release-state-reconciliation')
        legacyMonolithIncluded = $false
        sharedFileStoreWriteExpected = $false
        trackedDatedEvidenceWriteExpected = $false
    }
    legacyAudit = [ordered]@{
        entry = 'tools/run-verification.ps1 -Profile Release -AuthorizeStateful -IncludeLegacyCompatibility'
        optional = $true
        defaultBlocking = $false
        inventoryStepCount = $validation.stepCount
    }
    retiredDefaultLegacyExecutionCount = $validation.stepCount
    operationallyStatelessLegacyCount = $pureStateless.Count
    futureTriggerOnlyCount = $futureTriggerOnly.Count
    statefulAuthorizationRequired = $true
    stateFingerprintCommand = 'tools/get-release-state-fingerprint.ps1'
    uiBehaviorParityRows = @($uiRows | Where-Object parity_status -eq 'passed').Count
    futureQuickCount = $futureQuick.Count
    truthBoundary = 'Default release-core is repo/release-side technical evidence. Optional legacy audit history and repo-side evidence cannot close onsite or live acceptance.'
}
$fullReportPath = Join-Path $repoRoot $JsonReportPath
New-Item -ItemType Directory -Path (Split-Path -Parent $fullReportPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $fullReportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 6

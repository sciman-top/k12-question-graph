$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
Import-Module (Join-Path $repoRoot 'tools/verification/VerificationProfile.psm1') -Force

function New-ValidStep([string] $Id = 'legacy-sample', [string] $Name = 'sample') {
    return [pscustomobject][ordered]@{
        id = $Id
        name = $Name
        command = 'inline:sample'
        owner_module = 'governance'
        profile = 'Release'
        risk = 'medium'
        requires_database = $false
        stops_process = $false
        writes_repo = $false
        writes_filestore = $false
        requires_external_tool = $false
        trigger_paths = @('tools/**')
        trigger_only = $false
        supersedes = @()
        evidence_output = @()
        source_line = 1
        automatable_repo_side = $true
    }
}

function Assert-Throws([string] $Case, [scriptblock] $Script) {
    try {
        & $Script
    }
    catch {
        return
    }
    throw "negative parser case did not fail closed: $Case"
}

$valid = New-ValidStep
Test-LegacyGateInventory -Steps @($valid) -ExpectedStepCount 1 | Out-Null

$missing = New-ValidStep
$missing.PSObject.Properties.Remove('owner_module')
Assert-Throws 'missing field' { Test-LegacyGateInventory -Steps @($missing) -ExpectedStepCount 1 }

Assert-Throws 'duplicate id' {
    Test-LegacyGateInventory -Steps @((New-ValidStep), (New-ValidStep -Name 'sample two')) -ExpectedStepCount 2
}

$unknown = New-ValidStep
$unknown.profile = 'Maybe'
Assert-Throws 'unknown profile' { Test-LegacyGateInventory -Steps @($unknown) -ExpectedStepCount 1 }

$unsafeQuick = New-ValidStep
$unsafeQuick.profile = 'Quick'
$unsafeQuick.risk = 'low'
$unsafeQuick.requires_database = $true
Assert-Throws 'unsafe quick' { Test-LegacyGateInventory -Steps @($unsafeQuick) -ExpectedStepCount 1 }

$onsite = New-ValidStep
$onsite.profile = 'Onsite'
Assert-Throws 'onsite auto pass' { Test-LegacyGateInventory -Steps @($onsite) -ExpectedStepCount 1 }

$futureQuick = New-ValidStep
$futureQuick.profile = 'Quick'
$futureQuick.risk = 'low'
$futureQuick.trigger_only = $true
Assert-Throws 'future quick' { Test-LegacyGateInventory -Steps @($futureQuick) -ExpectedStepCount 1 }

$inventory = Get-LegacyGateInventory -RepoRoot $repoRoot
$real = Test-LegacyGateInventory -Steps $inventory.steps -ExpectedStepCount ([int]$inventory.rules.expectedStepCount)
if ($real.profileCounts.Quick -ne 7) {
    throw "expected seven side-effect-free legacy Quick steps; got $($real.profileCounts.Quick)"
}
if (@($inventory.steps | Where-Object trigger_only).Count -ne 0) {
    throw 'future-only Q/R/NS11/NS12 steps must be retired from the legacy executable gate'
}

$verificationScript = Get-Content -LiteralPath (Join-Path $repoRoot 'tools/run-verification.ps1') -Raw
foreach ($required in @(
    'Invoke-ReleaseCoreProfile',
    'run-ns102-migration-baseline.ps1',
    'run-ns203-privacy-license-scan.ps1',
    'run-ns204-no-active-write-guard.ps1',
    'run-ns806-upgrade-bundle.ps1',
    'run-live-pilot-closeout-plan-guard.ps1',
    'sharedFileStoreWriteExpected = $false'
)) {
    if (-not $verificationScript.Contains($required)) { throw "release-core source contract missing: $required" }
}
if ($verificationScript -notmatch 'if \(\$IncludeLegacyCompatibility\)\s*\{[\s\S]*?run-gates\.ps1') {
    throw 'legacy run-gates entry must be guarded by IncludeLegacyCompatibility'
}
if ($verificationScript -notmatch 'Copy-DirectoryMirror[\s\S]*?legacy-evidence-snapshot[\s\S]*?finally\s*\{[\s\S]*?Copy-DirectoryMirror') {
    throw 'legacy compatibility audit must restore its evidence workspace in finally'
}
$legacyGateScript = Get-Content -LiteralPath (Join-Path $repoRoot 'tools/run-gates.ps1') -Raw
if ($legacyGateScript -notmatch '\$env:KqgPaths__FileStoreRoot\s*=\s*\$FileStoreRoot' -or
    $legacyGateScript -notmatch '\$env:KqgPaths__FileStoreRoot\s*=\s*\$previousGateFileStoreRoot') {
    throw 'legacy gate must bind and restore the caller-provided FileStore root'
}
if ($legacyGateScript -notmatch "ns906 visual surrogate review[\s\S]*?run-real007-guangzhou-2015-layout-quality\.ps1[\s\S]*?run-ns906-visual-surrogate-review\.ps1") {
    throw 'NS906 must explicitly prepare current isolated visual source regions before review'
}
if (($verificationScript | Select-String -Pattern "run-ui-behavior-contract-guard.ps1'\) -SkipTests" -AllMatches).Matches.Count -ne 2) {
    throw 'Slice and Release must reuse already executed frontend tests instead of rerunning them inside the UI behavior guard'
}
if ($verificationScript -notmatch '\$Profile\s+-in\s+@\(''Quick'', ''Slice'', ''Release''\)') {
    throw 'all executable verification profiles must use the bounded process-settle window before side-effect comparison'
}

$defaultDryRun = & (Join-Path $repoRoot 'tools/run-verification.ps1') -Profile Release -DryRun -ReportRoot 'tmp/verification/tests/default-release' | ConvertFrom-Json
if (-not [bool]$defaultDryRun.releaseCoreIncluded) { throw 'default Release must include release-core' }
if ([bool]$defaultDryRun.legacyCompatibilityIncluded) { throw 'default Release must exclude legacy compatibility audit' }
if (@($defaultDryRun.steps.id) -contains 'legacy-compatibility-audit') { throw 'default Release selected legacy compatibility audit' }
foreach ($requiredStep in @('release-contracts', 'release-upgrade-recovery', 'release-closure-invariants')) {
    if (@($defaultDryRun.steps.id) -notcontains $requiredStep) { throw "default Release missing step: $requiredStep" }
}
$quickOrder = @($defaultDryRun.steps.id | Where-Object { $_ -notlike 'release-*' })
$expectedQuickOrder = @('profile-inventory', 'backend-build', 'frontend-build', 'frontend-lint', 'script-quality', 'backend-tests', 'frontend-tests', 'worker-tests')
if (($quickOrder -join ',') -ne ($expectedQuickOrder -join ',')) {
    throw "Quick must preserve build/static then test order; got: $($quickOrder -join ', ')"
}

$legacyDryRun = & (Join-Path $repoRoot 'tools/run-verification.ps1') -Profile Release -DryRun -IncludeLegacyCompatibility -ReportRoot 'tmp/verification/tests/legacy-release' | ConvertFrom-Json
if (-not [bool]$legacyDryRun.legacyCompatibilityIncluded) { throw 'explicit legacy audit flag was not projected' }
if (@($legacyDryRun.steps.id) -notcontains 'legacy-compatibility-audit') { throw 'explicit legacy audit was not selected' }

$ns802Script = Get-Content -LiteralPath (Join-Path $repoRoot 'tools/run-ns802-restore-drill.ps1') -Raw
if ($ns802Script -notmatch '\[string\]\s+\$Ns801ReportPath\s*=\s*''docs/evidence/20260530-ns801-backup-manifest-report\.json''') {
    throw 'NS802 must keep the backward-compatible NS801 report default'
}
if ($ns802Script -notmatch 'Read-Json\s+\$Ns801ReportPath') { throw 'NS802 must consume the explicit Ns801ReportPath parameter' }

$preflightScript = Get-Content -LiteralPath (Join-Path $repoRoot 'tools/run-repo-preflight.ps1') -Raw
if ($preflightScript.Contains("(Join-Path `$PSScriptRoot 'run-gates.ps1')")) { throw 'repo preflight must not call legacy run-gates directly' }
if (-not $preflightScript.Contains("'run-verification.ps1'")) { throw 'repo preflight must route through run-verification' }

$gateGroupScript = Get-Content -LiteralPath (Join-Path $repoRoot 'tools/run-gate-group.ps1') -Raw
if ($gateGroupScript -notmatch "'legacy-audit'") { throw 'gate group must expose an explicit legacy-audit entry' }
if ($gateGroupScript.Contains("(Join-Path `$PSScriptRoot 'run-gates.ps1')")) { throw 'gate group must not call legacy run-gates directly' }

[ordered]@{
    status = 'pass'
    negativeCases = @('missing field', 'duplicate id', 'unknown profile', 'unsafe quick', 'onsite auto pass', 'future quick')
    realStepCount = $real.stepCount
    profileCounts = $real.profileCounts
    defaultReleaseSteps = @($defaultDryRun.steps.id)
    legacyAuditOptIn = [bool]$legacyDryRun.legacyCompatibilityIncluded
} | ConvertTo-Json -Depth 5

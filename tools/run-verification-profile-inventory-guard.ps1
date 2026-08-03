param(
    [string] $RulesPath = 'configs/verification/legacy-gate-classification.rules.json',
    [string] $JsonReportPath = 'tmp/verification/profile-inventory.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Import-Module (Join-Path $PSScriptRoot 'verification/VerificationProfile.psm1') -Force

$inventory = Get-LegacyGateInventory -RepoRoot $repoRoot -RulesPath $RulesPath
$validation = Test-LegacyGateInventory `
    -Steps $inventory.steps `
    -ExpectedStepCount ([int]$inventory.rules.expectedStepCount) `
    -AllowedProfiles @($inventory.rules.allowedProfiles)

$sourceHash = (Get-FileHash -LiteralPath $inventory.sourceFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
$report = [ordered]@{
    schemaVersion = 1
    status = 'pass'
    sourceScript = $inventory.sourceScript
    sourceHash = $sourceHash
    stepCount = $validation.stepCount
    profileCounts = $validation.profileCounts
    steps = $inventory.steps
}

$reportFullPath = Join-Path $repoRoot $JsonReportPath
New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8

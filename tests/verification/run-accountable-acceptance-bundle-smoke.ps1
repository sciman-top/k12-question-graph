Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$runner = Join-Path $repoRoot 'tools/run-accountable-acceptance-bundle.ps1'

$validJson = & $runner -Mode DryRun -BundlePath 'tests/verification/fixtures/accountable-acceptance-bundle-valid.json' -ExpectedCommit 'fixture-commit' | Out-String
$valid = $validJson | ConvertFrom-Json
if ($valid.status -ne 'pass') { throw 'valid acceptance fixture did not pass' }
if (-not [bool] $valid.readyForAccountableReview) { throw 'valid acceptance fixture is not ready for accountable review' }
if ([bool] $valid.releaseAdvanceAllowed) { throw 'P005 fixture must not allow release advance' }
if (-not [bool] $valid.identityVerificationRequired) { throw 'identity verification boundary must remain explicit' }

$invalidBlocked = $false
try {
    & $runner -Mode DryRun -BundlePath 'tests/verification/fixtures/accountable-acceptance-bundle-invalid.json' -ExpectedCommit 'fixture-commit' *> $null
}
catch {
    $invalidBlocked = $_.Exception.Message -like 'accountable acceptance bundle blocked:*'
}
if (-not $invalidBlocked) { throw 'invalid acceptance fixture did not fail closed' }

[pscustomobject]@{
    status = 'pass'
    validReadyForAccountableReview = $valid.readyForAccountableReview
    invalidFixtureBlocked = $invalidBlocked
    boundary = $valid.truthBoundary
} | ConvertTo-Json -Depth 5

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
Import-Module (Join-Path $repoRoot 'tools/verification/VerificationSelection.psm1') -Force

function Assert-Selection([string] $Case, [string[]] $Paths, [string] $ExpectedStatus, [string[]] $ExpectedCommands) {
    $result = Get-VerificationSelection -RepoRoot $repoRoot -ChangedPaths $Paths -TaskId 'VGOV006'
    if ($result.status -ne $ExpectedStatus) { throw "$Case status expected=$ExpectedStatus actual=$($result.status)" }
    foreach ($command in $ExpectedCommands) {
        if (@($result.selected.id) -notcontains $command) { throw "$Case missing command: $command" }
    }
    return $result
}

Assert-Selection 'api' @('apps/api/Program.cs') 'pass' @('backend-tests') | Out-Null
Assert-Selection 'web' @('apps/web/src/App.tsx') 'pass' @('frontend-tests') | Out-Null
Assert-Selection 'worker' @('workers/document/worker.py') 'pass' @('worker-tests') | Out-Null
Assert-Selection 'docs' @('docs/18_TestStrategy.md') 'pass' @('governance-contracts') | Out-Null
Assert-Selection 'export' @('apps/web/src/ui/PaperWorkbenchPanels.tsx') 'pass' @('frontend-tests') | Out-Null
Assert-Selection 'ai' @('configs/ai/provider.json') 'pass' @('script-quality') | Out-Null

$migration = Assert-Selection 'migration' @('apps/api/Data/Migrations/Next.cs') 'escalated' @()
if ($migration.escalatedProfile -ne 'Release') { throw 'migration must escalate to Release' }

$unknown = Assert-Selection 'unknown' @('mystery/new.file') 'blocked' @()
if ($unknown.unknownPaths.Count -ne 1) { throw 'unknown path must be reported' }

$quotedBundle = Get-VerificationSelection `
    -RepoRoot $repoRoot `
    -ChangedPaths @("'apps/api/Program.cs','configs/verification/product-hotspot-budgets.json'") `
    -TaskId 'VGOV010'
if ($quotedBundle.status -ne 'pass') { throw "quoted comma-delimited changed paths must parse: $($quotedBundle.status)" }
if ($quotedBundle.unknownPaths.Count -ne 0) { throw 'quoted comma-delimited changed paths must not retain quote characters' }
foreach ($command in @('backend-tests', 'hotspot-budget', 'verification-governance')) {
    if (@($quotedBundle.selected.id) -notcontains $command) { throw "quoted bundle missing command: $command" }
}

[ordered]@{
    status = 'pass'
    cases = @('api', 'web', 'worker', 'docs', 'export', 'ai', 'migration', 'unknown', 'quoted-comma-bundle')
    unknownPolicy = 'fail-closed'
    migrationProfile = 'Release'
} | ConvertTo-Json -Depth 5

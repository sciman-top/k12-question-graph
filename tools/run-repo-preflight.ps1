param(
    [ValidateSet('Quick', 'Slice', 'Ci', 'Release')]
    [string] $Mode = 'Ci',
    [string] $ReportRoot = 'tmp/repo-preflight',
    [string] $TaskId = '',
    [string[]] $ChangedPaths = @(),
    [switch] $InstallFrontendDependencies,
    [switch] $SkipFullGate,
    [switch] $AuthorizeStateful,
    [switch] $IncludeLegacyCompatibility,
    [switch] $DryRun,
    [string] $JsonReportPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$profile = switch ($Mode) {
    'Ci' { 'Quick' }
    default { $Mode }
}

if ($InstallFrontendDependencies) {
    Push-Location (Join-Path $repoRoot 'apps/web')
    try {
        & npm ci
        if ($LASTEXITCODE -ne 0) { throw 'npm ci failed' }
    }
    finally { Pop-Location }
}

if ($SkipFullGate) {
    Write-Warning '-SkipFullGate is deprecated: the legacy full gate is no longer part of default Release. Omit this switch.'
}

$arguments = @{
    Profile = $profile
    TaskId = $TaskId
    ChangedPaths = $ChangedPaths
    ReportRoot = $ReportRoot
}
if ($AuthorizeStateful) { $arguments.AuthorizeStateful = $true }
if ($IncludeLegacyCompatibility) { $arguments.IncludeLegacyCompatibility = $true }
if ($DryRun) { $arguments.DryRun = $true }

$output = & (Join-Path $PSScriptRoot 'run-verification.ps1') @arguments
if (-not [string]::IsNullOrWhiteSpace($JsonReportPath)) {
    $source = Join-Path (Join-Path $repoRoot $ReportRoot) 'verification-summary.json'
    $target = Join-Path $repoRoot $JsonReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Force
}
$output

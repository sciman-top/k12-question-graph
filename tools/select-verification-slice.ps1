param(
    [string] $TaskId = '',
    [string[]] $ChangedPaths = @(),
    [string] $RulesPath = 'configs/verification/slice-selection.rules.json',
    [string] $JsonReportPath = 'tmp/verification/slice-selection.json',
    [switch] $AllowEscalation
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Import-Module (Join-Path $PSScriptRoot 'verification/VerificationSelection.psm1') -Force

if ($ChangedPaths.Count -eq 0) {
    $ChangedPaths = @(git -C $repoRoot status --porcelain=v1 --untracked-files=all | ForEach-Object {
        $value = [string]$_
        if ($value.Length -ge 4) { ($value.Substring(3) -split ' -> ')[-1] }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

$selection = Get-VerificationSelection -RepoRoot $repoRoot -ChangedPaths $ChangedPaths -TaskId $TaskId -RulesPath $RulesPath
$fullReportPath = Join-Path $repoRoot $JsonReportPath
New-Item -ItemType Directory -Path (Split-Path -Parent $fullReportPath) -Force | Out-Null
$selection | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $fullReportPath -Encoding UTF8
$selection | ConvertTo-Json -Depth 8

if ($selection.status -ne 'pass' -and -not $AllowEscalation) {
    throw "Slice selection requires $($selection.escalatedProfile): unknown=$($selection.unknownPaths.Count) release=$($selection.releasePaths.Count)"
}

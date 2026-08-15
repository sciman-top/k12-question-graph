param(
    [string[]] $ChangedPaths = @(),
    [string] $JsonReportPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'script-quality-helpers.ps1')

$normalizedPaths = @($ChangedPaths | ForEach-Object { [string]$_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$powershellResult = Invoke-KqgPowerShellParseSweep -RepoRoot $repoRoot -ChangedPaths $normalizedPaths
Assert-KqgQualitySweepPassed -Result $powershellResult -Label 'PowerShell parse sweep'

$pythonResult = Invoke-KqgPythonCompileSweep -RepoRoot $repoRoot -ChangedPaths $normalizedPaths
Assert-KqgQualitySweepPassed -Result $pythonResult -Label 'Python compile sweep'

$report = [ordered]@{
    status = 'pass'
    checkedAt = (Get-Date).ToString('s')
    powershell = $powershellResult
    python = $pythonResult
}

$json = $report | ConvertTo-Json -Depth 6
if (-not [string]::IsNullOrWhiteSpace($JsonReportPath)) {
    $fullPath = Join-Path $repoRoot $JsonReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $fullPath) -Force | Out-Null
    $json | Set-Content -LiteralPath $fullPath -Encoding UTF8
}

$json

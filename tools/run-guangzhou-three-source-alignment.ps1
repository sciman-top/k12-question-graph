param(
    [string] $EvidenceIndexPath = 'tmp\cek012\guangzhou-exam-evidence-index.json',
    [string] $CrosswalkPath = 'tmp\cek008\curriculum-knowledge-crosswalk.candidate.json',
    [string] $RegimesPath = 'configs\knowledge\curriculum-standard-regimes.json',
    [string] $OutputPath = 'tmp\cek013\guangzhou-three-source-alignment.candidate.json',
    [string] $ReportPath = 'docs\evidence\cek013-guangzhou-three-source-alignment.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

Push-Location $repoRoot
try {
    python -m unittest tests.workers.test_guangzhou_three_source_alignment
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-13 unit tests failed'

    python tools/guangzhou_three_source_alignment.py `
        --evidence-index $EvidenceIndexPath `
        --crosswalk $CrosswalkPath `
        --regimes $RegimesPath `
        --output $OutputPath `
        --report $ReportPath
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-13 alignment generation failed'

    $report = Get-Content -Raw $ReportPath | ConvertFrom-Json
    Assert-True ($report.status -eq 'pass') 'CEK-13 report status mismatch'
    Assert-True ($report.bundles -eq 234) 'CEK-13 bundle count mismatch'
    Assert-True ($report.databaseWrite -eq $false) 'CEK-13 must remain read-only'
    Assert-True ($report.activeWrite -eq $false) 'CEK-13 must not write active data'
    $report | ConvertTo-Json -Depth 20
}
finally {
    Pop-Location
}

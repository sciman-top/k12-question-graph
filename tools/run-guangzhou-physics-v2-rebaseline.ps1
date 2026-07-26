param(
    [Parameter(Mandatory)]
    [string] $OldSourceSnapshot,
    [string] $CsvRoot = 'guangzhou-physics-full-research-package-2016-2025\csv',
    [string] $NewImportReport = 'docs\evidence\20260726-guangzhou-physics-v2-source-import-idempotency.json',
    [string] $Output = 'docs\evidence\20260726-guangzhou-physics-v2-c003-rebaseline.json',
    [string] $ClassificationCsv = 'docs\evidence\20260726-guangzhou-physics-v2-c003-rebaseline.csv'
)

$ErrorActionPreference = 'Stop'
$env:PYTHONIOENCODING = 'utf-8'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

Push-Location $repoRoot
try {
    & python tools\guangzhou_physics_v2_rebaseline.py `
        --csv-root $CsvRoot `
        --old-source-snapshot $OldSourceSnapshot `
        --new-import-report $NewImportReport `
        --output $Output `
        --classification-csv $ClassificationCsv
    if ($LASTEXITCODE -ne 0) {
        throw "Guangzhou physics v2 rebaseline failed with exit code $LASTEXITCODE"
    }

    $report = Get-Content -LiteralPath $Output -Raw | ConvertFrom-Json
    $classifiedCount = [int] $report.classificationCounts.matched + [int] $report.classificationCounts.changed_pending_review + [int] $report.classificationCounts.blocked
    if ($report.questionCount -ne 210 -or $classifiedCount -ne 210) {
        throw 'C003 rebaseline did not classify exactly 210 questions'
    }
    if ($report.activeWrite -ne $false -or $report.activationAllowed -ne $false) {
        throw 'C003 rebaseline must not write or activate candidate assets'
    }
}
finally {
    Pop-Location
}

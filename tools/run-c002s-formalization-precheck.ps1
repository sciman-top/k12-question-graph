param(
    [string] $CsvRoot = 'guangzhou-physics-full-research-package-2016-2025\csv',
    [string] $Output = 'docs\evidence\c002s-formalization-precheck-report.json',
    [int] $SamplePerYear = 3,
    [int] $ExpectedQualityIssues = 210
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Push-Location $repoRoot
try {
    python tools\c002s_formalization_precheck.py --csv-root $CsvRoot --output $Output --sample-per-year $SamplePerYear --expected-quality-issues $ExpectedQualityIssues | Write-Host
    if ($LASTEXITCODE -ne 0) {
        throw "C002S formalization precheck failed"
    }

    $report = Get-Content -LiteralPath $Output -Raw | ConvertFrom-Json
    if ($report.task -ne 'C002S') {
        throw "C002S report task mismatch"
    }
    if ($report.sampleFailures -ne 0) {
        throw "C002S sample audit has failures"
    }
    if ($report.qualityIssuesTotal -ne $ExpectedQualityIssues) {
        throw "C002S quality issue count drifted"
    }
    if ($report.qualityIssuesOpenForProduction -gt 0 -and $report.productionActivationAllowed -ne $false) {
        throw "C002S must block activation while quality issues remain open"
    }
    if ($report.qualityIssuesOpenForProduction -eq 0 -and $report.productionActivationAllowed -ne $true) {
        throw "C002S should allow activation only after all blockers are cleared"
    }
    if ([string]::IsNullOrWhiteSpace($report.summaryChinese.title) -or [string]::IsNullOrWhiteSpace($report.summaryChinese.result)) {
        throw "C002S Chinese report summary is missing"
    }

    [ordered]@{
        status = 'pass'
        task = 'C002S'
        reportStatus = $report.status
        output = $Output
        sampleSize = $report.sampleSize
        sampleFailures = $report.sampleFailures
        qualityIssuesOpenForProduction = $report.qualityIssuesOpenForProduction
        productionActivationAllowed = $report.productionActivationAllowed
        chineseReport = $report.summaryChinese.title
    } | ConvertTo-Json -Depth 4
}
finally {
    Pop-Location
}

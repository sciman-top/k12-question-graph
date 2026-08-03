param(
    [string] $ObservationsPath = 'guangzhou-physics-full-research-package-2016-2025\quality-review-complete-csv-package\c003-year-report-observation.csv',
    [string] $AlignmentPath = 'tmp\cek013\guangzhou-three-source-alignment.candidate.json',
    [string] $TargetsPath = 'tmp\cek014\assessment-targets.candidate.json',
    [string] $InventoryPath = 'docs\evidence\20260726-guangzhou-physics-source-batch-inventory.csv',
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [string] $OutputPath = 'tmp\cek018\guangzhou-year-report-evidence.candidate.json',
    [string] $ReportPath = 'docs\evidence\cek018-guangzhou-year-report-evidence.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Assert-SchemaRows([object[]] $Rows, [string] $SchemaPath, [string] $Label) {
    foreach ($row in $Rows) {
        $valid = ($row | ConvertTo-Json -Depth 40) | Test-Json -SchemaFile $SchemaPath -ErrorAction SilentlyContinue
        Assert-True $valid "CEK-18 $Label schema validation failed"
    }
}

Push-Location $repoRoot
try {
    python -m unittest tests.workers.test_guangzhou_year_report_evidence
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-18 unit tests failed'

    python tools\guangzhou_year_report_evidence.py `
        --observations $ObservationsPath `
        --alignment $AlignmentPath `
        --targets $TargetsPath `
        --inventory $InventoryPath `
        --file-store-root $FileStoreRoot `
        --output $OutputPath `
        --report $ReportPath
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-18 extraction failed'

    $package = Get-Content -Raw $OutputPath | ConvertFrom-Json
    $report = Get-Content -Raw $ReportPath | ConvertFrom-Json
    Assert-SchemaRows @($package.observed_performance) 'schemas\observed_performance_evidence.schema.json' 'performance'
    Assert-SchemaRows @($package.observed_errors) 'schemas\observed_error_evidence.schema.json' 'error'
    Assert-SchemaRows @($package.teaching_recommendations) 'schemas\teaching_recommendation.schema.json' 'recommendation'

    Assert-True ($report.status -eq 'generated') 'CEK-18 report generation status mismatch'
    Assert-True ($report.sourcePdfCount -eq 11) 'CEK-18 expected 11 year-report PDFs'
    Assert-True ($report.sourceObservationRows -eq 210) 'CEK-18 expected 210 C003 observation rows'
    Assert-True ($report.derivedObservationRows -eq 24) 'CEK-18 expected 24 rule-derived 2015 observation candidates'
    Assert-True ($package.review_queue.Count -eq 234) 'CEK-18 expected one review item per whole question'
    $observationGap = $package.missing_fields.PSObject.Properties['observation']
    Assert-True ($null -eq $observationGap -or $observationGap.Value -eq 0) 'CEK-18 still has missing year observations'
    Assert-True ($package.governance.database_write -eq $false) 'CEK-18 unexpectedly permits database writes'
    Assert-True ($package.governance.active_write -eq $false) 'CEK-18 unexpectedly permits active writes'
    Assert-True ($package.generation.external_model_calls -eq 0) 'CEK-18 unexpectedly called an external model'
    $report.status = 'pass'
    $report.schemaValidated = $true
    [IO.File]::WriteAllText(
        (Join-Path $repoRoot $ReportPath),
        (($report | ConvertTo-Json -Depth 30) + "`n"),
        [Text.UTF8Encoding]::new($false)
    )
    $report | ConvertTo-Json -Depth 20
}
finally {
    Pop-Location
}

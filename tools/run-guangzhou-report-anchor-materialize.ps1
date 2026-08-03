param(
    [string] $ObservationsPath = 'guangzhou-physics-full-research-package-2016-2025\quality-review-complete-csv-package\c003-year-report-observation.csv',
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabaseUser = 'postgres',
    [string] $DatabasePassword = $env:PGPASSWORD,
    [Parameter(Mandatory)]
    [string] $BackupManifest,
    [string] $ReportPath = 'docs\evidence\cek012a-guangzhou-report-anchor-materialization.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword $DatabasePassword
if ([string]::IsNullOrWhiteSpace($DatabasePassword)) { throw 'database password required' }
$connection = "host=$DatabaseHost port=$DatabasePort dbname=$DatabaseName user=$DatabaseUser"

Push-Location $repoRoot
try {
    python -m unittest tests.workers.test_guangzhou_report_anchor_materialize
    if ($LASTEXITCODE -ne 0) { throw 'report anchor unit tests failed' }

    $evidenceArgs = @()
    if (Test-Path -LiteralPath 'tmp\cek018\guangzhou-year-report-evidence.candidate.json') {
        $evidenceArgs = @('--evidence-package', 'tmp\cek018\guangzhou-year-report-evidence.candidate.json')
    }
    python tools\guangzhou_report_anchor_materialize.py --observations $ObservationsPath --file-store-root $FileStoreRoot --connection-string $connection --backup-manifest $BackupManifest --output tmp\cek012a\dry-run.json @evidenceArgs
    if ($LASTEXITCODE -ne 0) { throw 'report anchor dry-run failed' }

    python tools\guangzhou_report_anchor_materialize.py --observations $ObservationsPath --file-store-root $FileStoreRoot --connection-string $connection --backup-manifest $BackupManifest --output $ReportPath --apply @evidenceArgs
    if ($LASTEXITCODE -ne 0) { throw 'report anchor apply failed' }

    python tools\guangzhou_report_anchor_materialize.py --observations $ObservationsPath --file-store-root $FileStoreRoot --connection-string $connection --backup-manifest $BackupManifest --output tmp\cek012a\idempotency.json --apply @evidenceArgs
    if ($LASTEXITCODE -ne 0) { throw 'report anchor idempotency apply failed' }

    $report = Get-Content -Raw $ReportPath | ConvertFrom-Json
    $idempotency = Get-Content -Raw 'tmp\cek012a\idempotency.json' | ConvertFrom-Json
    if ($report.questions -ne 234 -or $report.database.regionsAfter -ne $report.anchors -or $report.database.blocksAfter -ne $report.anchors) { throw 'report anchor apply count mismatch' }
    if ($idempotency.database.regionsBefore -ne $report.anchors -or $idempotency.database.regionsAfter -ne $report.anchors -or $idempotency.database.blocksAfter -ne $report.anchors) { throw 'report anchor idempotency mismatch' }

    pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-guangzhou-exam-evidence-index.ps1
    if ($LASTEXITCODE -ne 0) { throw 'CEK-12 readiness refresh failed' }
    $readiness = Get-Content -Raw 'docs\evidence\cek012-guangzhou-exam-evidence-index.json' | ConvertFrom-Json
    if ($readiness.readiness.reportEvidenceReady -ne $true -or $readiness.readiness.reportAnchorCount -lt 234) { throw 'report evidence readiness did not close' }
    $report | ConvertTo-Json -Depth 20
}
finally {
    Pop-Location
}

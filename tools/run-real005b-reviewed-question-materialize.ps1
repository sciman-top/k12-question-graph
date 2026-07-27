param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [string] $CsvRoot = 'D:\KQG_Data\candidate_packages\c003-merged-quality-review-2016-2025',
    [string] $QuestionRegionReport2015 = 'docs/evidence/20260726-guangzhou-physics-v2-2015-question-regions.json',
    [string] $QuestionRegionReport2016To2025 = 'docs/evidence/20260726-guangzhou-physics-v2-question-regions.json',
    [string] $BackupManifest = '',
    [switch] $Apply,
    [switch] $AllowPartialReport,
    [string] $ReportPath = '',
    [string] $MarkdownReportPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$env:PYTHONIOENCODING = 'utf-8'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for REAL005B reviewed-question materialization'
}

if ($Apply) {
    if ([string]::IsNullOrWhiteSpace($BackupManifest) -or -not (Test-Path -LiteralPath $BackupManifest -PathType Leaf)) {
        throw 'Apply requires a verified prewrite BackupManifest'
    }
    $verifyResult = & (Join-Path $PSScriptRoot 'verify-backup.ps1') -ManifestPath $BackupManifest | ConvertFrom-Json
    if ([string]$verifyResult.status -ne 'ok') {
        throw "Backup manifest verification failed: $BackupManifest"
    }
}

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = ('docs/evidence/{0}-real005b-reviewed-question-materialize.json' -f (Get-Date -Format 'yyyyMMdd'))
}

if ([string]::IsNullOrWhiteSpace($MarkdownReportPath)) {
    $MarkdownReportPath = ('docs/evidence/{0}-real005b-reviewed-question-materialize.md' -f (Get-Date -Format 'yyyyMMdd'))
}

Push-Location $repoRoot
try {
    $env:PGPASSWORD = $DatabasePassword
    $args = @(
        'tools\real005b_reviewed_question_materialize.py',
        '--host', $DatabaseHost,
        '--port', ([string] $DatabasePort),
        '--database', $DatabaseName,
        '--user', $DatabaseUser,
        '--file-root', $FileStoreRoot,
        '--csv-root', $CsvRoot,
        '--question-region-report-2015', $QuestionRegionReport2015,
        '--question-region-report-2016-2025', $QuestionRegionReport2016To2025,
        '--output', $ReportPath,
        '--markdown-output', $MarkdownReportPath
    )
    if ($Apply) {
        $args += @('--apply', '--backup-manifest', (Resolve-Path -LiteralPath $BackupManifest).Path)
    }

    & python @args
    if ($LASTEXITCODE -ne 0) {
        throw "REAL005B reviewed-question materialize failed with exit code $LASTEXITCODE"
    }

    $report = Get-Content -LiteralPath (Join-Path $repoRoot $ReportPath) -Raw | ConvertFrom-Json
    if ($Apply) {
        if ($report.status -ne 'pass') {
            throw "expected pass status after apply, got $($report.status)"
        }
    }
    else {
        if ($report.status -ne 'dry_run_pass') {
            throw "expected dry_run_pass status, got $($report.status)"
        }
    }

    $report | ConvertTo-Json -Depth 12
}
finally {
    Pop-Location
}

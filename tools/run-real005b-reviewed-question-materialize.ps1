param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [string] $CsvRoot = 'guangzhou-physics-full-research-package-2016-2025\csv',
    [string] $QualityReviewCsvRoot = 'guangzhou-physics-full-research-package-2016-2025\quality-review-complete-csv-package',
    [switch] $Apply,
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

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = ('docs/evidence/{0}-real005b-reviewed-question-materialize.json' -f (Get-Date -Format 'yyyyMMdd'))
}

if ([string]::IsNullOrWhiteSpace($MarkdownReportPath)) {
    $MarkdownReportPath = ('docs/evidence/{0}-real005b-reviewed-question-materialize.md' -f (Get-Date -Format 'yyyyMMdd'))
}

Push-Location $repoRoot
try {
    $args = @(
        'tools\real005b_reviewed_question_materialize.py',
        '--host', $DatabaseHost,
        '--port', ([string] $DatabasePort),
        '--database', $DatabaseName,
        '--user', $DatabaseUser,
        '--password', $DatabasePassword,
        '--file-root', $FileStoreRoot,
        '--csv-root', $CsvRoot,
        '--quality-review-csv-root', $QualityReviewCsvRoot,
        '--output', $ReportPath,
        '--markdown-output', $MarkdownReportPath
    )
    if ($Apply) {
        $args += '--apply'
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

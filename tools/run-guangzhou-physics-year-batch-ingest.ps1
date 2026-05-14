param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $CsvRoot = 'guangzhou-physics-full-research-package-2016-2025\csv',
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [string] $Output = 'docs\evidence\20260514-real003-guangzhou-physics-year-batch-ingest-report.json',
    [string] $MarkdownOutput = 'docs\evidence\20260514-real003-guangzhou-physics-year-batch-ingest-report.md'
)

$ErrorActionPreference = 'Stop'
$env:PYTHONIOENCODING = 'utf-8'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for REAL003 Guangzhou physics year batch ingest dry-run'
}

Push-Location $repoRoot
try {
    $args = @(
        'tools\guangzhou_physics_year_batch_ingest.py',
        '--host', $DatabaseHost,
        '--port', ([string] $DatabasePort),
        '--database', $DatabaseName,
        '--user', $DatabaseUser,
        '--password', $DatabasePassword,
        '--csv-root', $CsvRoot,
        '--file-root', $FileStoreRoot,
        '--output', $Output,
        '--markdown-output', $MarkdownOutput
    )

    & python @args
    if ($LASTEXITCODE -ne 0) {
        throw 'REAL003 Guangzhou physics year batch ingest dry-run failed'
    }

    $report = Get-Content -LiteralPath (Join-Path $repoRoot $Output) -Raw | ConvertFrom-Json
    if ($report.status -ne 'dry_run_pass') {
        throw "expected dry_run_pass status, got $($report.status)"
    }
    if ($report.dryRunOnly -ne $true -or $report.activeWrite -ne $false) {
        throw 'REAL003 must remain dry-run only with no active write'
    }
    if ($report.externalAiCalls -ne 0 -or $report.realStudentDataUsed -ne $false) {
        throw 'REAL003 dry-run must not call external AI or use real student data'
    }
    if ($report.years.Count -ne 10) {
        throw "expected 10 years, got $($report.years.Count)"
    }
    if ($report.totals.questions -ne 210 -or $report.totals.answers -ne 210) {
        throw "expected 210 questions and answers, got questions=$($report.totals.questions) answers=$($report.totals.answers)"
    }
    if (@($report.blockers).Count -ne 0) {
        throw "REAL003 dry-run has blockers: $(@($report.blockers) | ConvertTo-Json -Compress)"
    }
}
finally {
    Pop-Location
}

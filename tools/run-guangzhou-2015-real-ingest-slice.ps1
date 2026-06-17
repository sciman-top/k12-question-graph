param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [string] $Output = '',
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'
$env:PYTHONIOENCODING = 'utf-8'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for Guangzhou 2015 real ingest slice'
}

if ([string]::IsNullOrWhiteSpace($Output)) {
    $Output = ('docs\evidence\{0}-guangzhou-2015-real-ingest-slice-report.json' -f (Get-Date -Format 'yyyyMMdd'))
}

Push-Location $repoRoot
try {
    $args = @(
        'tools\guangzhou_2015_real_ingest.py',
        '--host', $DatabaseHost,
        '--port', ([string] $DatabasePort),
        '--database', $DatabaseName,
        '--user', $DatabaseUser,
        '--password', $DatabasePassword,
        '--file-root', $FileStoreRoot,
        '--output', $Output
    )
    if ($Apply) {
        $args += '--apply'
    }

    & python @args
    if ($LASTEXITCODE -ne 0) {
        throw 'Guangzhou 2015 real ingest slice failed'
    }

    $report = Get-Content -LiteralPath (Join-Path $repoRoot $Output) -Raw | ConvertFrom-Json
    if ($Apply) {
        if ($report.status -ne 'pass') {
            throw "expected pass status after apply, got $($report.status)"
        }
    }
    elseif ($report.status -ne 'dry_run_pass') {
        throw "expected dry_run_pass status, got $($report.status)"
    }

    if ($report.after.questionCount -ne 18) {
        throw "expected 18 question items, got $($report.after.questionCount)"
    }
    if ($report.after.cutCandidateCount -ne 18) {
        throw "expected 18 cut candidates, got $($report.after.cutCandidateCount)"
    }
    if ($report.after.openReviewQueueCount -ne 18) {
        throw "expected 18 open review queue items, got $($report.after.openReviewQueueCount)"
    }
}
finally {
    Pop-Location
}

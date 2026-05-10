param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $Output = 'docs\evidence\source-document-dedupe-report.json',
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw "DatabasePassword or PGPASSWORD is required for source document dedupe contract"
}

Push-Location $repoRoot
try {
    $args = @(
        'tools\source_document_dedupe.py',
        '--host', $DatabaseHost,
        '--port', ([string]$DatabasePort),
        '--database', $DatabaseName,
        '--user', $DatabaseUser,
        '--password', $DatabasePassword,
        '--output', $Output
    )
    if ($Apply) {
        $args += '--apply'
    }

    python @args | Write-Host
    if ($LASTEXITCODE -ne 0) {
        throw "source document dedupe contract failed"
    }

    $report = Get-Content -LiteralPath (Join-Path $repoRoot $Output) -Raw | ConvertFrom-Json
    if ($Apply -and $report.status -ne 'applied') {
        throw "dedupe report status was not applied"
    }
    if (-not $Apply -and $report.status -ne 'dry_run') {
        throw "dedupe report status was not dry_run"
    }
    if ($report.after.exactDuplicateGroups -ne 0) {
        throw "source document exact duplicate groups remain: $($report.after.exactDuplicateGroups)"
    }
    if ($report.after.guangzhou2015SourceDocuments -gt 2) {
        throw "2015 Guangzhou zhongkao source documents were not collapsed"
    }
}
finally {
    Pop-Location
}

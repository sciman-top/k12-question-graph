param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [string] $JsonReportPath = 'docs/evidence/20260516-real007-guangzhou-2015-layout-quality-report.json',
    [string] $MarkdownReportPath = 'docs/evidence/20260516-real007-guangzhou-2015-layout-quality-report.md'
)

$ErrorActionPreference = 'Stop'
$env:PYTHONIOENCODING = 'utf-8'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for REAL007 layout quality report'
}

Push-Location $repoRoot
try {
    & pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-guangzhou-2015-source-region-screenshots.ps1 `
        -DatabaseName $DatabaseName `
        -DatabaseUser $DatabaseUser `
        -DatabaseHost $DatabaseHost `
        -DatabasePort $DatabasePort `
        -DatabasePassword $DatabasePassword `
        -FileStoreRoot $FileStoreRoot `
        -Apply | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'REAL007 setup failed while regenerating source screenshots'
    }

    & python tools/guangzhou_2015_layout_quality_report.py `
        --host $DatabaseHost `
        --port $DatabasePort `
        --database $DatabaseName `
        --user $DatabaseUser `
        --password $DatabasePassword `
        --file-root $FileStoreRoot `
        --json-report $JsonReportPath `
        --markdown-report $MarkdownReportPath
    if ($LASTEXITCODE -ne 0) {
        throw 'REAL007 layout quality report failed'
    }
}
finally {
    Pop-Location
}

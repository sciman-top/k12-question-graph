param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [string] $ReportPath = '',
    [string] $MarkdownReportPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for Guangzhou physics v2 asset diagnostics'
}
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = ('docs/evidence/{0}-guangzhou-physics-v2-asset-diagnostics.json' -f (Get-Date -Format 'yyyyMMdd'))
}
if ([string]::IsNullOrWhiteSpace($MarkdownReportPath)) {
    $MarkdownReportPath = ('docs/evidence/{0}-guangzhou-physics-v2-asset-diagnostics.md' -f (Get-Date -Format 'yyyyMMdd'))
}

$previousPassword = $env:PGPASSWORD
try {
    $env:PGPASSWORD = $DatabasePassword
    Push-Location $repoRoot
    & python tools/guangzhou_physics_v2_asset_diagnostics.py `
        --host $DatabaseHost `
        --port $DatabasePort `
        --database $DatabaseName `
        --user $DatabaseUser `
        --file-root $FileStoreRoot `
        --output $ReportPath `
        --markdown-output $MarkdownReportPath
    if ($LASTEXITCODE -ne 0) {
        throw "Guangzhou physics v2 asset diagnostics failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
    $env:PGPASSWORD = $previousPassword
}

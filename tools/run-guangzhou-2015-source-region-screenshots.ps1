param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [string] $PdfToPpm = 'D:\texlive\2023\bin\windows\pdftoppm.exe',
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'
$env:PYTHONIOENCODING = 'utf-8'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for Guangzhou 2015 source screenshots'
}

if (-not (Test-Path -LiteralPath $PdfToPpm)) {
    $resolved = Get-Command pdftoppm -ErrorAction SilentlyContinue
    if (-not $resolved) {
        throw 'pdftoppm is required to render PDF source screenshots'
    }
    $PdfToPpm = $resolved.Source
}

Push-Location $repoRoot
try {
    $args = @(
        'tools\guangzhou_2015_source_region_screenshots.py',
        '--host', $DatabaseHost,
        '--port', ([string] $DatabasePort),
        '--database', $DatabaseName,
        '--user', $DatabaseUser,
        '--password', $DatabasePassword,
        '--file-root', $FileStoreRoot,
        '--pdftoppm', $PdfToPpm
    )
    if ($Apply) {
        $args += '--apply'
    }

    & python @args
    if ($LASTEXITCODE -ne 0) {
        throw 'Guangzhou 2015 source screenshots generation failed'
    }
}
finally {
    Pop-Location
}

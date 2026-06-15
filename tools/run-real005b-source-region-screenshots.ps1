param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [string] $PdfToPpm = '',
    [string] $PdfInfo = '',
    [string] $ReportPath = '',
    [string] $MarkdownReportPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runDate = Get-Date -Format 'yyyyMMdd'
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = ('docs/evidence/{0}-real005b-source-region-screenshots.json' -f $runDate)
}

if ([string]::IsNullOrWhiteSpace($MarkdownReportPath)) {
    $MarkdownReportPath = ('docs/evidence/{0}-real005b-source-region-screenshots.md' -f $runDate)
}

if ([string]::IsNullOrWhiteSpace($PdfToPpm)) {
    $PdfToPpm = (Get-Command pdftoppm -ErrorAction SilentlyContinue).Source
}

if ([string]::IsNullOrWhiteSpace($PdfInfo)) {
    $PdfInfo = (Get-Command pdfinfo -ErrorAction SilentlyContinue).Source
}

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for REAL005B source-region screenshots'
}

if ([string]::IsNullOrWhiteSpace($PdfToPpm) -or [string]::IsNullOrWhiteSpace($PdfInfo)) {
    throw 'pdftoppm and pdfinfo are required for REAL005B source-region screenshots'
}

Push-Location $repoRoot
try {
    $env:PYTHONIOENCODING = 'utf-8'
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

    & python tools/guangzhou_physics_2016_2025_source_region_screenshots.py `
        --host $DatabaseHost `
        --port $DatabasePort `
        --database $DatabaseName `
        --user $DatabaseUser `
        --password $DatabasePassword `
        --file-root $FileStoreRoot `
        --pdftoppm $PdfToPpm `
        --pdfinfo $PdfInfo `
        --output $ReportPath `
        --markdown-output $MarkdownReportPath
    if ($LASTEXITCODE -ne 0) {
        throw "REAL005B source-region screenshots failed with exit code $LASTEXITCODE"
    }

    $report = Get-Content -LiteralPath (Join-Path $repoRoot $ReportPath) -Raw | ConvertFrom-Json
    if ($report.status -ne 'pass') {
        throw "expected REAL005B source-region screenshot status=pass, got $($report.status)"
    }
    if (@($report.years).Count -ne 10) {
        throw "expected 10 yearly source-region rows, got $(@($report.years).Count)"
    }
    if ($report.sourceRegionCoveragePass -ne $true) {
        throw 'REAL005B source-region screenshot coverage must pass'
    }
    if ($report.activeWrite -ne $false -or $report.externalAiCalls -ne 0 -or $report.realStudentDataUsed -ne $false) {
        throw 'REAL005B source-region screenshot evidence must stay read-only'
    }

    $report | ConvertTo-Json -Depth 12
}
finally {
    Pop-Location
}

param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [string] $MaterialBatchKey = 'guangzhou_physics_2015_2025_20260726_v2',
    [string] $PdfToPpm = '',
    [string] $ReportPath = 'docs\evidence\20260726-guangzhou-physics-v2-2015-question-regions.json',
    [string] $MarkdownReportPath = 'docs\evidence\20260726-guangzhou-physics-v2-2015-question-regions.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for v2 2015 question-region candidates'
}
if ([string]::IsNullOrWhiteSpace($PdfToPpm)) {
    $PdfToPpm = (Get-Command pdftoppm.exe -ErrorAction Stop).Source
}

Push-Location $repoRoot
try {
    $env:PYTHONIOENCODING = 'utf-8'
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    & python tools\guangzhou_physics_v2_2015_question_regions.py `
        --host $DatabaseHost `
        --port $DatabasePort `
        --database $DatabaseName `
        --user $DatabaseUser `
        --material-batch-key $MaterialBatchKey `
        --file-root $FileStoreRoot `
        --pdftoppm $PdfToPpm `
        --output $ReportPath `
        --markdown-output $MarkdownReportPath
    if ($LASTEXITCODE -ne 0) {
        throw "Guangzhou physics v2 2015 question-region candidates failed with exit code $LASTEXITCODE"
    }

    $report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
    if ($report.materialBatchKey -ne $MaterialBatchKey -or $report.totals.questionCandidates -ne 24 -or $report.totals.sourcePages -ne 8) {
        throw 'v2 2015 question-region report must bind the requested batch with 24 candidates and 8 source pages'
    }
    if ($report.status -ne 'pass' -or $report.totals.blockedItems -ne 0 -or $report.totals.manualTakeovers -ne 0) {
        throw 'v2 2015 question-region report has a blocker or unexpected manual takeover'
    }
    if ($report.activeWrite -ne $false -or $report.externalAiCalls -ne 0 -or $report.realStudentDataUsed -ne $false) {
        throw 'v2 2015 question-region generation must remain read-only'
    }
    $regions = @($report.year.questions | ForEach-Object { @($_.regions) })
    if ($regions.Count -ne $report.totals.regionCandidates -or @($regions | ForEach-Object { $_.relativePath } | Sort-Object -Unique).Count -ne $regions.Count) {
        throw 'v2 2015 question-region paths must be complete and unique'
    }
    foreach ($region in $regions) {
        if (-not (Test-Path -LiteralPath (Join-Path $FileStoreRoot $region.relativePath) -PathType Leaf) -or $region.imageQuality.nonBlank -ne $true) {
            throw "v2 2015 question-region file is missing or blank: $($region.relativePath)"
        }
    }
    $report | ConvertTo-Json -Depth 12
}
finally {
    Pop-Location
}

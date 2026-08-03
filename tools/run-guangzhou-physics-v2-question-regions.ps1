param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [string] $MaterialBatchKey = 'guangzhou_physics_2015_2025_20260726_v2',
    [string] $SourcePageReport = 'docs\evidence\20260726-guangzhou-physics-v2-source-region-screenshots.json',
    [string] $ReportPath = 'docs\evidence\20260726-guangzhou-physics-v2-question-regions.json',
    [string] $MarkdownReportPath = 'docs\evidence\20260726-guangzhou-physics-v2-question-regions.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for v2 question-region candidates'
}

Push-Location $repoRoot
try {
    $env:PYTHONIOENCODING = 'utf-8'
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    & python tools\guangzhou_physics_v2_question_regions.py `
        --host $DatabaseHost `
        --port $DatabasePort `
        --database $DatabaseName `
        --user $DatabaseUser `
        --material-batch-key $MaterialBatchKey `
        --file-root $FileStoreRoot `
        --source-page-report $SourcePageReport `
        --output $ReportPath `
        --markdown-output $MarkdownReportPath
    if ($LASTEXITCODE -ne 0) {
        throw "Guangzhou physics v2 question-region candidates failed with exit code $LASTEXITCODE"
    }

    $report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
    if ($report.materialBatchKey -ne $MaterialBatchKey -or $report.totals.questionCandidates -ne 210) {
        throw 'v2 question-region report must bind the requested batch and contain 210 candidates'
    }
    if ($report.status -notin @('pass', 'review_required') -or $report.totals.blockedItems -ne 0) {
        throw "v2 question-region report has blocking items: $($report.blockers -join ', ')"
    }
    if ($report.activeWrite -ne $false) {
        throw 'v2 question-region generation must not write database state'
    }

    $questions = @($report.years | ForEach-Object { @($_.questions) })
    $regions = @($questions | ForEach-Object { @($_.regions) })
    if ($questions.Count -ne 210 -or $regions.Count -ne $report.totals.regionCandidates) {
        throw "v2 question-region detail counts do not match totals: questions=$($questions.Count), regions=$($regions.Count)"
    }
    if (@($questions | Where-Object { $_.status -ne 'candidate' }).Count -ne 0) {
        throw 'every v2 question-region item must remain a candidate'
    }

    $relativePaths = @($regions | ForEach-Object { [string]$_.relativePath })
    if (@($relativePaths | Sort-Object -Unique).Count -ne $relativePaths.Count) {
        throw 'v2 question-region paths must be unique'
    }
    foreach ($region in $regions) {
        $regionPath = Join-Path $FileStoreRoot ([string]$region.relativePath)
        if (-not (Test-Path -LiteralPath $regionPath -PathType Leaf)) {
            throw "v2 question-region file is missing: $($region.relativePath)"
        }
        if ($region.imageQuality.nonBlank -ne $true -or [double]$region.imageQuality.nonWhitePixelRatio -lt 0.001) {
            throw "v2 question-region image is blank or below the quality floor: $($region.relativePath)"
        }
    }

    $takeovers = @($report.years | ForEach-Object {
        $year = $_.year
        @($_.manualTakeoverCandidates) | ForEach-Object {
            [pscustomobject]@{ year = $year; candidate = $_ }
        }
    })
    if ($takeovers.Count -ne 1 -or $takeovers[0].year -ne 2022 -or $takeovers[0].candidate.questionNumber -ne 1) {
        throw 'the only accepted manual takeover candidate is 2022 question 1'
    }

    $year2020 = $report.years | Where-Object { $_.year -eq 2020 }
    if ($year2020.questionSectionBoundary.mode -notin @('following_question_sequence', 'document_end') -or
        $year2020.questionSectionBoundary.endPageNumber -ne 8) {
        throw 'the 2020 paper must stop question regions at page 8 for combined or split source layouts'
    }
    $report | ConvertTo-Json -Depth 12
}
finally {
    Pop-Location
}

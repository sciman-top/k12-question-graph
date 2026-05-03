param(
    [string] $SourceReport = 'docs\evidence\c002-source-material-import-report.json',
    [string] $SourceRoot = 'D:\KQG_Data\source_materials\imported\guangzhou_physics_2016_2025',
    [string] $CacheRoot = 'tmp\c002n-source-chunk-cache',
    [string] $Output = 'docs\evidence\c002n-source-chunk-cache-report.json',
    [int] $RequireCount = 33
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Push-Location $repoRoot
try {
    python tools\c002n_source_chunk_cache.py --source-report $SourceReport --source-root $SourceRoot --cache-root $CacheRoot --output $Output --require-count $RequireCount | Write-Host
    if ($LASTEXITCODE -ne 0) {
        throw "C002N source chunk cache extraction failed"
    }

    python tools\c002n_source_chunk_cache.py --source-report $SourceReport --source-root $SourceRoot --cache-root $CacheRoot --output $Output --require-count $RequireCount | Write-Host
    if ($LASTEXITCODE -ne 0) {
        throw "C002N source chunk cache idempotency rerun failed"
    }

    $report = Get-Content -LiteralPath $Output -Raw | ConvertFrom-Json
    if ($report.status -ne 'pass') {
        throw "C002N report status is not pass"
    }
    if ($report.externalAiCalls -ne 0) {
        throw "C002N must not call external AI"
    }
    if ($report.sourceHashCoverage.coveragePass -ne $true) {
        throw "C002N source hash coverage failed"
    }
    if ($report.cacheIdempotency.cacheHitSourceCount -lt $RequireCount) {
        throw "C002N idempotency rerun did not hit cache for all sources"
    }
    if ([string]::IsNullOrWhiteSpace($report.summaryChinese.title) -or [string]::IsNullOrWhiteSpace($report.summaryChinese.result)) {
        throw "C002N Chinese report summary is missing"
    }

    [ordered]@{
        status = 'pass'
        task = 'C002N'
        output = $Output
        sourceCount = $report.sourceCount
        chunkCount = $report.totals.chunkCount
        cacheHitSourceCount = $report.cacheIdempotency.cacheHitSourceCount
        externalAiCalls = $report.externalAiCalls
        chineseReport = $report.summaryChinese.title
    } | ConvertTo-Json -Depth 4
}
finally {
    Pop-Location
}

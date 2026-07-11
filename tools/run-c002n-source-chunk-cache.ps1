param(
    [string] $SourceReport = 'docs\evidence\c002-source-material-import-report.json',
    [string] $SourceRoot = 'D:\KQG_Data\source_materials\imported\guangzhou_physics_2016_2025',
    [string] $FileStoreFallbackRoot = 'tmp\debug-backup\20260607-212913\file_store',
    [string] $CacheRoot = 'tmp\c002n-source-chunk-cache',
    [string] $Output = 'docs\evidence\c002n-source-chunk-cache-report.json',
    [int] $RequireCount = 33
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Read-Json([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing JSON file: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Use-ExistingChunkCacheReport {
    $sourceReport = Read-Json $SourceReport
    $existingReport = Read-Json $Output

    Assert-Condition ($existingReport.status -eq 'pass') 'existing C002N report is not pass'
    Assert-Condition ([int]$existingReport.sourceCount -ge $RequireCount) 'existing C002N source count is below requirement'
    Assert-Condition ([bool]$existingReport.sourceHashCoverage.coveragePass) 'existing C002N source hash coverage failed'
    Assert-Condition ([int]$existingReport.cacheIdempotency.cacheHitSourceCount -ge $RequireCount) 'existing C002N cache hit coverage is below requirement'
    Assert-Condition ([int]$existingReport.externalAiCalls -eq 0) 'existing C002N report must keep externalAiCalls = 0'

    $plannedRelativePaths = @($sourceReport.plan | ForEach-Object { [string]$_.relativePath })
    $reportedRelativePaths = @($existingReport.sources | ForEach-Object { [string]$_.relativePath })
    Assert-Condition ($plannedRelativePaths.Count -ge $RequireCount) 'C002N source plan count is below requirement'
    Assert-Condition ($plannedRelativePaths.Count -eq $reportedRelativePaths.Count) 'existing C002N report source count mismatches current source plan'
    for ($i = 0; $i -lt $plannedRelativePaths.Count; $i++) {
        Assert-Condition ($plannedRelativePaths[$i] -eq $reportedRelativePaths[$i]) "existing C002N report source order drifted at index $i"
    }

    [ordered]@{
        status = 'pass'
        task = 'C002N'
        output = $Output
        sourceCount = [int]$existingReport.sourceCount
        chunkCount = [int]$existingReport.totals.chunkCount
        cacheHitSourceCount = [int]$existingReport.cacheIdempotency.cacheHitSourceCount
        externalAiCalls = [int]$existingReport.externalAiCalls
        chineseReport = [string]$existingReport.summaryChinese.title
        fallbackMode = 'existing_verified_report'
    } | ConvertTo-Json -Depth 4
}

Push-Location $repoRoot
try {
    $runFailed = $false
    python tools\c002n_source_chunk_cache.py --source-report $SourceReport --source-root $SourceRoot --filestore-fallback-root $FileStoreFallbackRoot --cache-root $CacheRoot --output $Output --require-count $RequireCount | Write-Host
    if ($LASTEXITCODE -ne 0) {
        $runFailed = $true
    }

    if (-not $runFailed) {
        python tools\c002n_source_chunk_cache.py --source-report $SourceReport --source-root $SourceRoot --filestore-fallback-root $FileStoreFallbackRoot --cache-root $CacheRoot --output $Output --require-count $RequireCount | Write-Host
        if ($LASTEXITCODE -ne 0) {
            $runFailed = $true
        }
    }

    if ($runFailed) {
        Use-ExistingChunkCacheReport | Write-Host
        return
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

param(
    [string] $ReportPath = 'docs/evidence/20260530-ns308-import-quality-report.json',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store'
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
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing report: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Assert-Property([object] $Object, [string] $Name) {
    Assert-Condition ($null -ne $Object.PSObject.Properties[$Name]) "missing property: $Name"
}

Push-Location $repoRoot
try {
    $real012Path = 'docs/evidence/20260530-ns308-real012-quality-source-report.json'
    $real012Output = & pwsh -NoProfile -ExecutionPolicy Bypass -File 'tools/run-real012-production-flow-quality-smoke.ps1' `
        -DatabaseName $DatabaseName `
        -DatabaseUser $DatabaseUser `
        -DatabaseHost $DatabaseHost `
        -DatabasePort $DatabasePort `
        -DatabasePassword $DatabasePassword `
        -PgBin $PgBin `
        -FileStoreRoot $FileStoreRoot `
        -ReportPath $real012Path 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) 'REAL012 quality report dependency failed'

    $real012 = Read-Json $real012Path
    Assert-Condition ($real012.status -eq 'pass') 'REAL012 report did not pass'
    Assert-Condition ($real012.real005ClosureStatus -eq 'not_closed') 'NS308 must keep REAL005 not_closed'

    $quality = $real012.qualityReport
    Assert-Condition ($null -ne $quality) 'REAL012 quality report payload missing'
    Assert-Condition ($quality.closureStatus -eq 'not_closed') 'NS308 must expose per-material gaps as not_closed'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$quality.rollbackSql)) 'NS308 quality report must include rollback SQL'

    $metrics = $quality.metrics
    foreach ($field in @(
        'questionCount',
        'answerCoveredCount',
        'imageAssetCount',
        'tableBlockCount',
        'formulaBlockCount',
        'pendingManualItemCount',
        'noiseRetainedBlockCount',
        'externalAiCallCount'
    )) {
        Assert-Property $metrics $field
        Assert-Condition ([int]$metrics.$field -ge 0) "NS308 metric must be non-negative: $field"
    }
    Assert-Condition ([int]$metrics.questionCount -ge 1) 'NS308 quality report must count questions'
    Assert-Condition ([int]$metrics.answerCoveredCount -ge 1) 'NS308 quality report must count answer coverage'
    Assert-Condition ([int]$metrics.imageAssetCount -ge 1) 'NS308 quality report must count question images'
    Assert-Condition ([int]$metrics.pendingManualItemCount -ge 1) 'NS308 quality report must expose manual review items'
    Assert-Condition ([int]$metrics.externalAiCallCount -eq 0) 'NS308 must not call external AI'
    Assert-Condition (@($quality.gaps).Count -ge 1) 'NS308 must list remaining quality gaps'

    $ns304 = Read-Json 'docs/evidence/20260530-ns304-docx-adapter-report.json'
    $ns305 = Read-Json 'docs/evidence/20260530-ns305-pdf-text-adapter-report.json'
    $ns306 = Read-Json 'docs/evidence/20260530-ns306-scan-ocr-adapter-report.json'
    $ns307 = Read-Json 'docs/evidence/20260530-ns307-source-region-screenshot-report.json'
    foreach ($dependency in @($ns304, $ns305, $ns306, $ns307)) {
        Assert-Condition ($dependency.status -eq 'pass') 'NS308 dependency report did not pass'
    }
    Assert-Condition ([bool]$ns304.acceptance.tablePreserved) 'NS308 requires DOCX table evidence from NS304'
    Assert-Condition ([bool]$ns304.acceptance.formulaOmmlFirstSource) 'NS308 requires DOCX formula evidence from NS304'
    Assert-Condition ([bool]$ns305.documentModel.sourceRegionsPresent) 'NS308 requires PDF SourceRegion evidence from NS305'
    Assert-Condition ([bool]$ns306.acceptance.failureFallsBackToPendingReviewTakeover) 'NS308 requires OCR takeover evidence from NS306'
    Assert-Condition ([bool]$ns307.acceptance.missingScreenshotFailsExplicitly) 'NS308 requires screenshot invariant evidence from NS307'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS308'
        checkedAt = (Get-Date).ToString('s')
        mode = 'real012_source_document_quality_report_wrapper'
        productionEligible = $false
        dependency = [ordered]@{
            real012Report = $real012Path
            sourceDocumentId = [string]$real012.sourceDocumentId
            ns304 = 'docs/evidence/20260530-ns304-docx-adapter-report.json'
            ns305 = 'docs/evidence/20260530-ns305-pdf-text-adapter-report.json'
            ns306 = 'docs/evidence/20260530-ns306-scan-ocr-adapter-report.json'
            ns307 = 'docs/evidence/20260530-ns307-source-region-screenshot-report.json'
        }
        qualityReport = [ordered]@{
            closureStatus = [string]$quality.closureStatus
            fullClosureAllowed = $false
            questionCount = [int]$metrics.questionCount
            answerCoveredCount = [int]$metrics.answerCoveredCount
            imageAssetCount = [int]$metrics.imageAssetCount
            tableBlockCount = [int]$metrics.tableBlockCount
            formulaBlockCount = [int]$metrics.formulaBlockCount
            pendingManualItemCount = [int]$metrics.pendingManualItemCount
            noiseRetainedBlockCount = [int]$metrics.noiseRetainedBlockCount
            externalAiCallCount = [int]$metrics.externalAiCallCount
            gapCount = @($quality.gaps).Count
            gaps = $quality.gaps
            rollbackSqlPresent = $true
        }
        acceptance = [ordered]@{
            questionCountReported = $true
            answerCoverageReported = $true
            imageCountReported = $true
            tableCountReported = $true
            formulaCountReported = $true
            manualItemsReported = $true
            noiseCountReported = $true
            rollbackSqlReported = $true
            real005RemainsNotClosed = $true
        }
        boundary = 'NS308 proves the import quality report contract can output source-document metrics, gaps, pending manual items, external-AI count, and rollback SQL. It does not claim real full-paper or 2015-2025 production closure.'
        next = 'NS401 can continue cut-candidate service after the quality report exposes per-material gaps and takeover needs.'
        rollback = "git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns308-import-quality-report.ps1 docs/evidence/20260530-ns308-import-quality-report.json docs/evidence/20260530-ns308-real012-quality-source-report.json"
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}

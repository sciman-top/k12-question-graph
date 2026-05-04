$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$fileRoot = Join-Path $repoRoot 'tmp\j002-text-pdf'
$reportPath = Join-Path $repoRoot 'docs\evidence\j002-text-pdf-adapter-report.json'

Push-Location $repoRoot
try {
    python tools\j002_text_pdf_fixture.py | Write-Host
    if ($LASTEXITCODE -ne 0) { throw "J002 fixture generation failed" }

    $json = python workers\document\worker.py --job-id j002-golden --relative-path j002-golden.pdf --file-root $fileRoot | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw "J002 text PDF worker failed" }
    if ($json.status -ne 'ok') { throw "J002 worker status is not ok" }
    if ($json.adapterDiagnostics[0].adapterName -ne 'pdf_text_adapter') { throw "J002 must use pdf_text_adapter" }
    if (@($json.adapterDiagnostics[0].warnings).Count -ne 0) { throw "J002 text PDF adapter should not emit warnings for golden sample" }

    $pages = @($json.documentModel.pages)
    if ($pages.Count -ne 2) { throw "J002 must preserve two PDF pages" }
    if ($pages[0].pageNumber -ne 1 -or $pages[1].pageNumber -ne 2) { throw "J002 page order is unstable" }

    $blocks = @($pages | ForEach-Object { $_.layoutBlocks })
    if ($blocks.Count -lt 5) { throw "J002 expected at least five text blocks" }
    foreach ($block in $blocks) {
        if ($null -eq $block.sourceRegion) { throw "J002 block missing sourceRegion" }
        if ($block.sourceRegion.source -ne 'pdf_text') { throw "J002 sourceRegion source mismatch" }
        if ($null -eq $block.sourceRegion.pageObject -or $null -eq $block.sourceRegion.contentObject) {
            throw "J002 sourceRegion must include PDF object references"
        }
    }

    $joinedText = ($blocks | ForEach-Object { $_.textPreview }) -join "`n"
    foreach ($text in @('Q1 stem', 'A.', 'B.', 'Answer: B', 'Explanation')) {
        if (-not $joinedText.Contains($text)) {
            throw "missing J002 extracted text: $text"
        }
    }

    $report = [ordered]@{
        status = 'pass'
        task = 'J002'
        adapterName = $json.adapterDiagnostics[0].adapterName
        adapterVersion = $json.adapterDiagnostics[0].adapterVersion
        pageCount = $pages.Count
        blockCount = $blocks.Count
        pageNumbers = @($pages | ForEach-Object { $_.pageNumber })
        sourceRegionsPresent = $true
        source = 'synthetic text pdf'
        productionEligible = $false
    }
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding utf8
    $report | ConvertTo-Json -Depth 6
}
finally {
    Pop-Location
}

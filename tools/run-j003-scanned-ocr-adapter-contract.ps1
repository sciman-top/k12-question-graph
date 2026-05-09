$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$fileRoot = Join-Path $repoRoot 'tmp\j003-scanned-ocr'
$reportPath = Join-Path $repoRoot 'docs\evidence\j003-scanned-ocr-adapter-report.json'

function Assert-RealOcrResult {
    param(
        [Parameter(Mandatory=$true)]$Json,
        [Parameter(Mandatory=$true)][string]$CaseName,
        [Parameter(Mandatory=$true)][string]$ExpectedAdapter
    )

    if ($Json.status -ne 'ok') { throw "$CaseName worker status is not ok" }
    if ($Json.adapterDiagnostics[0].adapterName -ne $ExpectedAdapter) {
        throw "$CaseName must use $ExpectedAdapter"
    }

    $pages = @($Json.documentModel.pages)
    if ($pages.Count -lt 1) { throw "$CaseName must output at least one OCR page" }

    $blocks = @($pages | ForEach-Object { $_.layoutBlocks })
    if ($blocks.Count -lt 1) { throw "$CaseName must output at least one recognized text block" }
    $joined = ($blocks | ForEach-Object { [string]$_.textPreview }) -join "`n"
    if ($joined -notmatch '咸鱼|冷冻室|分子') {
        throw "$CaseName must recognize real Chinese OCR text; got: $joined"
    }
    foreach ($block in $blocks) {
        if ([decimal]$block.confidence -le 0.5) { throw "$CaseName confidence must come from OCR and be > 0.5" }
        if ($block.reviewStatus -ne 'pending_review') { throw "$CaseName must enter pending_review" }
        if ($null -eq $block.sourceRegion) { throw "$CaseName missing sourceRegion" }
        if ($block.sourceRegion.source -notmatch 'rapidocr') { throw "$CaseName sourceRegion must record rapidocr source" }
    }
}

function Assert-OcrReviewResult {
    param(
        [Parameter(Mandatory=$true)]$Json,
        [Parameter(Mandatory=$true)][string]$CaseName
    )

    if ($Json.status -ne 'ok') { throw "$CaseName worker status is not ok" }
    if ($Json.adapterDiagnostics[0].adapterName -ne 'scanned_ocr_review_adapter') {
        throw "$CaseName must use scanned_ocr_review_adapter"
    }
    if (@($Json.adapterDiagnostics[0].warnings).Count -lt 1) {
        throw "$CaseName must record OCR takeover warning"
    }

    $pages = @($Json.documentModel.pages)
    if ($pages.Count -lt 1) { throw "$CaseName must output at least one reviewable page" }

    $blocks = @($pages | ForEach-Object { $_.layoutBlocks })
    if ($blocks.Count -lt 1) { throw "$CaseName must output at least one reviewable candidate block" }
    foreach ($block in $blocks) {
        if ($block.blockType -ne 'ocr_candidate') { throw "$CaseName block must be ocr_candidate" }
        if ([decimal]$block.confidence -ne 0) { throw "$CaseName confidence must be fail-closed at 0" }
        if ($block.reviewStatus -ne 'pending_review') { throw "$CaseName must enter pending_review" }
        if ($block.takeoverRequired -ne $true) { throw "$CaseName must require manual takeover" }
        if ($null -eq $block.sourceRegion) { throw "$CaseName missing sourceRegion" }
        if ($block.sourceRegion.takeoverRequired -ne $true) { throw "$CaseName sourceRegion must require takeover" }
    }
}

Push-Location $repoRoot
try {
    python tools\j003_scanned_ocr_fixture.py | Write-Host
    if ($LASTEXITCODE -ne 0) { throw "J003 fixture generation failed" }

    $pdf = python workers\document\worker.py --job-id j003-scanned --relative-path j003-scanned.pdf --file-root $fileRoot | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw "J003 scanned PDF worker failed" }
    Assert-RealOcrResult -Json $pdf -CaseName 'J003 scanned PDF' -ExpectedAdapter 'rapidocr_scanned_pdf_adapter'

    $image = python workers\document\worker.py --job-id j003-image --relative-path j003-scanned.png --file-root $fileRoot | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw "J003 scanned image worker failed" }
    Assert-RealOcrResult -Json $image -CaseName 'J003 scanned image' -ExpectedAdapter 'rapidocr_image_adapter'

    $invalid = python workers\document\worker.py --job-id j003-invalid --relative-path j003-invalid.png --file-root $fileRoot | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw "J003 invalid image worker failed" }
    Assert-OcrReviewResult -Json $invalid -CaseName 'J003 invalid image'

    $pdfBlocks = @($pdf.documentModel.pages | ForEach-Object { $_.layoutBlocks })
    $imageBlocks = @($image.documentModel.pages | ForEach-Object { $_.layoutBlocks })
    $invalidBlocks = @($invalid.documentModel.pages | ForEach-Object { $_.layoutBlocks })
    $recognizedPreview = ($pdfBlocks | Select-Object -First 3 | ForEach-Object { [string]$_.textPreview }) -join "`n"
    $report = [ordered]@{
        status = 'pass'
        task = 'J003'
        adapterName = $pdf.adapterDiagnostics[0].adapterName
        adapterVersion = $pdf.adapterDiagnostics[0].adapterVersion
        scannedPdfPageCount = @($pdf.documentModel.pages).Count
        scannedPdfBlockCount = $pdfBlocks.Count
        scannedImageAdapterName = $image.adapterDiagnostics[0].adapterName
        scannedImageBlockCount = $imageBlocks.Count
        invalidTakeoverBlockCount = $invalidBlocks.Count
        lowConfidence = $false
        reviewStatus = 'pending_review'
        takeoverRequired = $true
        ocrEngineAvailable = $true
        realOcrTextRecognized = $true
        recognizedPreview = $recognizedPreview
        source = 'synthetic scanned pdf, synthetic scanned image, and invalid image'
        productionEligible = $false
    }
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding utf8
    $report | ConvertTo-Json -Depth 6
}
finally {
    Pop-Location
}

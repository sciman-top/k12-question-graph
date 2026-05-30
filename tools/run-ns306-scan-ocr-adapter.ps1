param(
    [string] $ReportPath = 'docs/evidence/20260530-ns306-scan-ocr-adapter-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

Push-Location $repoRoot
try {
    $j003Output = & pwsh -NoProfile -ExecutionPolicy Bypass -File 'tools/run-j003-scanned-ocr-adapter-contract.ps1' 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) 'J003 scanned OCR adapter dependency failed'

    $j003Path = 'docs/evidence/j003-scanned-ocr-adapter-report.json'
    Assert-Condition (Test-Path -LiteralPath $j003Path) "missing J003 report: $j003Path"
    $j003 = Get-Content -LiteralPath $j003Path -Raw | ConvertFrom-Json

    Assert-Condition ($j003.status -eq 'pass') 'J003 report did not pass'
    Assert-Condition ($j003.adapterName -eq 'rapidocr_scanned_pdf_adapter') 'NS306 scanned PDF must use RapidOCR adapter'
    Assert-Condition ($j003.scannedImageAdapterName -eq 'rapidocr_image_adapter') 'NS306 scanned image must use RapidOCR image adapter'
    Assert-Condition ([int]$j003.scannedPdfBlockCount -ge 1) 'NS306 scanned PDF OCR blocks missing'
    Assert-Condition ([int]$j003.scannedImageBlockCount -ge 1) 'NS306 scanned image OCR blocks missing'
    Assert-Condition ([int]$j003.invalidTakeoverBlockCount -ge 1) 'NS306 invalid image takeover block missing'
    Assert-Condition ($j003.reviewStatus -eq 'pending_review') 'NS306 OCR output must stay pending_review'
    Assert-Condition ($j003.takeoverRequired -eq $true) 'NS306 must preserve takeoverRequired path'
    Assert-Condition ($j003.productionEligible -eq $false) 'NS306 synthetic OCR evidence must not be production eligible'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS306'
        checkedAt = (Get-Date).ToString('s')
        mode = 'j003_scanned_ocr_adapter_contract_wrapper'
        productionEligible = $false
        dependency = [ordered]@{
            task = 'J003'
            report = $j003Path
            scannedPdfAdapter = [string]$j003.adapterName
            scannedImageAdapter = [string]$j003.scannedImageAdapterName
            adapterVersion = [string]$j003.adapterVersion
        }
        ocr = [ordered]@{
            engineAvailable = [bool]$j003.ocrEngineAvailable
            scannedPdfPageCount = [int]$j003.scannedPdfPageCount
            scannedPdfBlockCount = [int]$j003.scannedPdfBlockCount
            scannedImageBlockCount = [int]$j003.scannedImageBlockCount
            realOcrTextRecognized = [bool]$j003.realOcrTextRecognized
            reviewStatus = [string]$j003.reviewStatus
            takeoverRequired = [bool]$j003.takeoverRequired
            invalidTakeoverBlockCount = [int]$j003.invalidTakeoverBlockCount
        }
        acceptance = [ordered]@{
            scannedPdfOcrRuns = $true
            scannedImageOcrRuns = $true
            confidenceAndSourceRegionsCovered = $true
            failureFallsBackToPendingReviewTakeover = $true
            syntheticGoldenOnly = $true
        }
        boundary = 'NS306 proves RapidOCR scanned PDF/image adapters produce pending_review OCR blocks and invalid images fail closed to manual takeover. It does not claim production OCR accuracy for real school materials.'
        next = 'NS307 can continue SourceRegion screenshot path invariants after PDF/OCR adapter evidence.'
        rollback = 'git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns306-scan-ocr-adapter.ps1 docs/evidence/20260530-ns306-scan-ocr-adapter-report.json'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 6
}
finally {
    Pop-Location
}

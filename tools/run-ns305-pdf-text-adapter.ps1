param(
    [string] $ReportPath = 'docs/evidence/20260530-ns305-pdf-text-adapter-report.json'
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
    $j002Output = & pwsh -NoProfile -ExecutionPolicy Bypass -File 'tools/run-j002-text-pdf-adapter-contract.ps1' 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) 'J002 text PDF adapter dependency failed'

    $j002Path = 'docs/evidence/j002-text-pdf-adapter-report.json'
    Assert-Condition (Test-Path -LiteralPath $j002Path) "missing J002 report: $j002Path"
    $j002 = Get-Content -LiteralPath $j002Path -Raw | ConvertFrom-Json

    Assert-Condition ($j002.status -eq 'pass') 'J002 report did not pass'
    Assert-Condition ($j002.adapterName -eq 'pdf_text_adapter') 'NS305 must use pdf_text_adapter'
    Assert-Condition ([int]$j002.pageCount -eq 2) 'NS305 must preserve text PDF pages'
    Assert-Condition ([int]$j002.blockCount -ge 5) 'NS305 expected text PDF blocks'
    Assert-Condition ($j002.sourceRegionsPresent -eq $true) 'NS305 sourceRegion object references missing'
    Assert-Condition ($j002.productionEligible -eq $false) 'NS305 synthetic adapter evidence must not be production eligible'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS305'
        checkedAt = (Get-Date).ToString('s')
        mode = 'j002_pdf_text_adapter_contract_wrapper'
        productionEligible = $false
        dependency = [ordered]@{
            task = 'J002'
            report = $j002Path
            adapterName = [string]$j002.adapterName
            adapterVersion = [string]$j002.adapterVersion
        }
        documentModel = [ordered]@{
            pageCount = [int]$j002.pageCount
            pageNumbers = @($j002.pageNumbers)
            blockCount = [int]$j002.blockCount
            sourceRegionsPresent = [bool]$j002.sourceRegionsPresent
            sourceRegionSource = 'pdf_text'
        }
        acceptance = [ordered]@{
            textPdfAdapterRuns = $true
            pagesPreserved = $true
            textBlocksReturned = $true
            sourceHashAndObjectReferencesAvailable = $true
            syntheticGoldenOnly = $true
        }
        boundary = 'NS305 proves the existing PDF text adapter returns ordered pages, text blocks, and sourceRegion PDF object references for a synthetic text PDF. It does not claim scanned OCR, image PDF, or real copyrighted source quality.'
        next = 'NS306 can continue scanned image/PDF OCR adapter evidence.'
        rollback = 'git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns305-pdf-text-adapter.ps1 docs/evidence/20260530-ns305-pdf-text-adapter-report.json'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 6
}
finally {
    Pop-Location
}

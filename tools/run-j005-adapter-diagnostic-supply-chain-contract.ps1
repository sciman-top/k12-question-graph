$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$reportPath = Join-Path $repoRoot 'docs\evidence\j005-adapter-diagnostic-supply-chain-report.json'

Push-Location $repoRoot
try {
    python tools\j005_adapter_diagnostic_supply_chain.py | Write-Host
    if ($LASTEXITCODE -ne 0) { throw "J005 adapter diagnostic supply-chain gate failed" }

    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    if ($report.status -ne 'pass') { throw "J005 report status is not pass" }
    if ($report.mode -ne 'draft_test') { throw "J005 must stay draft_test" }
    if ($report.productionEligible) { throw "J005 must not be production eligible" }
    if ($report.externalAiCalls -ne 0) { throw "J005 must not call external AI" }
    if ($report.realStudentDataUsed) { throw "J005 must not use real student data" }
    if ($report.supplyChain.externalOcrEngineInvoked) { throw "J005 must not invoke external OCR engines" }
    if (-not $report.supplyChain.localOcrEngineInvoked) { throw "J005 must record local OCR engine invocation" }
    if ($report.supplyChain.localOcrEngine -ne 'rapidocr_onnxruntime') { throw "J005 must record rapidocr_onnxruntime local OCR engine" }
    if ($report.supplyChain.doclingInvoked) { throw "J005 must not invoke Docling in this contract" }
    if ($report.supplyChain.networkAccessRequired) { throw "J005 must not require network access" }

    $requiredFields = @($report.requiredFields)
    foreach ($field in @('adapterName','adapterVersion','toolName','toolVersion','commandArgs','durationMs','inputSha256','outputSha256','warnings','errors')) {
        if ($requiredFields -notcontains $field) { throw "J005 requiredFields missing $field" }
    }

    $cases = @($report.diagnosticCases)
    foreach ($adapter in @('openxml_docx_adapter','pdf_text_adapter','rapidocr_scanned_pdf_adapter','rapidocr_image_adapter','scanned_ocr_review_adapter','placeholder_document_adapter')) {
        if (-not ($cases | Where-Object { $_.adapterName -eq $adapter })) {
            throw "J005 missing diagnostic adapter case: $adapter"
        }
    }
    foreach ($case in $cases) {
        if ([string]::IsNullOrWhiteSpace($case.adapterVersion)) { throw "J005 adapterVersion missing for $($case.caseId)" }
        if ([string]::IsNullOrWhiteSpace($case.toolVersion)) { throw "J005 toolVersion missing for $($case.caseId)" }
        if ($case.durationMs -lt 0) { throw "J005 durationMs invalid for $($case.caseId)" }
        if ($case.inputSha256.Length -ne 64) { throw "J005 inputSha256 invalid for $($case.caseId)" }
        if ($case.outputSha256.Length -ne 64) { throw "J005 outputSha256 invalid for $($case.caseId)" }
        if ($null -eq $case.commandArgs.relativePath) { throw "J005 commandArgs.relativePath missing for $($case.caseId)" }
        if ($case.errorCount -ne 0) { throw "J005 successful case has errors for $($case.caseId)" }
    }

    [ordered]@{
        status = 'pass'
        task = 'J005'
        mode = [string]$report.mode
        diagnosticCaseCount = $cases.Count
        adapterNames = @($report.adapterNames)
        toolVersions = @($report.toolVersions)
        externalOcrEngineInvoked = [bool]$report.supplyChain.externalOcrEngineInvoked
        localOcrEngineInvoked = [bool]$report.supplyChain.localOcrEngineInvoked
        localOcrEngine = [string]$report.supplyChain.localOcrEngine
        networkAccessRequired = [bool]$report.supplyChain.networkAccessRequired
    } | ConvertTo-Json -Depth 6
}
finally {
    Pop-Location
}

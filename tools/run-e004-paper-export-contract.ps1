param(
    [string] $OutputRoot = 'tmp\e004-paper-export',
    [string] $Report = 'docs\evidence\e004-paper-export-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Push-Location $repoRoot
try {
    python tools\e004_paper_export.py --output-root $OutputRoot --report $Report | Write-Host
    if ($LASTEXITCODE -ne 0) {
        throw "E004 paper export failed"
    }

    $reportObject = Get-Content -LiteralPath $Report -Raw | ConvertFrom-Json
    if ($reportObject.status -ne 'pass') { throw "E004 report status is not pass" }
    if ($reportObject.mode -ne 'draft_test') { throw "E004 must stay draft_test" }
    if ($reportObject.productionEligible) { throw "E004 must not be production eligible" }
    if ($reportObject.formalC002Required) { throw "E004 must not require formal C002" }
    if (-not (Test-Path -LiteralPath $reportObject.docxPath)) { throw "E004 DOCX artifact missing" }
    if (-not (Test-Path -LiteralPath $reportObject.pdfPath)) { throw "E004 PDF artifact missing" }
    if (-not $reportObject.docxChecks.hasFormulaText) { throw "E004 DOCX formula text missing" }
    if (-not $reportObject.docxChecks.hasFigureMedia) { throw "E004 DOCX figure media missing" }
    if (-not $reportObject.docxChecks.hasTable) { throw "E004 DOCX table missing" }
    if (-not $reportObject.pdfChecks.hasPdfHeader) { throw "E004 PDF header missing" }

    $app = Get-Content -LiteralPath 'apps\web\src\App.tsx' -Raw
    foreach ($pattern in @(
        'data-flow="paper-export"',
        'data-action="export-docx"',
        'data-action="export-pdf"',
        'data-contract="export-productionEligible=false"',
        'data-contract="export-artifact-checks"'
    )) {
        if (-not $app.Contains($pattern)) {
            throw "missing E004 UI contract marker: $pattern"
        }
    }

    [ordered]@{
        status = 'pass'
        task = 'E004'
        mode = [string]$reportObject.mode
        productionEligible = [bool]$reportObject.productionEligible
        docxPath = [string]$reportObject.docxPath
        pdfPath = [string]$reportObject.pdfPath
        docxHasFormula = [bool]$reportObject.docxChecks.hasFormulaText
        docxHasFigure = [bool]$reportObject.docxChecks.hasFigureMedia
        docxHasTable = [bool]$reportObject.docxChecks.hasTable
        pdfHasHeader = [bool]$reportObject.pdfChecks.hasPdfHeader
    } | ConvertTo-Json
}
finally {
    Pop-Location
}

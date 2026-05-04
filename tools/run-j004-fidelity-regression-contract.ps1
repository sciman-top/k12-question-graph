$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$reportPath = Join-Path $repoRoot 'docs\evidence\j004-fidelity-regression-report.json'

Push-Location $repoRoot
try {
    python tools\j004_fidelity_regression.py | Write-Host
    if ($LASTEXITCODE -ne 0) { throw "J004 fidelity regression failed" }

    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    if ($report.status -ne 'pass') { throw "J004 report status is not pass" }
    if ($report.mode -ne 'draft_test') { throw "J004 must stay draft_test" }
    if ($report.productionEligible) { throw "J004 must not be production eligible" }
    if ($report.externalAiCalls -ne 0) { throw "J004 must not call external AI" }
    if ($report.realStudentDataUsed) { throw "J004 must not use real student data" }
    if (-not $report.importChecks.hasFormulaBlock) { throw "J004 import formula block missing" }
    if (-not $report.importChecks.hasTableBlock) { throw "J004 import table block missing" }
    if (-not $report.importChecks.hasImageBlock) { throw "J004 import image block missing" }
    if ($report.draftChecks.formulaBlocks -lt 1) { throw "J004 draft formula block missing" }
    if ($report.draftChecks.tableBlocks -lt 1) { throw "J004 draft table block missing" }
    if ($report.draftChecks.imageAssets -lt 1) { throw "J004 draft image asset missing" }
    if (-not $report.draftChecks.sourceRegionsPreserved) { throw "J004 source regions not preserved" }
    if (-not $report.exportChecks.docx.hasFormulaText) { throw "J004 export formula missing" }
    if (-not $report.exportChecks.docx.hasTable) { throw "J004 export table missing" }
    if (-not $report.exportChecks.docx.hasFigureMedia) { throw "J004 export figure media missing" }
    if (-not $report.exportChecks.pdf.hasPdfHeader) { throw "J004 PDF header missing" }

    [ordered]@{
        status = 'pass'
        task = 'J004'
        mode = [string]$report.mode
        productionEligible = [bool]$report.productionEligible
        importHasFormula = [bool]$report.importChecks.hasFormulaBlock
        importHasTable = [bool]$report.importChecks.hasTableBlock
        importHasImage = [bool]$report.importChecks.hasImageBlock
        draftImageAssets = [int]$report.draftChecks.imageAssets
        exportHasFormula = [bool]$report.exportChecks.docx.hasFormulaText
        exportHasTable = [bool]$report.exportChecks.docx.hasTable
        exportHasFigure = [bool]$report.exportChecks.docx.hasFigureMedia
    } | ConvertTo-Json
}
finally {
    Pop-Location
}

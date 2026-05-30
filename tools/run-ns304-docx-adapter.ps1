param(
    [string] $ReportPath = 'docs/evidence/20260530-ns304-docx-adapter-report.json'
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
    $j001Output = & pwsh -NoProfile -ExecutionPolicy Bypass -File 'tools/run-j001-openxml-docx-adapter-contract.ps1' 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) 'J001 OpenXML DOCX adapter dependency failed'

    $j001Path = 'docs/evidence/j001-openxml-docx-adapter-report.json'
    Assert-Condition (Test-Path -LiteralPath $j001Path) "missing J001 report: $j001Path"
    $j001 = Get-Content -LiteralPath $j001Path -Raw | ConvertFrom-Json

    Assert-Condition ($j001.status -eq 'pass') 'J001 report did not pass'
    Assert-Condition ($j001.adapterName -eq 'openxml_docx_adapter') 'NS304 must use openxml_docx_adapter'
    Assert-Condition ($j001.hasQuestionStem -eq $true) 'NS304 missing question stem block'
    Assert-Condition ($j001.hasOptions -eq $true) 'NS304 missing option blocks'
    Assert-Condition ($j001.hasAnswer -eq $true) 'NS304 missing answer block'
    Assert-Condition ($j001.hasExplanation -eq $true) 'NS304 missing explanation block'
    Assert-Condition ($j001.hasTable -eq $true) 'NS304 missing table block'
    Assert-Condition ($j001.hasFormula -eq $true) 'NS304 missing formula block'
    Assert-Condition ($j001.formulaSourceFormat -eq 'omml') 'NS304 must preserve OMML as first source'
    Assert-Condition ($j001.formulaOmmlPreserved -eq $true) 'NS304 OMML payload not preserved'
    Assert-Condition ($j001.productionEligible -eq $false) 'NS304 synthetic adapter evidence must not be production eligible'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS304'
        checkedAt = (Get-Date).ToString('s')
        mode = 'j001_openxml_docx_adapter_contract_wrapper'
        productionEligible = $false
        dependency = [ordered]@{
            task = 'J001'
            report = $j001Path
            adapterName = [string]$j001.adapterName
            adapterVersion = [string]$j001.adapterVersion
        }
        documentModel = [ordered]@{
            blockTypes = @($j001.blockTypes)
            hasQuestionStem = [bool]$j001.hasQuestionStem
            hasOptions = [bool]$j001.hasOptions
            hasAnswer = [bool]$j001.hasAnswer
            hasExplanation = [bool]$j001.hasExplanation
            hasTable = [bool]$j001.hasTable
            hasFormula = [bool]$j001.hasFormula
        }
        formula = [ordered]@{
            firstSource = 'omml'
            formulaSourceFormat = [string]$j001.formulaSourceFormat
            ommlPreserved = [bool]$j001.formulaOmmlPreserved
            derivativeText = [string]$j001.formulaLatexDerivative
        }
        acceptance = [ordered]@{
            docxOpenXmlAdapterRuns = $true
            documentModelBlocksReturned = $true
            tablePreserved = $true
            formulaOmmlFirstSource = $true
            syntheticGoldenOnly = $true
        }
        boundary = 'NS304 proves the existing OpenXML DOCX adapter returns DocumentModel blocks with table and OMML formula evidence. It does not claim scanned OCR, PDF layout, or real copyrighted source ingestion.'
        next = 'NS305 can continue PDF text/layout adapter evidence.'
        rollback = 'git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns304-docx-adapter.ps1 docs/evidence/20260530-ns304-docx-adapter-report.json'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 6
}
finally {
    Pop-Location
}

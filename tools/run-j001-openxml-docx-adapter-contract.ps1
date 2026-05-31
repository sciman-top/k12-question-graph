$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$fileRoot = Join-Path $repoRoot 'tmp\j001-openxml-docx'
$fixture = Join-Path $fileRoot 'j001-golden.docx'
$reportPath = Join-Path $repoRoot 'docs\evidence\j001-openxml-docx-adapter-report.json'

Push-Location $repoRoot
try {
    python tools\j001_openxml_docx_fixture.py | Write-Host
    if ($LASTEXITCODE -ne 0) { throw "J001 fixture generation failed" }

    $workerOutputPath = Join-Path $fileRoot 'worker-output.json'
    $workerErrorPath = Join-Path $fileRoot 'worker-error.log'
    python workers\document\worker.py --job-id j001-golden --relative-path j001-golden.docx --file-root $fileRoot > $workerOutputPath 2> $workerErrorPath
    if ($LASTEXITCODE -ne 0) { throw "J001 OpenXML worker failed" }
    $json = Get-Content -LiteralPath $workerOutputPath -Raw | ConvertFrom-Json
    if ($json.status -ne 'ok') { throw "J001 worker status is not ok" }
    if ($json.adapterDiagnostics[0].adapterName -ne 'openxml_docx_adapter') { throw "J001 must use openxml_docx_adapter" }
    if (@($json.adapterDiagnostics[0].warnings).Count -ne 0) { throw "J001 OpenXML adapter should not emit placeholder warnings" }

    $blocks = @($json.documentModel.pages[0].layoutBlocks)
    foreach ($blockType in @('question_stem', 'option', 'answer', 'explanation', 'table', 'formula')) {
        if (-not ($blocks | Where-Object { $_.blockType -eq $blockType })) {
            throw "missing J001 block type: $blockType"
        }
    }

    $joinedText = ($blocks | ForEach-Object { $_.textPreview }) -join "`n"
    foreach ($text in @('A.', 'B.', 'F=ma')) {
        if (-not $joinedText.Contains($text)) {
            throw "missing J001 extracted text: $text"
        }
    }

    $table = $blocks | Where-Object { $_.blockType -eq 'table' } | Select-Object -First 1
    if (-not $table.table.rows -or @($table.table.rows).Count -lt 2) {
        throw "J001 table rows missing"
    }

    $formula = $blocks | Where-Object { $_.blockType -eq 'formula' } | Select-Object -First 1
    if (-not $formula.formula -or $formula.formula.sourceFormat -ne 'omml') {
        throw "J001 formula OMML source format missing"
    }
    if (@($formula.formula.formulas).Count -lt 1 -or [string]::IsNullOrWhiteSpace([string]$formula.formula.formulas[0].omml)) {
        throw "J001 formula OMML payload missing"
    }
    if ([string]$formula.formula.formulas[0].latex -ne 'F=ma') {
        throw "J001 formula LaTeX/text derivative missing"
    }

    $report = [ordered]@{
        status = 'pass'
        task = 'J001'
        adapterName = $json.adapterDiagnostics[0].adapterName
        adapterVersion = $json.adapterDiagnostics[0].adapterVersion
        blockTypes = @($blocks | ForEach-Object { $_.blockType })
        hasQuestionStem = $true
        hasOptions = $true
        hasAnswer = $true
        hasExplanation = $true
        hasTable = $true
        hasFormula = $true
        formulaSourceFormat = [string]$formula.formula.sourceFormat
        formulaOmmlPreserved = $true
        formulaLatexDerivative = [string]$formula.formula.formulas[0].latex
        source = 'synthetic golden docx'
        productionEligible = $false
    }
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding utf8
    $report | ConvertTo-Json -Depth 6
}
finally {
    Pop-Location
}

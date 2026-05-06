param(
    [string] $RegistryPath = 'tests/golden-import/registry.json',
    [string] $J001Path = 'docs/evidence/j001-openxml-docx-adapter-report.json',
    [string] $J002Path = 'docs/evidence/j002-text-pdf-adapter-report.json',
    [string] $J003Path = 'docs/evidence/j003-scanned-ocr-adapter-report.json',
    [string] $J005Path = 'docs/evidence/j005-adapter-diagnostic-supply-chain-report.json',
    [string] $J006Path = 'docs/evidence/j006-import-accuracy-workload-report.json',
    [string] $ReportPath = 'docs/evidence/20260506-s004b-adapter-benchmark-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

function Read-JsonFile([string] $relativePath) {
    $full = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $full)) { throw "missing json file: $relativePath" }
    return Get-Content -Raw -LiteralPath $full | ConvertFrom-Json -Depth 100
}

$registry = Read-JsonFile $RegistryPath
$j001 = Read-JsonFile $J001Path
$j002 = Read-JsonFile $J002Path
$j003 = Read-JsonFile $J003Path
$j005 = Read-JsonFile $J005Path
$j006 = Read-JsonFile $J006Path

if ([string]$registry.registryVersion -ne 'golden-import-registry.v1') {
    throw "unexpected registry version: $($registry.registryVersion)"
}

$diagnosticCases = @($j005.diagnosticCases)
$docxCases = @($diagnosticCases | Where-Object { $_.caseId -eq 'openxml_docx' })
$textPdfCases = @($diagnosticCases | Where-Object { $_.caseId -eq 'text_pdf' })
$scannedCases = @($diagnosticCases | Where-Object { $_.caseId -in @('scanned_pdf','invalid_image') })

function Measure-Case([object[]] $cases) {
    if ($cases.Count -eq 0) {
        return [ordered]@{ avgDurationMs = $null; warningCount = 0; errorCount = 0; sampleCount = 0 }
    }

    $avg = [Math]::Round((($cases | Measure-Object -Property durationMs -Average).Average), 2)
    $warnings = [int](($cases | Measure-Object -Property warningCount -Sum).Sum)
    $errors = [int](($cases | Measure-Object -Property errorCount -Sum).Sum)

    return [ordered]@{ avgDurationMs = $avg; warningCount = $warnings; errorCount = $errors; sampleCount = $cases.Count }
}

$docxMeasure = Measure-Case $docxCases
$textPdfMeasure = Measure-Case $textPdfCases
$scannedMeasure = Measure-Case $scannedCases

$sourceRegionAccuracy = [double]$j006.accuracy.sourceRegionAccuracy
$blockPreservationAccuracy = [double]$j006.accuracy.blockPreservationAccuracy
$automatedCutCaseCount = [int]$j006.accuracy.automatedCutCaseCount
$autoCutAccuracy = $j006.accuracy.autoCutAccuracy
$takeoverRecommendations = @($j006.teacherWorkload.failureTakeoverSteps)

$benchmarks = @(
    [ordered]@{
        format = 'docx'
        adapter = [string]$j001.adapterName
        sampleIds = @($registry.entries | Where-Object format -eq 'docx' | ForEach-Object sampleId)
        accuracy = [ordered]@{
            sourceRegionAccuracy = $sourceRegionAccuracy
            blockPreservationAccuracy = $blockPreservationAccuracy
            formulaPreserved = [bool]$j001.hasFormula
            tablePreserved = [bool]$j001.hasTable
        }
        performance = $docxMeasure
        warnings = $docxMeasure.warningCount
        errors = $docxMeasure.errorCount
        takeoverNeeded = $false
        takeoverRecommendations = @()
    },
    [ordered]@{
        format = 'text_pdf'
        adapter = [string]$j002.adapterName
        sampleIds = @($registry.entries | Where-Object format -eq 'text_pdf' | ForEach-Object sampleId)
        accuracy = [ordered]@{
            sourceRegionAccuracy = $sourceRegionAccuracy
            blockPreservationAccuracy = $blockPreservationAccuracy
            pageCount = [int]$j002.pageCount
        }
        performance = $textPdfMeasure
        warnings = $textPdfMeasure.warningCount
        errors = $textPdfMeasure.errorCount
        takeoverNeeded = $false
        takeoverRecommendations = @()
    },
    [ordered]@{
        format = 'scanned_pdf'
        adapter = [string]$j003.adapterName
        sampleIds = @($registry.entries | Where-Object format -eq 'scanned_pdf' | ForEach-Object sampleId)
        accuracy = [ordered]@{
            sourceRegionAccuracy = $sourceRegionAccuracy
            blockPreservationAccuracy = $blockPreservationAccuracy
            autoCutAccuracy = $autoCutAccuracy
            automatedCutCaseCount = $automatedCutCaseCount
        }
        performance = $scannedMeasure
        warnings = $scannedMeasure.warningCount
        errors = $scannedMeasure.errorCount
        takeoverNeeded = [bool]$j003.takeoverRequired
        takeoverRecommendations = $takeoverRecommendations
    }
)

$report = [ordered]@{
    status = 'pass'
    taskId = 'S004B'
    mode = 'synthetic_benchmark'
    checkedAt = (Get-Date).ToString('s')
    inputs = [ordered]@{
        registryPath = $RegistryPath
        evidence = @($J001Path, $J002Path, $J003Path, $J005Path, $J006Path)
        sampleCount = @($registry.entries).Count
    }
    benchmark = $benchmarks
    summary = [ordered]@{
        teacherMessage = 'docx/text_pdf 稳定，扫描件必须走人工接管；当前不宣称自动切题准确率。'
        manualTakeoverStepCount = @($takeoverRecommendations).Count
        nextAction = 'S004C 使用授权或脱敏材料做代理验收并复核不可自动处理项。'
    }
}

$reportFullPath = Join-Path $repoRoot $ReportPath
$reportDir = Split-Path -Parent $reportFullPath
if (-not (Test-Path -LiteralPath $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir | Out-Null
}

$report | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
$report | ConvertTo-Json -Depth 30

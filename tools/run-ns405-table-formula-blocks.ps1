param(
    [string] $ReportPath = 'docs/evidence/20260530-ns405-table-formula-blocks-report.json',
    [string] $TableSourceReportPath = 'docs/evidence/20260530-ns405-real009-table-source-report.json',
    [string] $FormulaSourceReportPath = 'docs/evidence/20260530-ns405-real010-formula-source-report.json',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [int] $TableApiPort = 0,
    [int] $FormulaApiPort = 0,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Read-Json([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing report: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse('127.0.0.1'), 0)
    try {
        $listener.Start()
        return $listener.LocalEndpoint.Port
    }
    finally {
        $listener.Stop()
    }
}

Push-Location $repoRoot
try {
    $ns403 = Read-Json 'docs/evidence/20260530-ns403-review-workbench-ui-report.json'
    Assert-Condition ($ns403.status -eq 'pass') 'NS405 dependency NS403 report did not pass'

    $buildOutput = dotnet build 'apps/api/K12QuestionGraph.Api.csproj' -c Release 2>&1
    Assert-Condition ($LASTEXITCODE -eq 0) 'dotnet build failed before NS405 table/formula smoke'

    if ($TableApiPort -le 0) {
        $TableApiPort = Get-FreeTcpPort
    }
    if ($FormulaApiPort -le 0) {
        $FormulaApiPort = Get-FreeTcpPort
    }

    $real009Output = & pwsh -NoProfile -ExecutionPolicy Bypass -File 'tools/run-real009-table-structure-smoke.ps1' `
        -DatabaseName $DatabaseName `
        -DatabaseUser $DatabaseUser `
        -DatabaseHost $DatabaseHost `
        -DatabasePort $DatabasePort `
        -DatabasePassword $DatabasePassword `
        -FileStoreRoot $FileStoreRoot `
        -ApiPort $TableApiPort `
        -PgBin $PgBin `
        -ReportPath $TableSourceReportPath 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "REAL009 table dependency failed: $real009Output"

    $real010Output = & pwsh -NoProfile -ExecutionPolicy Bypass -File 'tools/run-real010-formula-fidelity-smoke.ps1' `
        -DatabaseName $DatabaseName `
        -DatabaseUser $DatabaseUser `
        -DatabaseHost $DatabaseHost `
        -DatabasePort $DatabasePort `
        -DatabasePassword $DatabasePassword `
        -FileStoreRoot $FileStoreRoot `
        -ApiPort $FormulaApiPort `
        -PgBin $PgBin `
        -ReportPath $FormulaSourceReportPath 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "REAL010 formula dependency failed: $real010Output"

    $real009 = Read-Json $TableSourceReportPath
    $real010 = Read-Json $FormulaSourceReportPath
    Assert-Condition ($real009.status -eq 'pass' -and $real009.task -eq 'REAL009') 'REAL009 source report did not pass'
    Assert-Condition ($real010.status -eq 'pass' -and $real010.task -eq 'REAL010') 'REAL010 source report did not pass'

    Assert-Condition ($real009.tableStructure.columnCount -ge 1) 'NS405 table columns missing'
    Assert-Condition ($real009.tableStructure.rowCount -ge 1) 'NS405 table rows missing'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$real009.tableStructure.caption)) 'NS405 table caption missing'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$real009.tableStructure.sourceRegionId)) 'NS405 table sourceRegionId missing'
    Assert-Condition ([double]$real009.tableStructure.confidence -lt 0.8) 'NS405 table low-confidence path missing'
    Assert-Condition ([string]$real009.tableStructure.reviewStatus -eq 'pending_review') 'NS405 table pending_review missing'
    Assert-Condition ([bool]$real009.cardProbe.hasTable) 'NS405 card hasTable missing'
    Assert-Condition (-not [bool]$real009.cardProbe.hasImage) 'NS405 table must not be treated as question image'
    Assert-Condition ([string]$real009.sourceProbe.tableRegionType -eq 'question_table') 'NS405 table source region type missing'
    Assert-Condition ([int]$real009.sourceProbe.tableScreenshotStatusCode -eq 200) 'NS405 table screenshot must render'
    Assert-Condition ([string]$real009.reviewQueueProbe.reviewType -eq 'question_table_block_review') 'NS405 table review type missing'
    Assert-Condition ([string]$real009.reviewQueueProbe.requiredAction -eq 'review_table_structure') 'NS405 table review action missing'

    Assert-Condition ([string]$real010.officeFormula.sourceFormat -eq 'omml') 'NS405 Office formula must use OMML source'
    Assert-Condition ([bool]$real010.officeFormula.ommlPreserved) 'NS405 OMML payload missing'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$real010.officeFormula.latex)) 'NS405 LaTeX derivative missing'
    Assert-Condition ([bool]$real010.officeFormula.mathmlPresent) 'NS405 MathML derivative missing'
    Assert-Condition ([string]$real010.officeFormula.exportPreference -eq 'omml') 'NS405 formula export preference must be OMML'
    Assert-Condition ([string]$real010.scannedFormula.sourceFormat -eq 'scanned_formula_candidate') 'NS405 scanned formula source format missing'
    Assert-Condition ([double]$real010.scannedFormula.confidence -lt 0.9) 'NS405 scanned formula low-confidence path missing'
    Assert-Condition ([string]$real010.scannedFormula.reviewStatus -eq 'pending_review') 'NS405 scanned formula pending_review missing'
    Assert-Condition ([int]$real010.scannedFormula.fallbackImageStatusCode -eq 200) 'NS405 scanned formula fallback image must render'
    Assert-Condition ([bool]$real010.cardProbe.hasFormula) 'NS405 card hasFormula missing'
    Assert-Condition (-not [bool]$real010.cardProbe.hasImage) 'NS405 formula fallback must not be treated as question image'
    Assert-Condition ([string]$real010.reviewQueueProbe.reviewType -eq 'question_formula_block_review') 'NS405 formula review type missing'
    Assert-Condition ([string]$real010.reviewQueueProbe.requiredAction -eq 'review_formula_structure') 'NS405 formula review action missing'

    $program = Get-Content -LiteralPath 'apps/api/Program.cs' -Raw
    foreach ($marker in @(
        'RequiresTableBlockReview',
        'CreateTableBlockReviewItem',
        'question_table_block_review',
        'review_table_structure',
        'RequiresFormulaBlockReview',
        'CreateFormulaBlockReviewItem',
        'question_formula_block_review',
        'review_formula_structure'
    )) {
        Assert-Condition ($program.Contains($marker)) "NS405 API marker missing: $marker"
    }

    $worker = Get-Content -LiteralPath 'workers/document/worker.py' -Raw
    foreach ($marker in @(
        'formula_payload',
        'oMath',
        '"blockType": "table"',
        '"formulas": formulas'
    )) {
        Assert-Condition ($worker.Contains($marker)) "NS405 worker marker missing: $marker"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS405'
        checkedAt = (Get-Date).ToString('s')
        mode = 'real009_real010_table_formula_wrapper_plus_api_worker_markers'
        productionEligible = $false
        dependency = [ordered]@{
            ns403 = 'docs/evidence/20260530-ns403-review-workbench-ui-report.json'
            real009 = $TableSourceReportPath
            real010 = $FormulaSourceReportPath
        }
        tableBlock = [ordered]@{
            questionId = [string]$real009.questionId
            tableBlockId = [string]$real009.tableBlockId
            sourceRegionId = [string]$real009.tableSourceRegionId
            caption = [string]$real009.tableStructure.caption
            columnCount = [int]$real009.tableStructure.columnCount
            rowCount = [int]$real009.tableStructure.rowCount
            confidence = [double]$real009.tableStructure.confidence
            reviewStatus = [string]$real009.tableStructure.reviewStatus
            cardHasTable = [bool]$real009.cardProbe.hasTable
            tableScreenshotStatusCode = [int]$real009.sourceProbe.tableScreenshotStatusCode
            reviewType = [string]$real009.reviewQueueProbe.reviewType
            requiredAction = [string]$real009.reviewQueueProbe.requiredAction
        }
        formulaBlock = [ordered]@{
            questionId = [string]$real010.questionId
            officeBlockId = [string]$real010.officeFormula.blockId
            officeSourceFormat = [string]$real010.officeFormula.sourceFormat
            ommlPreserved = [bool]$real010.officeFormula.ommlPreserved
            latex = [string]$real010.officeFormula.latex
            mathmlPresent = [bool]$real010.officeFormula.mathmlPresent
            exportPreference = [string]$real010.officeFormula.exportPreference
            scannedBlockId = [string]$real010.scannedFormula.blockId
            scannedSourceFormat = [string]$real010.scannedFormula.sourceFormat
            scannedConfidence = [double]$real010.scannedFormula.confidence
            scannedReviewStatus = [string]$real010.scannedFormula.reviewStatus
            fallbackImageStatusCode = [int]$real010.scannedFormula.fallbackImageStatusCode
            cardHasFormula = [bool]$real010.cardProbe.hasFormula
            cardHasImage = [bool]$real010.cardProbe.hasImage
            reviewType = [string]$real010.reviewQueueProbe.reviewType
            requiredAction = [string]$real010.reviewQueueProbe.requiredAction
        }
        acceptance = [ordered]@{
            tableSavedAsStructuredJson = $true
            tableKeepsSourceRegionAndScreenshot = $true
            lowConfidenceTableGoesToReview = $true
            formulaKeepsOmmlAsFirstSource = $true
            latexAndMathmlAreDerivatives = $true
            scannedFormulaKeepsFallbackImage = $true
            lowConfidenceFormulaGoesToReview = $true
            tableAndFormulaAreNotMisclassifiedAsQuestionImages = $true
        }
        boundary = 'NS405 proves structured table and formula QuestionBlock contracts through REAL009/REAL010 API smoke plus API/worker markers. It does not claim full Word/PDF export visual fidelity or onsite teacher validation.'
        next = 'NS406 can combine NS404 and NS405 evidence for question edit, recrop, merge/split, and audit.'
        rollback = "git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns405-table-formula-blocks.ps1 docs/evidence/20260530-ns405-table-formula-blocks-report.json docs/evidence/20260530-ns405-real009-table-source-report.json docs/evidence/20260530-ns405-real010-formula-source-report.json"
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}

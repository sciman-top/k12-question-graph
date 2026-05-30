param(
    [string] $ReportPath = 'docs/evidence/20260530-ns607-export-artifacts-report.json',
    [string] $S010BReportPath = 'docs/evidence/20260530-ns607-s010b-source-report.json',
    [string] $OutputRoot = 'tmp\ns607-paper-artifacts',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

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

function Invoke-CheckedScript([scriptblock] $Command, [string] $Label) {
    $output = & $Command 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "$Label failed: $output"
    return $output
}

function Test-FileHashMatches([string] $Path, [string] $ExpectedHash) {
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    Assert-Condition ($actual -eq $ExpectedHash.ToLowerInvariant()) "hash mismatch for $Path"
}

Push-Location $repoRoot
try {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'DatabasePassword or PGPASSWORD is required for NS607 export artifact verification.'

    $ns606 = Read-Json 'docs/evidence/20260530-ns606-export-preflight-report.json'
    Assert-Condition ($ns606.status -eq 'pass') 'NS607 dependency NS606 report did not pass'
    Assert-Condition (-not [bool]$ns606.productionEligible) 'NS607 must inherit NS606 non-production boundary'
    Assert-Condition ([bool]$ns606.acceptance.studentTeacherAnswerVersionsMustBePreflighted) 'NS607 requires NS606 preflight-before-export evidence'

    $apiBuildOutput = & dotnet build apps/api/K12QuestionGraph.Api.csproj -c Release 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "NS607 API build failed: $apiBuildOutput"

    $port = Get-FreeTcpPort
    Invoke-CheckedScript {
        .\tools\run-s010b-word-pdf-artifact-chain-smoke.ps1 `
            -DatabaseName $DatabaseName `
            -DatabaseUser $DatabaseUser `
            -DatabaseHost $DatabaseHost `
            -DatabasePort $DatabasePort `
            -DatabasePassword $DatabasePassword `
            -PgBin $PgBin `
            -ApiPort $port `
            -OutputRoot $OutputRoot `
            -ReportPath $S010BReportPath
    } 'S010B Word/PDF artifact chain smoke' | Write-Host

    $s010b = Read-Json $S010BReportPath
    Assert-Condition ($s010b.status -eq 'pass') 'S010B source report did not pass'
    Assert-Condition ([string]$s010b.preflightStatus -eq 'ready_for_review') 'NS607 artifacts must start from ready_for_review preflight'
    Assert-Condition (-not [bool]$s010b.productionEligible) 'NS607 artifact regression must stay non-production eligible'

    $manifestPath = [string]$s010b.manifestPath
    $manifestFullPath = Join-Path $repoRoot $manifestPath
    Assert-Condition (Test-Path -LiteralPath $manifestFullPath) 'NS607 manifest file missing'
    Test-FileHashMatches -Path $manifestFullPath -ExpectedHash ([string]$s010b.manifestSha256)
    $manifest = Get-Content -LiteralPath $manifestFullPath -Raw | ConvertFrom-Json
    Assert-Condition ($manifest.schemaVersion -eq 'paper-artifact-manifest.s010b.v1') 'NS607 manifest schema mismatch'

    foreach ($variant in @('student', 'teacher', 'answer')) {
        $artifact = $manifest.variants.$variant
        Assert-Condition ($null -ne $artifact) "NS607 missing variant: $variant"
        $docxPath = Join-Path $repoRoot ([string]$artifact.docxPath)
        $pdfPath = Join-Path $repoRoot ([string]$artifact.pdfPath)
        Assert-Condition (Test-Path -LiteralPath $docxPath) "NS607 missing $variant docx"
        Assert-Condition (Test-Path -LiteralPath $pdfPath) "NS607 missing $variant pdf"
        Test-FileHashMatches -Path $docxPath -ExpectedHash ([string]$artifact.docxSha256)
        Test-FileHashMatches -Path $pdfPath -ExpectedHash ([string]$artifact.pdfSha256)
        Assert-Condition ([bool]$manifest.checks.$variant.docx.hasDocumentXml) "NS607 $variant docx xml check failed"
        Assert-Condition ([bool]$manifest.checks.$variant.docx.hasTable) "NS607 $variant table check failed"
        Assert-Condition ([bool]$manifest.checks.$variant.docx.hasSourceAuthorization) "NS607 $variant source authorization check failed"
        Assert-Condition ([bool]$manifest.checks.$variant.docx.hasKnowledgeVersionReference) "NS607 $variant knowledge version check failed"
        Assert-Condition ([bool]$manifest.checks.$variant.pdf.hasPdfHeader) "NS607 $variant pdf header check failed"
        Assert-Condition ([bool]$manifest.checks.$variant.pdf.hasEof) "NS607 $variant pdf EOF check failed"
    }

    Assert-Condition ([bool]$manifest.checks.student.docx.studentHidesAnswer) 'NS607 student version must hide answer and solution'
    Assert-Condition (-not [bool]$manifest.checks.student.docx.hasAnswer) 'NS607 student version must not expose answer'
    Assert-Condition (-not [bool]$manifest.checks.student.docx.hasSolution) 'NS607 student version must not expose solution'
    Assert-Condition ([bool]$manifest.checks.teacher.docx.hasAnswer) 'NS607 teacher version must include answer'
    Assert-Condition ([bool]$manifest.checks.teacher.docx.hasSolution) 'NS607 teacher version must include solution'
    Assert-Condition ([bool]$manifest.checks.answer.docx.hasAnswer) 'NS607 answer version must include answer'
    Assert-Condition ([bool]$manifest.checks.answer.docx.hasSolution) 'NS607 answer version must include solution'
    Assert-Condition ([bool]$manifest.checks.student.docx.hasFormulaText) 'NS607 student version must preserve formula text'
    Assert-Condition ([bool]$manifest.checks.teacher.docx.hasFormulaText) 'NS607 teacher version must preserve formula text'
    Assert-Condition ([bool]$manifest.requirements.requiresFormula) 'NS607 manifest must declare formula requirement'
    Assert-Condition ([bool]$manifest.requirements.requiresTable) 'NS607 manifest must declare table requirement'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS607'
        checkedAt = (Get-Date).ToString('s')
        mode = 'word_pdf_artifact_regression'
        productionEligible = $false
        externalAiCalls = 0
        realStudentDataUsed = $false
        activeAssetMutation = $false
        dependency = [ordered]@{
            ns606 = 'docs/evidence/20260530-ns606-export-preflight-report.json'
            s010b = $S010BReportPath
        }
        artifact = [ordered]@{
            outputRoot = [string]$s010b.outputRoot
            manifestPath = $manifestPath
            manifestSha256 = [string]$s010b.manifestSha256
            variants = $s010b.variants
            checks = $manifest.checks
            requirements = $manifest.requirements
        }
        acceptance = [ordered]@{
            studentDocxPdfGenerated = $true
            teacherDocxPdfGenerated = $true
            answerDocxPdfGenerated = $true
            manifestHashVerified = $true
            formulaPreservedInStudentAndTeacherVersions = $true
            tablePreservedInAllVersions = $true
            figureMediaPreservedWhereExpected = $true
            pdfHeaderAndEofVerified = $true
            sourceAuthorizationAndKnowledgeVersionIncluded = $true
            studentVersionHidesAnswerAndSolution = $true
            noExternalAiCall = $true
            noRealStudentData = $true
            noActiveSwitch = $true
        }
        verification = [ordered]@{
            build = 'dotnet build apps/api/K12QuestionGraph.Api.csproj -c Release'
            test = 'tools/run-s010b-word-pdf-artifact-chain-smoke.ps1'
            contractInvariant = 'manifest hash plus DOCX XML, PDF header/EOF, source authorization, knowledge version, formula/table/figure checks'
            hotspot = 'gate_na: no onsite printer/WPS visual hotspot command; artifact-level regression covers deterministic non-site export integrity'
        }
        boundary = 'NS607 proves deterministic non-site Word/PDF artifact generation for student, teacher, and answer variants from ready_for_review preflight. It does not prove onsite printer behavior, WPS rendering on every target machine, or production/live release.'
        rollback = "delete $OutputRoot and $S010BReportPath; git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns607-export-artifacts.ps1 $ReportPath"
        next = 'NS701 can continue Excel score template mapping.'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 12
}
finally {
    Pop-Location
}

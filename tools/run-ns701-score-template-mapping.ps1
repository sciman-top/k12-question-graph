param(
    [string] $ReportPath = 'docs/evidence/20260530-ns701-score-template-mapping-report.json',
    [string] $F002ReportPath = 'docs/evidence/20260530-ns701-f002-source-report.json',
    [string] $F002OutputRoot = 'tmp\ns701-score-import',
    [string] $S011AReportPath = 'docs/evidence/20260530-ns701-s011a-source-report.json',
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

function Read-Text([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing file: $Path"
    return Get-Content -LiteralPath $fullPath -Raw
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

Push-Location $repoRoot
try {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'DatabasePassword or PGPASSWORD is required for NS701 score template mapping verification.'

    $ns607 = Read-Json 'docs/evidence/20260530-ns607-export-artifacts-report.json'
    Assert-Condition ($ns607.status -eq 'pass') 'NS701 dependency NS607 report did not pass'
    $ns203 = Read-Json 'docs/evidence/20260529-ns203-privacy-license-scan-report.json'
    Assert-Condition ($ns203.status -eq 'pass') 'NS701 dependency NS203 privacy/license scan did not pass'

    $apiBuildOutput = & dotnet build apps/api/K12QuestionGraph.Api.csproj -c Release 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "NS701 API build failed: $apiBuildOutput"

    Invoke-CheckedScript {
        .\tools\run-f002-score-import-contract.ps1 `
            -DatabaseName $DatabaseName `
            -DatabaseUser $DatabaseUser `
            -DatabaseHost $DatabaseHost `
            -DatabasePort $DatabasePort `
            -DatabasePassword $DatabasePassword `
            -PgBin $PgBin `
            -OutputRoot $F002OutputRoot `
            -Report $F002ReportPath
    } 'F002 score import template contract' | Write-Host

    $s011aPort = Get-FreeTcpPort
    Invoke-CheckedScript {
        .\tools\run-s011a-score-import-api-smoke.ps1 `
            -DatabaseName $DatabaseName `
            -DatabaseUser $DatabaseUser `
            -DatabaseHost $DatabaseHost `
            -DatabasePort $DatabasePort `
            -DatabasePassword $DatabasePassword `
            -PgBin $PgBin `
            -ApiPort $s011aPort `
            -ReportPath $S011AReportPath
    } 'S011A score import API smoke' | Write-Host

    $f002 = Read-Json $F002ReportPath
    Assert-Condition ($f002.status -eq 'pass') 'F002 source report did not pass'
    Assert-Condition ([string]$f002.mode -eq 'draft_test') 'NS701 F002 must stay draft_test'
    Assert-Condition (-not [bool]$f002.productionEligible) 'NS701 F002 must not be production eligible'
    Assert-Condition (-not [bool]$f002.realStudentDataUsed) 'NS701 F002 must not use real student data'
    Assert-Condition ([bool]$f002.fieldMappingDynamicAsset) 'NS701 requires field mapping to be treated as dynamic asset'
    Assert-Condition ([bool]$f002.templateReusable) 'NS701 requires reusable template evidence'
    Assert-Condition (Test-Path -LiteralPath (Join-Path $repoRoot ([string]$f002.workbookPath))) 'NS701 workbook fixture missing'
    Assert-Condition (Test-Path -LiteralPath (Join-Path $repoRoot ([string]$f002.mappingPath))) 'NS701 mapping fixture missing'
    Assert-Condition ([int]$f002.errorCount -eq 1) 'NS701 F002 must centralize an abnormal row'

    $s011a = Read-Json $S011AReportPath
    Assert-Condition ($s011a.status -eq 'pass') 'S011A source report did not pass'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$s011a.templateId)) 'NS701 S011A template id missing'
    Assert-Condition ([int]$s011a.importedCount -eq 2) 'NS701 S011A imported count mismatch'
    Assert-Condition ([int]$s011a.errorCount -eq 1) 'NS701 S011A abnormal row count mismatch'
    Assert-Condition (@($s011a.errorCodes) -contains 'item_score_out_of_range') 'NS701 expected out-of-range row error missing'
    Assert-Condition ([int]$s011a.dbCounts.piiRecords -eq 0) 'NS701 S011A must not write PII records'
    Assert-Condition ([int]$s011a.blockedPiiStatusCode -eq 400) 'NS701 S011A must block PII request'
    foreach ($audit in @(
        'used_deterministic_excel_field_mapping',
        'blocked_pii',
        'centralized_abnormal_rows',
        'wrote_draft_test_score_records',
        'no_ai_runtime_dependency'
    )) {
        Assert-Condition (@($s011a.auditTrail) -contains $audit) "NS701 S011A audit trail missing: $audit"
    }

    $program = (Read-Text 'apps/api/Program.cs') + "`n" + (Read-Text 'apps/api/Application/Workflows/ScoreAnalysisWorkflowService.cs')
    foreach ($marker in @(
        '/score-imports',
        'ScoreImportServiceRequest',
        'FieldMapping',
        'student_key_mapping_required',
        'total_score_mapping_required',
        'item_score_mapping_required',
        'pii_not_allowed'
    )) {
        Assert-Condition ($program.Contains($marker)) "NS701 API marker missing: $marker"
    }

    $app = (Read-Text 'apps/web/src/App.tsx') + "`n" + (Read-Text 'apps/web/src/api/client.ts')
    foreach ($marker in @(
        'data-flow="score-import-workbench"',
        '字段映射预览',
        '异常行',
        'createScoreImport',
        '/score-imports'
    )) {
        Assert-Condition ($app.Contains($marker)) "NS701 UI/client marker missing: $marker"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS701'
        checkedAt = (Get-Date).ToString('s')
        mode = 'score_template_mapping'
        productionEligible = $false
        externalAiCalls = 0
        realStudentDataUsed = $false
        activeAssetMutation = $false
        dependency = [ordered]@{
            ns607 = 'docs/evidence/20260530-ns607-export-artifacts-report.json'
            ns203 = 'docs/evidence/20260529-ns203-privacy-license-scan-report.json'
            f002 = $F002ReportPath
            s011a = $S011AReportPath
        }
        template = [ordered]@{
            workbookPath = [string]$f002.workbookPath
            mappingPath = [string]$f002.mappingPath
            fieldMappingDynamicAsset = [bool]$f002.fieldMappingDynamicAsset
            templateReusable = [bool]$f002.templateReusable
            apiTemplateId = [string]$s011a.templateId
        }
        import = [ordered]@{
            endpoint = '/score-imports'
            rowCount = [int]$s011a.rowCount
            importedCount = [int]$s011a.importedCount
            errorCount = [int]$s011a.errorCount
            errorCodes = @($s011a.errorCodes)
            dbCounts = $s011a.dbCounts
            auditTrail = @($s011a.auditTrail)
            teacherMessage = [string]$s011a.teacherMessage
        }
        acceptance = [ordered]@{
            excelWorkbookFixtureGenerated = $true
            fieldMappingPreviewVisibleInUi = $true
            fieldMappingSavedAsReusableTemplate = $true
            abnormalRowsCentralized = $true
            piiBlockedBeforeDatabaseWrite = $true
            draftTestScoreRecordsWritten = $true
            noExternalAiCall = $true
            noRealStudentData = $true
            noActiveSwitch = $true
        }
        verification = [ordered]@{
            build = 'dotnet build apps/api/K12QuestionGraph.Api.csproj -c Release'
            test = 'tools/run-f002-score-import-contract.ps1 + tools/run-s011a-score-import-api-smoke.ps1'
            contractInvariant = 'API/UI/client markers for /score-imports, field mapping preview, reusable template id, abnormal row centralization, and PII fail-closed'
            hotspot = 'gate_na: no real school Excel or onsite privacy workflow; deterministic synthetic workbook/API contract covers non-site score-template mapping'
        }
        boundary = 'NS701 proves synthetic Excel template mapping, reusable template persistence, centralized abnormal rows, and PII fail-closed behavior before score analysis. It does not process real student records or switch formal analytics history.'
        rollback = "delete $F002OutputRoot, $F002ReportPath, and $S011AReportPath if needed; git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns701-score-template-mapping.ps1 $ReportPath"
        next = 'NS702 can continue item score mapping UI/API.'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 12
}
finally {
    Pop-Location
}

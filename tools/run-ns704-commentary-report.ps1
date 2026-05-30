param(
    [string] $ReportPath = 'docs/evidence/20260530-ns704-commentary-report.json',
    [string] $S011CReportPath = 'docs/evidence/20260530-ns704-s011c-source-report.json',
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
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'DatabasePassword or PGPASSWORD is required for NS704 commentary report verification.'

    $ns703 = Read-Json 'docs/evidence/20260530-ns703-analysis-metrics-report.json'
    Assert-Condition ($ns703.status -eq 'pass') 'NS704 dependency NS703 report did not pass'
    Assert-Condition ([bool]$ns703.acceptance.knowledgeMasteryExplainable) 'NS704 requires NS703 explainable analysis metrics'
    Assert-Condition (-not [bool]$ns703.writesProductionHistory) 'NS704 must inherit no production history write boundary'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$ns703.metrics.activeKnowledgeVersion)) 'NS704 requires active knowledge version evidence'

    $ns701 = Read-Json 'docs/evidence/20260530-ns701-score-template-mapping-report.json'
    Assert-Condition ($ns701.status -eq 'pass') 'NS704 dependency NS701 report did not pass'
    Assert-Condition ([bool]$ns701.acceptance.abnormalRowsCentralized) 'NS704 requires centralized abnormal-row evidence'
    Assert-Condition (@($ns701.import.errorCodes).Count -ge 1) 'NS704 requires abnormal score row code evidence'

    $ns702 = Read-Json 'docs/evidence/20260530-ns702-item-score-mapping-report.json'
    Assert-Condition ($ns702.status -eq 'pass') 'NS704 dependency NS702 report did not pass'
    Assert-Condition ([bool]$ns702.acceptance.unclearMappingCentralized) 'NS704 requires centralized unclear-mapping evidence'
    Assert-Condition (@($ns702.mapping.issueCodes) -contains 'question_mapping_missing') 'NS704 requires unclear mapping issue code evidence'

    $apiBuildOutput = & dotnet build apps/api/K12QuestionGraph.Api.csproj -c Release 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "NS704 API build failed: $apiBuildOutput"

    $s011cPort = Get-FreeTcpPort
    Invoke-CheckedScript {
        .\tools\run-s011c-commentary-report-export-smoke.ps1 `
            -DatabaseName $DatabaseName `
            -DatabaseUser $DatabaseUser `
            -DatabaseHost $DatabaseHost `
            -DatabasePort $DatabasePort `
            -DatabasePassword $DatabasePassword `
            -PgBin $PgBin `
            -ApiPort $s011cPort `
            -ReportPath $S011CReportPath
    } 'S011C commentary report export smoke' | Write-Host
    $s011c = Read-Json $S011CReportPath
    Assert-Condition ($s011c.status -eq 'pass') 'S011C source report did not pass'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$s011c.artifactPath)) 'NS704 commentary artifact path missing'
    Assert-Condition ([string]$s011c.artifactPath -like 'draft://commentary-reports/*') 'NS704 report artifact must stay draft'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$s011c.manifestSha256)) 'NS704 manifest hash missing'
    Assert-Condition ([int]$s011c.sectionCount -ge 3) 'NS704 report section count missing'
    Assert-Condition ([int]$s011c.weakKnowledgePointCount -ge 1) 'NS704 weak knowledge points missing'
    Assert-Condition ([int]$s011c.practiceSuggestionCount -ge 1) 'NS704 practice suggestions missing'
    Assert-Condition ([string]$s011c.reportMarkdownPreview -match '分层练习建议') 'NS704 report markdown must include layered practice suggestions'
    Assert-Condition (@($s011c.weakKnowledgePoints | Where-Object { [int]$_.version -ge 1 }).Count -ge 1) 'NS704 weak knowledge points must explain knowledge version'
    foreach ($audit in @(
        'deterministic_score_metrics',
        'draft_commentary_report_export',
        'no_real_student_data',
        'no_production_history_write',
        'no_ai_runtime_dependency'
    )) {
        Assert-Condition (@($s011c.auditTrail) -contains $audit) "NS704 S011C audit trail missing: $audit"
    }

    $n004 = (Invoke-CheckedScript {
        .\tools\run-n004-class-commentary-report-mvp.ps1 -F003ReportPath 'docs/evidence/20260530-ns703-f003-source-report.json'
    } 'N004 class commentary report MVP') | ConvertFrom-Json
    Assert-Condition ($n004.status -eq 'pass') 'N004 commentary MVP contract did not pass'

    $n005 = (Invoke-CheckedScript {
        .\tools\run-n005-tiered-practice-draft-test.ps1 -F003ReportPath 'docs/evidence/20260530-ns703-f003-source-report.json'
    } 'N005 tiered practice draft/test') | ConvertFrom-Json
    Assert-Condition ($n005.status -eq 'pass') 'N005 tiered practice contract did not pass'

    $surface = (Read-Text 'apps/api/Program.cs') + "`n" + (Read-Text 'apps/api/Application/Workflows/ScoreAnalysisWorkflowService.cs')
    foreach ($marker in @(
        '/assessments/{assessmentId:guid}/commentary-report/export',
        'CommentaryReportExportResponse',
        'deterministic_score_metrics',
        'draft_commentary_report_export',
        'WritesProductionHistory',
        'blocked_unclear_item_score_mapping',
        'BlockingIssues'
    )) {
        Assert-Condition ($surface.Contains($marker)) "NS704 API/service marker missing: $marker"
    }

    $ui = (Read-Text 'apps/web/src/App.tsx') + "`n" + (Read-Text 'apps/web/src/api/client.ts') + "`n" + (Read-Text 'apps/web/src/api/contracts.ts')
    foreach ($marker in @(
        'data-contract="s011c-commentary-report-export"',
        'export-score-report',
        'exportCommentaryReport',
        '讲评报告',
        '报告导出路径'
    )) {
        Assert-Condition ($ui.Contains($marker)) "NS704 UI/client marker missing: $marker"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS704'
        checkedAt = (Get-Date).ToString('s')
        mode = 'commentary_report_and_tiered_suggestions'
        productionEligible = $false
        externalAiCalls = 0
        realStudentDataUsed = $false
        writesProductionHistory = $false
        activeAssetMutation = $false
        dependency = [ordered]@{
            ns703 = 'docs/evidence/20260530-ns703-analysis-metrics-report.json'
            ns701 = 'docs/evidence/20260530-ns701-score-template-mapping-report.json'
            ns702 = 'docs/evidence/20260530-ns702-item-score-mapping-report.json'
            s011c = $S011CReportPath
            n004 = [string]$n004.n004EvidencePath
            n005 = [string]$n005.n005EvidencePath
        }
        report = [ordered]@{
            endpoint = [string]$s011c.endpoint
            assessmentId = [string]$s011c.assessmentId
            artifactPath = [string]$s011c.artifactPath
            manifestSha256 = [string]$s011c.manifestSha256
            sectionCount = [int]$s011c.sectionCount
            weakKnowledgePointCount = [int]$s011c.weakKnowledgePointCount
            practiceSuggestionCount = [int]$s011c.practiceSuggestionCount
            activeKnowledgeVersion = [string]$ns703.metrics.activeKnowledgeVersion
            abnormalRowCodes = @($ns701.import.errorCodes)
            unclearMappingCodes = @($ns702.mapping.issueCodes)
            auditTrail = @($s011c.auditTrail)
            teacherMessage = [string]$s011c.teacherMessage
        }
        acceptance = [ordered]@{
            commentaryReportExported = $true
            dataSourceTraceable = $true
            activeKnowledgeVersionReferenced = $true
            abnormalOrUnclearItemsBlockedBeforeReport = $true
            weakKnowledgePointsIncluded = $true
            tieredPracticeSuggestionsDrafted = $true
            unexplainedAdvancedMetricsExcluded = $true
            noExternalAiCall = $true
            noRealStudentData = $true
            noProductionHistoryWrite = $true
            noActiveSwitch = $true
        }
        verification = [ordered]@{
            build = 'dotnet build apps/api/K12QuestionGraph.Api.csproj -c Release'
            test = 'tools/run-s011c-commentary-report-export-smoke.ps1'
            contractInvariant = 'N004/N005 commentary and tiered practice contracts plus S011C report export manifest/audit trail'
            hotspot = 'gate_na: no real class interpretation session or formal historical analytics; deterministic draft report export covers non-site report generation'
        }
        boundary = 'NS704 proves commentary report draft export and layered practice suggestions from deterministic score metrics after item-score mapping. It does not process real student data, enable AI-written production commentary, or write formal historical analytics.'
        rollback = "delete synthetic S011C rows recorded in $S011CReportPath if needed; git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns704-commentary-report.ps1 $ReportPath $S011CReportPath"
        next = 'NS705 can continue real-student-data privacy admission audit.'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}

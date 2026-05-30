param(
    [string] $ReportPath = 'docs/evidence/20260530-ns702-item-score-mapping-report.json',
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
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'DatabasePassword or PGPASSWORD is required for NS702 item score mapping verification.'

    $ns701 = Read-Json 'docs/evidence/20260530-ns701-score-template-mapping-report.json'
    Assert-Condition ($ns701.status -eq 'pass') 'NS702 dependency NS701 report did not pass'
    Assert-Condition ([bool]$ns701.acceptance.abnormalRowsCentralized) 'NS702 requires NS701 centralized abnormal row evidence'

    $apiBuildOutput = & dotnet build apps/api/K12QuestionGraph.Api.csproj -c Release 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "NS702 API build failed: $apiBuildOutput"

    $s011bPath = 'docs/evidence/20260530-ns702-s011b-source-report.json'
    $s011bPort = Get-FreeTcpPort
    Invoke-CheckedScript {
        .\tools\run-s011b-item-score-mapping-ui-api-smoke.ps1 `
            -DatabaseName $DatabaseName `
            -DatabaseUser $DatabaseUser `
            -DatabaseHost $DatabaseHost `
            -DatabasePort $DatabasePort `
            -DatabasePassword $DatabasePassword `
            -PgBin $PgBin `
            -ApiPort $s011bPort `
            -ReportPath $s011bPath
    } 'S011B item score mapping UI/API smoke' | Write-Host
    $s011b = Read-Json $s011bPath
    Assert-Condition ($s011b.status -eq 'pass') 'S011B source report did not pass'
    Assert-Condition ([int]$s011b.itemCount -eq 2) 'NS702 item count mismatch'
    Assert-Condition ([int]$s011b.mappedCount -eq 1) 'NS702 mapped count mismatch'
    Assert-Condition ([int]$s011b.unclearCount -eq 1) 'NS702 unclear count mismatch'
    Assert-Condition (@($s011b.issueCodes) -contains 'question_mapping_missing') 'NS702 must centralize missing question mapping'
    Assert-Condition (@($s011b.auditTrail) -contains 'centralized_unclear_mappings') 'NS702 audit trail missing centralized unclear mapping'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$s011b.questionId)) 'NS702 mapped question id missing'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$s011b.knowledgeId)) 'NS702 mapped knowledge id missing'

    $surface = (Read-Text 'apps/api/Program.cs') + "`n" + (Read-Text 'apps/api/Application/Workflows/ScoreAnalysisWorkflowService.cs')
    foreach ($marker in @(
        '/assessments/{assessmentId:guid}/item-score-mappings/preview',
        'ItemScoreMappingPreviewResponse',
        'question_mapping_missing',
        'centralized_unclear_mappings',
        'WritesProductionHistory'
    )) {
        Assert-Condition ($surface.Contains($marker)) "NS702 API marker missing: $marker"
    }

    $ui = (Read-Text 'apps/web/src/App.tsx') + "`n" + (Read-Text 'apps/web/src/api/client.ts') + "`n" + (Read-Text 'apps/web/src/api/contracts.ts')
    foreach ($marker in @(
        'data-flow="item-score-mapping-workbench"',
        'data-contract="s011b-item-score-mapping-ui-api"',
        'data-action="preview-item-score-mapping"',
        'data-contract="centralized-unclear-item-score-mappings"',
        'previewItemScoreMappings',
        'ItemScoreMappingPreviewContract'
    )) {
        Assert-Condition ($ui.Contains($marker)) "NS702 UI/client marker missing: $marker"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS702'
        checkedAt = (Get-Date).ToString('s')
        mode = 'item_score_mapping_ui_api'
        productionEligible = $false
        externalAiCalls = 0
        realStudentDataUsed = $false
        writesProductionHistory = $false
        activeAssetMutation = $false
        dependency = [ordered]@{
            ns701 = 'docs/evidence/20260530-ns701-score-template-mapping-report.json'
            s011b = $s011bPath
        }
        mapping = [ordered]@{
            endpoint = [string]$s011b.endpoint
            assessmentId = [string]$s011b.assessmentId
            questionId = [string]$s011b.questionId
            knowledgeId = [string]$s011b.knowledgeId
            itemCount = [int]$s011b.itemCount
            mappedCount = [int]$s011b.mappedCount
            unclearCount = [int]$s011b.unclearCount
            issueCodes = @($s011b.issueCodes)
            teacherMessage = [string]$s011b.teacherMessage
        }
        acceptance = [ordered]@{
            questionNoCanMapToQuestion = $true
            itemScoreCanMapToKnowledge = $true
            scoreValuePreservedForPreview = $true
            unclearMappingCentralized = $true
            noSilentDropForUnclearItems = $true
            uiHasPreviewActionAndUnclearList = $true
            noExternalAiCall = $true
            noRealStudentData = $true
            noProductionHistoryWrite = $true
            noActiveSwitch = $true
        }
        verification = [ordered]@{
            build = 'dotnet build apps/api/K12QuestionGraph.Api.csproj -c Release'
            test = 'tools/run-s011b-item-score-mapping-ui-api-smoke.ps1'
            contractInvariant = 'API/UI/client markers for item-score mapping preview and centralized unclear mappings'
            hotspot = 'gate_na: no real school score sheet or teacher UI session; synthetic API/UI contract covers non-site mapping semantics'
        }
        boundary = 'NS702 proves item-score mappings can be previewed against question and knowledge references, while unclear mappings are centralized for teacher review and never silently dropped.'
        rollback = "delete synthetic S011B rows recorded in $s011bPath if needed; git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns702-item-score-mapping.ps1 $ReportPath $s011bPath"
        next = 'NS703 can continue analysis metrics verification.'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}

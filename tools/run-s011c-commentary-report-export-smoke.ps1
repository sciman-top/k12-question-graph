param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [int] $ApiPort = 5298,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $ReportPath = 'docs\evidence\20260508-s011c-commentary-report-export-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
if ([string]::IsNullOrWhiteSpace($DatabasePassword)) { throw 'DatabasePassword or PGPASSWORD is required for S011C smoke' }

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return $listener.LocalEndpoint.Port
    }
    finally {
        $listener.Stop()
    }
}

function Test-TcpPortAvailable([int] $Port) {
    $listener = $null
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
        $listener.Start()
        return $true
    }
    catch [System.Net.Sockets.SocketException] {
        return $false
    }
    finally {
        if ($null -ne $listener) {
            $listener.Stop()
        }
    }
}

function Invoke-ScalarSql([string] $Sql) {
    $psql = Join-Path $PgBin 'psql.exe'
    $value = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c $Sql
    if ($LASTEXITCODE -ne 0) { throw "S011C SQL failed: $Sql" }
    return (($value | Select-Object -First 1) ?? '').Trim()
}

function New-MappedQuestion([string] $Title, [decimal] $Score) {
    $knowledgeId = Invoke-ScalarSql "insert into knowledge_nodes (subject, stage, code, title, node_type, level, status, version, metadata, created_at, updated_at) values ('physics', 'junior_middle_school', 'S011C-' || replace(gen_random_uuid()::text,'-',''), '$Title', 'concept', 3, 'active', 1, '{""task"":""S011C""}'::jsonb, now(), now()) returning id;"
    $questionId = Invoke-ScalarSql "insert into question_items (subject, stage, grade, question_type, default_score, difficulty_estimated, status, primary_knowledge_id, blocks, quality_signals, created_at, updated_at) values ('physics', 'junior_middle_school', 'grade_8', 'single_choice', $Score, 0.62, 'draft', '$knowledgeId', '[{""blockType"":""text"",""content"":{""text"":""S011C commentary report fixture.""} }]'::jsonb, '{""task"":""S011C""}'::jsonb, now(), now()) returning id;"
    Invoke-ScalarSql "insert into knowledge_mappings (question_item_id, knowledge_node_id, mapping_source, is_primary, confidence, version, evidence, created_at) values ('$questionId', '$knowledgeId', 'manual', true, 0.95, 1, '{""task"":""S011C""}'::jsonb, now()) returning id;" | Out-Null
    return [ordered]@{ knowledgeId = $knowledgeId; questionId = $questionId }
}

$requestedApiPort = $ApiPort
if ($ApiPort -le 0 -or -not (Test-TcpPortAvailable -Port $ApiPort)) {
    $ApiPort = Get-FreeTcpPort
}
$apiUrl = "http://127.0.0.1:$ApiPort"
$logOut = Join-Path $repoRoot 'docs/evidence/s011c-smoke-api.out.log'
$logErr = Join-Path $repoRoot 'docs/evidence/s011c-smoke-api.err.log'
$previousConnectionString = $env:KQG_CONNECTION_STRING
$env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
$process = $null
$pushedLocation = $false

try {
    Push-Location $repoRoot
    $pushedLocation = $true
    dotnet ef database update --project apps\api\K12QuestionGraph.Api.csproj --startup-project apps\api\K12QuestionGraph.Api.csproj --configuration Release --no-build | Write-Host
    if ($LASTEXITCODE -ne 0) { throw 'dotnet ef database update failed' }

    $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\\api\\K12QuestionGraph.Api.csproj','-c','Release','--no-build','--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr
    $ready = $false
    for ($i = 0; $i -lt 120; $i++) {
        try { if ((Invoke-RestMethod -Uri "$apiUrl/health/ready" -TimeoutSec 2).status -eq 'ok') { $ready = $true; break } } catch {}
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { throw "API did not become ready on $apiUrl" }

    $validBody = @{
        assessmentKey = 's011c-commentary-report-smoke'
        assessmentTitle = 'S011C commentary report smoke'
        subject = 'physics'
        stage = 'junior_middle_school'
        grade = 'grade_8'
        templateKey = 's011c-score-template-v1'
        templateDisplayName = 'S011C score template'
        sourceFileName = 's011c-score-import-smoke.xlsx'
        containsStudentPii = $false
        productionEligible = $false
        maxTotalScore = 100
        fieldMapping = @{
            studentKey = 'student_code'
            totalScore = 'total_score'
            itemScores = @{
                Q1 = 'q1_score'
                Q2 = 'q2_score'
            }
        }
        itemMaxScores = @{
            Q1 = 40
            Q2 = 60
        }
        rows = @(
            @{ rowNumber = 2; values = @{ student_code = 'SYN-011C-001'; total_score = '88'; q1_score = '34'; q2_score = '54' } },
            @{ rowNumber = 3; values = @{ student_code = 'SYN-011C-002'; total_score = '76'; q1_score = '30'; q2_score = '46' } }
        )
    } | ConvertTo-Json -Depth 10

    $import = Invoke-RestMethod -Method Post -Uri "$apiUrl/score-imports" -ContentType 'application/json' -Body $validBody -TimeoutSec 10
    Assert-True ([string]$import.status -eq 'imported') 'S011C fixture import should succeed'
    $assessmentId = [string]$import.assessmentId
    $q1 = New-MappedQuestion -Title 'Inertia' -Score 40
    $q2 = New-MappedQuestion -Title 'Force analysis' -Score 60

    $exportBody = @{
        format = 'md'
        allowAiDraftText = $false
        mappings = @(
            @{ questionNo = 'Q1'; questionItemId = $q1.questionId },
            @{ questionNo = 'Q2'; questionItemId = $q2.questionId }
        )
    } | ConvertTo-Json -Depth 8

    $export = Invoke-RestMethod -Method Post -Uri "$apiUrl/assessments/$assessmentId/commentary-report/export" -ContentType 'application/json' -Body $exportBody -TimeoutSec 10
    Assert-True ([string]$export.status -eq 'ready') 'S011C export should be ready'
    Assert-True ([string]$export.mode -eq 'draft_test') 'S011C export must stay draft_test'
    Assert-True (-not [bool]$export.productionEligible) 'S011C export must not be production eligible'
    Assert-True (-not [bool]$export.realStudentDataUsed) 'S011C export must not use real student data'
    Assert-True (-not [bool]$export.writesProductionHistory) 'S011C export must not write production history'
    Assert-True (-not [bool]$export.allowAiDraftText) 'S011C smoke keeps AI draft text disabled'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$export.artifactPath)) 'S011C artifact path missing'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$export.manifestSha256)) 'S011C manifest sha missing'
    Assert-True (@($export.sections).Count -ge 3) 'S011C report sections missing'
    Assert-True (@($export.weakKnowledgePoints).Count -ge 1) 'S011C weak knowledge points missing'
    Assert-True (@($export.practiceSuggestions).Count -ge 1) 'S011C practice suggestions missing'
    Assert-True (@($export.auditTrail) -contains 'deterministic_score_metrics') 'S011C audit missing deterministic metrics'

    $app = Get-Content -LiteralPath (Join-Path $repoRoot 'apps\web\src\App.tsx') -Raw
    Assert-True ($app.Contains('data-contract="s011c-commentary-report-export"')) 'S011C UI missing marker: s011c-commentary-report-export'
    Assert-True (($app.Contains('data-action="export-score-report"')) -or ($app.Contains("action: 'export-score-report'"))) 'S011C UI missing marker: export-score-report'
    Assert-True ($app.Contains('exportCommentaryReport')) 'S011C UI missing exportCommentaryReport client call'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'S011C'
        checkedAt = (Get-Date).ToString('s')
        endpoint = "/assessments/{assessmentId}/commentary-report/export"
        requestedApiPort = $requestedApiPort
        resolvedApiPort = $ApiPort
        portFallbackApplied = ($requestedApiPort -ne $ApiPort)
        assessmentId = $assessmentId
        artifactPath = $export.artifactPath
        manifestSha256 = $export.manifestSha256
        sectionCount = @($export.sections).Count
        weakKnowledgePointCount = @($export.weakKnowledgePoints).Count
        practiceSuggestionCount = @($export.practiceSuggestions).Count
        sections = $export.sections
        weakKnowledgePoints = $export.weakKnowledgePoints
        practiceSuggestions = $export.practiceSuggestions
        blockingIssues = $export.blockingIssues
        reportMarkdownPreview = ([string]$export.reportMarkdown).Substring(0, [Math]::Min(500, ([string]$export.reportMarkdown).Length))
        auditTrail = $export.auditTrail
        uiMarkers = @('s011c-commentary-report-export','export-score-report')
        teacherMessage = $export.teacherMessage
        conclusion = 'commentary report export uses deterministic score metrics after item-score mapping, returns a draft/test artifact manifest, and does not write formal history'
        rollback = 'revert the S011C export endpoint/service/client/UI/gate changes and remove docs/evidence/20260508-s011c-commentary-report-export-report.json; no migration is required'
    }
    $full = Join-Path $repoRoot $ReportPath
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $full -Encoding UTF8
    $report | ConvertTo-Json -Depth 10
}
finally {
    if ($null -ne $process) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
    $env:KQG_CONNECTION_STRING = $previousConnectionString
    if ($pushedLocation) { Pop-Location }
}

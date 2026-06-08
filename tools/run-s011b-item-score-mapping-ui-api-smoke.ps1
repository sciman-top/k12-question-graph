param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [int] $ApiPort = 0,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $ReportPath = 'docs\evidence\20260508-s011b-item-score-mapping-ui-api-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
if ([string]::IsNullOrWhiteSpace($DatabasePassword)) { throw 'DatabasePassword or PGPASSWORD is required for S011B smoke' }

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
    if ($LASTEXITCODE -ne 0) { throw "S011B SQL failed: $Sql" }
    return (($value | Select-Object -First 1) ?? '').Trim()
}

$requestedApiPort = $ApiPort
if ($ApiPort -le 0 -or -not (Test-TcpPortAvailable -Port $ApiPort)) {
    $ApiPort = Get-FreeTcpPort
}
$apiUrl = "http://127.0.0.1:$ApiPort"
$logOut = Join-Path $repoRoot 'docs/evidence/s011b-smoke-api.out.log'
$logErr = Join-Path $repoRoot 'docs/evidence/s011b-smoke-api.err.log'
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
        assessmentKey = 's011b-item-score-mapping-smoke'
        assessmentTitle = 'S011B 小题映射 smoke'
        subject = 'physics'
        stage = 'junior_middle_school'
        grade = 'grade_8'
        templateKey = 's011b-score-template-v1'
        templateDisplayName = 'S011B 成绩导入模板'
        sourceFileName = 's011b-score-import-smoke.xlsx'
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
            @{ rowNumber = 2; values = @{ student_code = 'SYN-011B-001'; total_score = '88'; q1_score = '34'; q2_score = '54' } },
            @{ rowNumber = 3; values = @{ student_code = 'SYN-011B-002'; total_score = '76'; q1_score = '30'; q2_score = '46' } }
        )
    } | ConvertTo-Json -Depth 10

    $import = Invoke-RestMethod -Method Post -Uri "$apiUrl/score-imports" -ContentType 'application/json' -Body $validBody -TimeoutSec 10
    Assert-True ([string]$import.status -eq 'imported') 'S011B fixture import should succeed'
    $assessmentId = [string]$import.assessmentId

    $knowledgeId = Invoke-ScalarSql @"
insert into knowledge_nodes (subject, stage, code, title, node_type, level, status, version, metadata, created_at, updated_at)
values ('physics', 'junior_middle_school', 'S011B-KNOWLEDGE-' || replace(gen_random_uuid()::text,'-',''), 'Newton first law and inertia', 'concept', 3, 'active', 1, '{"task":"S011B"}'::jsonb, now(), now())
returning id;
"@
    $questionId = Invoke-ScalarSql @"
insert into question_items (subject, stage, grade, question_type, default_score, difficulty_estimated, status, primary_knowledge_id, blocks, quality_signals, created_at, updated_at)
values ('physics', 'junior_middle_school', 'grade_8', 'single_choice', 40, 0.62, 'draft', '$knowledgeId', '[{"blockType":"text","content":{"text":"Inertia question fixture for S011B."}}]'::jsonb, '{"task":"S011B"}'::jsonb, now(), now())
returning id;
"@
    Invoke-ScalarSql "insert into knowledge_mappings (question_item_id, knowledge_node_id, mapping_source, is_primary, confidence, version, evidence, created_at) values ('$questionId', '$knowledgeId', 'manual', true, 0.95, 1, '{""task"":""S011B""}'::jsonb, now()) returning id;" | Out-Null

    $previewBody = @{
        mappings = @(
            @{ questionNo = 'Q1'; questionItemId = $questionId },
            @{ questionNo = 'Q2'; questionItemId = $null }
        )
    } | ConvertTo-Json -Depth 8
    $preview = Invoke-RestMethod -Method Post -Uri "$apiUrl/assessments/$assessmentId/item-score-mappings/preview" -ContentType 'application/json' -Body $previewBody -TimeoutSec 10

    Assert-True ([string]$preview.mode -eq 'draft_test') 'S011B preview must stay draft_test'
    Assert-True (-not [bool]$preview.productionEligible) 'S011B preview must not be production eligible'
    Assert-True (-not [bool]$preview.realStudentDataUsed) 'S011B preview must not use real student data'
    Assert-True (-not [bool]$preview.writesProductionHistory) 'S011B preview must not write production history'
    Assert-True ([int]$preview.itemCount -eq 2) 'S011B item count mismatch'
    Assert-True ([int]$preview.mappedCount -eq 1) 'S011B mapped count mismatch'
    Assert-True ([int]$preview.unclearCount -eq 1) 'S011B unclear count mismatch'
    $mapped = @($preview.rows | Where-Object { $_.questionNo -eq 'Q1' }) | Select-Object -First 1
    Assert-True ($null -ne $mapped.primaryKnowledge) 'S011B mapped row should include primary knowledge'
    $unclear = @($preview.rows | Where-Object { $_.questionNo -eq 'Q2' }) | Select-Object -First 1
    Assert-True (@($unclear.issueCodes) -contains 'question_mapping_missing') 'S011B unclear row should centralize missing mapping'
    Assert-True (@($preview.auditTrail) -contains 'centralized_unclear_mappings') 'S011B audit trail missing centralized unclear mappings'

    $app = Get-Content -LiteralPath (Join-Path $repoRoot 'apps\web\src\App.tsx') -Raw
    foreach ($pattern in @(
        'data-flow="item-score-mapping-workbench"',
        'data-contract="s011b-item-score-mapping-ui-api"',
        'data-action="preview-item-score-mapping"',
        'data-contract="centralized-unclear-item-score-mappings"'
    )) {
        Assert-True ($app.Contains($pattern)) "S011B UI missing marker: $pattern"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'S011B'
        checkedAt = (Get-Date).ToString('s')
        endpoint = "/assessments/{assessmentId}/item-score-mappings/preview"
        requestedApiPort = $requestedApiPort
        resolvedApiPort = $ApiPort
        portFallbackApplied = ($requestedApiPort -ne $ApiPort)
        assessmentId = $assessmentId
        questionId = $questionId
        knowledgeId = $knowledgeId
        itemCount = $preview.itemCount
        mappedCount = $preview.mappedCount
        unclearCount = $preview.unclearCount
        issueCodes = @($preview.issues | ForEach-Object { $_.codes } | ForEach-Object { $_ })
        auditTrail = $preview.auditTrail
        uiMarkers = @('item-score-mapping-workbench','s011b-item-score-mapping-ui-api','centralized-unclear-item-score-mappings')
        teacherMessage = $preview.teacherMessage
        conclusion = 'item scores can be preview-mapped to questions and active knowledge nodes, while unclear mappings are centralized for teacher review before analysis/export'
        rollback = 'revert the S011B preview endpoint/service/client/UI/gate changes and remove docs/evidence/20260508-s011b-item-score-mapping-ui-api-report.json; no migration is required'
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

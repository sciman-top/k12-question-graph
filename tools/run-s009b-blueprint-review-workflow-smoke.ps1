param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [int] $ApiPort = 0,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $ReportPath = 'docs/evidence/20260507-s009b-blueprint-review-workflow-smoke-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
if ([string]::IsNullOrWhiteSpace($DatabasePassword)) { throw 'DatabasePassword or PGPASSWORD is required for S009B smoke' }

$requestedApiPort = $ApiPort
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

if ($ApiPort -le 0) {
    $ApiPort = Get-FreeTcpPort
}
$apiUrl = "http://127.0.0.1:$ApiPort"
$logOut = Join-Path $repoRoot 'docs/evidence/s009b-smoke-api.out.log'
$logErr = Join-Path $repoRoot 'docs/evidence/s009b-smoke-api.err.log'
$previousConnectionString = $env:KQG_CONNECTION_STRING
$env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
$process = $null

try {
    dotnet ef database update --project apps\api\K12QuestionGraph.Api.csproj --startup-project apps\api\K12QuestionGraph.Api.csproj --configuration Release --no-build | Write-Host
    if ($LASTEXITCODE -ne 0) { throw 'dotnet ef database update failed' }

    $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\\api\\K12QuestionGraph.Api.csproj','-c','Release','--no-build','--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr
    $ready = $false
    for ($i = 0; $i -lt 120; $i++) {
        try { if ((Invoke-RestMethod -Uri "$apiUrl/health/ready" -TimeoutSec 2).status -eq 'ok') { $ready = $true; break } } catch {}
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { throw "API did not become ready on $apiUrl" }

    $psql = Join-Path $PgBin 'psql.exe'
    $knowledgeId = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c "select id from knowledge_nodes where status='active' and version=1 order by created_at asc limit 1;"
    if ($LASTEXITCODE -ne 0) { throw 'S009B active knowledge query failed' }
    $knowledgeId = (($knowledgeId | Select-Object -First 1) ?? '').Trim()
    if ([string]::IsNullOrWhiteSpace($knowledgeId)) {
        $knowledgeId = [Guid]::NewGuid().ToString()
        $code = "S009B-ACTIVE-" + [Guid]::NewGuid().ToString('N').Substring(0, 8).ToUpperInvariant()
        & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c "insert into knowledge_nodes (id,subject,stage,code,title,node_type,level,status,version,metadata,created_at,updated_at) values ('$knowledgeId','physics','junior_middle_school','$code','S009B Active Seed','concept',2,'active',1,'{}',now(),now());"
        if ($LASTEXITCODE -ne 0) { throw 'S009B active knowledge seed failed' }
    }

    for ($i = 1; $i -le 8; $i++) {
        $questionType = if ($i -le 5) { 'single_choice' } elseif ($i -le 7) { 'calculation' } else { 'experiment' }
        $score = if ($questionType -eq 'single_choice') { 3 } elseif ($questionType -eq 'calculation') { 5 } else { 5 }
        $questionBody = @{
            subject = 'physics'
            stage = 'junior_middle_school'
            grade = 'grade_8'
            questionType = $questionType
            defaultScore = $score
            difficultyEstimated = 0.58
            status = 'draft'
            primaryKnowledgeId = $knowledgeId
            blocks = @(
                @{ blockType = 'text'; sortOrder = 0; content = @{ text = "S009B 细目表确认后取题 $i" }; sourceRegionId = $null }
            )
            assets = @()
            answer = @{ value = 'A' }
            solution = @{ text = 'S009B smoke' }
        } | ConvertTo-Json -Depth 8
        Invoke-RestMethod -Method Post -Uri "$apiUrl/questions" -ContentType 'application/json' -Body $questionBody -TimeoutSec 10 | Out-Null
    }

    $blueprintBody = @{
        teacherRequest = '八年级力学复习，先给我可确认的细目表，不要直接出整卷'
        textbookVersion = '人教版八年级'
    } | ConvertTo-Json -Depth 6
    $blueprint = Invoke-RestMethod -Method Post -Uri "$apiUrl/paper-blueprints" -ContentType 'application/json' -Body $blueprintBody -TimeoutSec 10

    if ([string]$blueprint.status -ne 'pending_review') { throw 'S009B blueprint must start pending_review' }
    if (-not $blueprint.mustConfirmBeforeTakingQuestions) { throw 'S009B blueprint must require teacher confirmation before taking questions' }
    if ($blueprint.opaqueGenerationAllowed) { throw 'S009B opaque generation must stay blocked' }
    if ($null -ne $blueprint.confirmedPaperBasketId) { throw 'S009B blueprint must not create a basket before confirmation' }
    if ($blueprint.blueprint.Count -lt 3) { throw 'S009B blueprint rows missing' }

    $confirmBody = @{ teacherConfirmedBy = 'proxy-teacher-s009b' } | ConvertTo-Json -Depth 3
    $confirmed = Invoke-RestMethod -Method Post -Uri "$apiUrl/paper-blueprints/$($blueprint.id)/confirm" -ContentType 'application/json' -Body $confirmBody -TimeoutSec 10
    if (-not $confirmed.confirmed) { throw 'S009B blueprint confirm did not succeed' }
    if ([string]$confirmed.status -ne 'confirmed') { throw 'S009B blueprint status was not confirmed' }
    if ([string]::IsNullOrWhiteSpace([string]$confirmed.paperBasketId)) { throw 'S009B confirm did not return paperBasketId' }
    if ([int]$confirmed.selectedQuestionCount -lt 8) { throw 'S009B confirm selected too few questions' }

    $loadedBasket = Invoke-RestMethod -Uri "$apiUrl/paper-baskets/$($confirmed.paperBasketId)" -TimeoutSec 10
    if ($loadedBasket.items.Count -lt 8) { throw 'S009B confirmed basket item count mismatch' }
    if (-not $loadedBasket.structure.confirmRequiredBeforeQuestionSelection) { throw 'S009B basket structure lost confirm-required guard' }
    if ($loadedBasket.structure.opaqueGenerationAllowed) { throw 'S009B basket structure allowed opaque generation' }

    $dbStatus = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c "select status from paper_blueprint_reviews where id='$($blueprint.id)';"
    if ($LASTEXITCODE -ne 0) { throw 'S009B blueprint review DB status query failed' }
    $dbStatus = (($dbStatus | Select-Object -First 1) ?? '').Trim()
    if ($dbStatus -ne 'confirmed') { throw "S009B DB status mismatch: $dbStatus" }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'S009B'
        checkedAt = (Get-Date).ToString('s')
        requestedApiPort = $requestedApiPort
        resolvedApiPort = $ApiPort
        portFallbackApplied = ($requestedApiPort -ne $ApiPort)
        blueprintReviewId = $blueprint.id
        initialStatus = 'pending_review'
        finalStatus = $dbStatus
        paperBasketId = $confirmed.paperBasketId
        selectedQuestionCount = $confirmed.selectedQuestionCount
        reviewRequiredBeforeQuestionSelection = $true
        opaqueGenerationAllowed = $false
        allowRealModelCalls = $blueprint.allowRealModelCalls
        productionEligible = $blueprint.productionEligible
        conclusion = 'natural-language paper request creates a reviewable blueprint first; only explicit teacher confirmation creates a draft paper basket and selects questions'
        rollback = 'delete the created paper_blueprint_reviews row and related draft paper_baskets/paper_basket_items, or revert the S009B migration before release'
    }
    $full = Join-Path $repoRoot $ReportPath
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $full -Encoding UTF8
    $report | ConvertTo-Json -Depth 10
}
finally {
    if ($null -ne $process) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
    $env:KQG_CONNECTION_STRING = $previousConnectionString
}

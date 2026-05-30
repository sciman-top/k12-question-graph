param(
    [string] $ReportPath = 'docs/evidence/20260530-ns505-feedback-eval-loop-report.json',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [int] $ApiPort = 0
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for NS505 feedback eval loop'
}

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
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return [int]$listener.LocalEndpoint.Port
    }
    finally {
        $listener.Stop()
    }
}

function Invoke-ScalarSql([string] $Sql) {
    $psql = Join-Path $PgBin 'psql.exe'
    $value = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c $Sql
    if ($LASTEXITCODE -ne 0) {
        throw "NS505 SQL failed: $Sql"
    }
    return (($value | Select-Object -First 1) ?? '').Trim()
}

$previousConnectionString = $env:KQG_CONNECTION_STRING
$env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
$process = $null

Push-Location $repoRoot
try {
    $ns504 = Read-Json 'docs/evidence/20260530-ns504-ai-suggestion-review-report.json'
    Assert-Condition ($ns504.status -eq 'pass') 'NS505 dependency NS504 report did not pass'
    Assert-Condition ([bool]$ns504.acceptance.teacherFeedbackResolvesQueue) 'NS505 requires NS504 teacher feedback review boundary'
    Assert-Condition ([bool]$ns504.acceptance.realModelCallsStillDisabled) 'NS505 requires NS504 real model disabled boundary'

    $buildOutput = & dotnet build apps/api/K12QuestionGraph.Api.csproj -c Release 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "NS505 backend build failed: $buildOutput"

    $efOutput = & dotnet ef database update --project apps/api/K12QuestionGraph.Api.csproj --startup-project apps/api/K12QuestionGraph.Api.csproj --configuration Release --no-build 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "NS505 database migration failed: $efOutput"

    $migrationApplied = Invoke-ScalarSql 'select count(*) from "__EFMigrationsHistory" where migration_id like ''%AddFeedbackEventsForNS505'';'
    Assert-Condition ([int]$migrationApplied -eq 1) 'NS505 migration history missing AddFeedbackEventsForNS505'

    if ($ApiPort -le 0) {
        $ApiPort = Get-FreeTcpPort
    }
    $apiUrl = "http://127.0.0.1:$ApiPort"
    $logOut = Join-Path $repoRoot 'docs/evidence/ns505-feedback-api.out.log'
    $logErr = Join-Path $repoRoot 'docs/evidence/ns505-feedback-api.err.log'
    $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\api\K12QuestionGraph.Api.csproj','-c','Release','--no-build','--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr

    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
        if ($process.HasExited) {
            throw "NS505 API exited before ready; see $logErr"
        }
        try {
            $health = Invoke-RestMethod -Uri "$apiUrl/health/ready" -TimeoutSec 2
            if ($health.status -eq 'ok') {
                $ready = $true
                break
            }
        }
        catch {
            Start-Sleep -Milliseconds 500
        }
    }
    Assert-Condition $ready "NS505 API did not become ready on $apiUrl"

    $sourceList = Invoke-RestMethod -Uri "$apiUrl/source-documents" -TimeoutSec 10
    $sourceId = [string]$sourceList.items[0].id
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($sourceId)) 'NS505 needs at least one source document'

    $beforeFeedbackCount = [int](Invoke-ScalarSql 'select count(*) from feedback_events;')
    $runId = "ns505-$([Guid]::NewGuid().ToString('N'))"
    $enqueueBody = @{
        suggestionType = 'knowledge_tagging'
        sourceDocumentId = $sourceId
        sourceRegionIds = @()
        confidence = @{ score = 0.71; threshold = 0.86 }
        cost = @{ inputTokens = 128; outputTokens = 40; estimatedUsd = 0.0 }
        cache = @{ cacheKey = "$runId-cache"; cacheHit = $true }
        idempotencyKey = "$runId-ai-suggestion"
        payload = @{
            suggestion = 'tag_by_semantics'
            beforeKnowledge = @('mechanics')
            afterKnowledge = @('pressure')
            evalCandidate = $true
        }
        modelRoute = 'suggestion_stub'
        promptVersion = 's007b.prompt.v1'
    } | ConvertTo-Json -Depth 8

    $enqueue = Invoke-RestMethod -Method Post -Uri "$apiUrl/ai-suggestions/enqueue" -ContentType 'application/json' -Body $enqueueBody -TimeoutSec 10
    Assert-Condition ([string]$enqueue.reviewStatus -eq 'open') 'NS505 enqueue must start as open review'

    $feedbackBody = @{
        decision = 'approved'
        teacherModified = $true
        reviewedBy = 'teacher_ns505'
        reason = 'teacher_changed_knowledge_tag_for_eval'
    } | ConvertTo-Json
    $feedback = Invoke-RestMethod -Method Post -Uri "$apiUrl/ai-suggestions/$($enqueue.aiJobId)/feedback" -ContentType 'application/json' -Body $feedbackBody -TimeoutSec 10
    Assert-Condition ([string]$feedback.reviewStatus -eq 'resolved') 'NS505 feedback must resolve review'
    Assert-Condition ([bool]$feedback.teacherModified) 'NS505 feedback must persist teacherModified'

    $afterFeedbackCount = [int](Invoke-ScalarSql 'select count(*) from feedback_events;')
    Assert-Condition ($afterFeedbackCount -eq ($beforeFeedbackCount + 1)) "NS505 feedback event count should increase by one ($beforeFeedbackCount -> $afterFeedbackCount)"

    $feedbackEventId = Invoke-ScalarSql "select id::text from feedback_events where ai_job_id = '$($enqueue.aiJobId)' order by created_at desc limit 1;"
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($feedbackEventId)) 'NS505 feedback event id missing'
    $acceptedForEval = Invoke-ScalarSql "select accepted_for_eval::text from feedback_events where id = '$feedbackEventId';"
    Assert-Condition ($acceptedForEval -eq 'true') 'NS505 feedback event must be accepted_for_eval'
    $promptMutation = Invoke-ScalarSql "select metadata->>'productionPromptMutation' from feedback_events where id = '$feedbackEventId';"
    $activeMutation = Invoke-ScalarSql "select metadata->>'activeAssetMutation' from feedback_events where id = '$feedbackEventId';"
    Assert-Condition ($promptMutation -eq 'False' -or $promptMutation -eq 'false') 'NS505 feedback event must not mutate production prompt'
    Assert-Condition ($activeMutation -eq 'False' -or $activeMutation -eq 'false') 'NS505 feedback event must not mutate active assets'

    $evalSamples = Invoke-RestMethod -Uri "$apiUrl/feedback-events/eval-samples?limit=20" -TimeoutSec 10
    $sample = @($evalSamples.items | Where-Object { [string]$_.id -eq $feedbackEventId })[0]
    Assert-Condition ($null -ne $sample) 'NS505 eval sample endpoint did not return created feedback event'
    Assert-Condition ([bool]$sample.acceptedForEval) 'NS505 eval sample must be accepted_for_eval'
    Assert-Condition ([string]$sample.taskType -eq 'knowledge_tagging') 'NS505 feedback task type mismatch'
    Assert-Condition ([string]$sample.reasonTag -eq 'teacher_changed_knowledge_tag_for_eval') 'NS505 feedback reason tag mismatch'
    Assert-Condition ($evalSamples.productionPromptMutation -eq $false) 'NS505 eval endpoint must report no prompt mutation'
    Assert-Condition ($evalSamples.activeAssetMutation -eq $false) 'NS505 eval endpoint must report no active asset mutation'

    $program = Read-Text 'apps/api/Program.cs'
    foreach ($marker in @(
        'dbContext.FeedbackEvents.Add',
        'AcceptedForEval = true',
        'productionPromptMutation = false',
        'activeAssetMutation = false',
        'app.MapGet("/feedback-events/eval-samples"'
    )) {
        Assert-Condition ($program.Contains($marker)) "NS505 API marker missing: $marker"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS505'
        checkedAt = (Get-Date).ToString('s')
        mode = 'teacher_feedback_event_eval_loop_no_prompt_mutation'
        productionEligible = $false
        externalAiCalls = 0
        allowRealModelCalls = $false
        dependency = [ordered]@{
            ns504 = 'docs/evidence/20260530-ns504-ai-suggestion-review-report.json'
            migration = '20260530044956_AddFeedbackEventsForNS505'
        }
        feedbackEvent = [ordered]@{
            id = $feedbackEventId
            aiJobId = [string]$enqueue.aiJobId
            countBefore = $beforeFeedbackCount
            countAfter = $afterFeedbackCount
            acceptedForEval = $true
            reasonTag = [string]$sample.reasonTag
            taskType = [string]$sample.taskType
        }
        evalSampleEndpoint = [ordered]@{
            returnedCreatedEvent = $true
            totalCount = [int]$evalSamples.totalCount
            productionPromptMutation = [bool]$evalSamples.productionPromptMutation
            activeAssetMutation = [bool]$evalSamples.activeAssetMutation
        }
        acceptance = [ordered]@{
            teacherModificationCreatesFeedbackEvent = $true
            feedbackEventAcceptedForEval = $true
            evalSampleEndpointReadable = $true
            productionPromptNotMutated = $true
            activeAssetNotMutated = $true
            realModelCallsStillDisabled = $true
            externalAiCallsZero = $true
        }
        boundary = 'NS505 proves teacher-modified AI suggestion feedback is captured as FeedbackEvent and exposed as an eval sample. It does not automatically mutate production prompts, schema, model routing, active C002 assets, or call real AI.'
        next = 'NS601 can continue production question search API after NS5 AI review/eval guards are runtime verified.'
        rollback = "dotnet ef database update 20260507152001_AddPaperBlueprintReviewForS009B --project apps/api/K12QuestionGraph.Api.csproj --startup-project apps/api/K12QuestionGraph.Api.csproj --configuration Release --no-build; git restore apps/api/Domain/P0Entities.cs apps/api/Data/KqgDbContext.cs apps/api/Data/Migrations/KqgDbContextModelSnapshot.cs apps/api/Program.cs tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- apps/api/Data/Migrations/20260530044956_AddFeedbackEventsForNS505.cs apps/api/Data/Migrations/20260530044956_AddFeedbackEventsForNS505.Designer.cs tools/run-ns505-feedback-eval-loop.ps1 docs/evidence/20260530-ns505-feedback-eval-loop-report.json"
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    if ($null -ne $process) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    $env:KQG_CONNECTION_STRING = $previousConnectionString
    Pop-Location
}

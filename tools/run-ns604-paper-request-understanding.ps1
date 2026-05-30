param(
    [string] $ReportPath = 'docs/evidence/20260530-ns604-paper-request-understanding-report.json',
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

function Wait-ApiReady([System.Diagnostics.Process] $Process, [string] $ApiUrl, [string] $LogErr) {
    for ($i = 0; $i -lt 90; $i++) {
        if ($Process.HasExited) {
            throw "API exited before ready on $ApiUrl; see $LogErr"
        }

        try {
            $health = Invoke-RestMethod -Uri "$ApiUrl/health/ready" -TimeoutSec 2
            if ($health.status -eq 'ok') {
                return
            }
        }
        catch {
            Start-Sleep -Milliseconds 500
        }
    }

    throw "API did not become ready on $ApiUrl"
}

function Invoke-CheckedScript([scriptblock] $Command, [string] $Label) {
    $output = & $Command 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "$Label failed: $output"
    return $output
}

function Invoke-ScalarSql([string] $Sql) {
    $psql = Join-Path $PgBin 'psql.exe'
    $value = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c $Sql
    Assert-Condition ($LASTEXITCODE -eq 0) "NS604 SQL failed: $Sql"
    return (($value | Select-Object -First 1) ?? '').Trim()
}

Push-Location $repoRoot
$previousPgPassword = $env:PGPASSWORD
$previousConnectionString = $env:KQG_CONNECTION_STRING
$process = $null
try {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'DatabasePassword or PGPASSWORD is required for NS604 paper request verification.'
    $env:PGPASSWORD = $DatabasePassword
    $env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"

    $ns603 = Read-Json 'docs/evidence/20260530-ns603-paper-basket-report.json'
    Assert-Condition ($ns603.status -eq 'pass') 'NS604 dependency NS603 report did not pass'
    Assert-Condition ([bool]$ns603.acceptance.teacherConfirmCreatesDraftPaperBasket) 'NS604 requires NS603 confirmed draft basket evidence'

    $apiBuildOutput = & dotnet build apps/api/K12QuestionGraph.Api.csproj -c Release 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "NS604 API build failed: $apiBuildOutput"

    $e002Output = Invoke-CheckedScript {
        .\tools\run-e002-paper-request-contract.ps1
    } 'E002 paper request contract'
    $e002 = $e002Output | ConvertFrom-Json
    Assert-Condition ($e002.status -eq 'pass') 'E002 source contract did not pass'
    Assert-Condition ([string]$e002.mode -eq 'draft_test') 'NS604 requires draft_test parse mode'
    Assert-Condition (-not [bool]$e002.productionEligible) 'NS604 parse must not be production eligible'
    Assert-Condition (-not [bool]$e002.allowRealModelCalls) 'NS604 parse must not allow real model calls'
    Assert-Condition ([int]$e002.blueprintRows -ge 3) 'NS604 parse must return a reviewable blueprint'
    Assert-Condition ([int]$e002.reviewQuestions -ge 1) 'NS604 parse must return review questions'
    Assert-Condition ([string]$e002.knowledgeStatus -eq 'draft') 'NS604 parse must stay on draft dynamic assets'

    $m002Output = Invoke-CheckedScript {
        .\tools\run-m002-nl-to-blueprint-production-chain.ps1
    } 'M002 natural language blueprint production chain contract'
    $m002 = $m002Output | ConvertFrom-Json
    Assert-Condition ($m002.status -eq 'pass') 'M002 source contract did not pass'

    dotnet ef database update --project apps\api\K12QuestionGraph.Api.csproj --startup-project apps\api\K12QuestionGraph.Api.csproj --configuration Release --no-build | Write-Host
    Assert-Condition ($LASTEXITCODE -eq 0) 'NS604 dotnet ef database update failed'

    $port = Get-FreeTcpPort
    $apiUrl = "http://127.0.0.1:$port"
    $logOut = Join-Path $repoRoot 'docs\evidence\ns604-api.out.log'
    $logErr = Join-Path $repoRoot 'docs\evidence\ns604-api.err.log'
    $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\api\K12QuestionGraph.Api.csproj','-c','Release','--no-build','--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr
    Wait-ApiReady -Process $process -ApiUrl $apiUrl -LogErr $logErr

    $blueprintBody = [ordered]@{
        teacherRequest = '九年级速度与惯性复习，偏难，先展示理解和细目表，暂时不要直接生成整卷'
        textbookVersion = '人教版九年级'
    } | ConvertTo-Json -Depth 6
    $blueprint = Invoke-RestMethod -Method Post -Uri "$apiUrl/paper-blueprints" -ContentType 'application/json' -Body $blueprintBody -TimeoutSec 10

    Assert-Condition ([string]$blueprint.status -eq 'pending_review') 'NS604 blueprint must stay pending_review'
    Assert-Condition ([string]$blueprint.mode -eq 'draft_test') 'NS604 blueprint mode must stay draft_test'
    Assert-Condition (-not [bool]$blueprint.productionEligible) 'NS604 blueprint must not be production eligible'
    Assert-Condition (-not [bool]$blueprint.allowRealModelCalls) 'NS604 blueprint must not allow real model calls'
    Assert-Condition ([bool]$blueprint.mustConfirmBeforeTakingQuestions) 'NS604 blueprint must require teacher confirmation before taking questions'
    Assert-Condition (-not [bool]$blueprint.opaqueGenerationAllowed) 'NS604 blueprint must block opaque generation'
    Assert-Condition ($null -eq $blueprint.confirmedPaperBasketId) 'NS604 blueprint must not create a paper basket before confirmation'
    Assert-Condition (@($blueprint.blueprint).Count -ge 3) 'NS604 blueprint rows missing'
    Assert-Condition (@($blueprint.reviewQuestions).Count -ge 1) 'NS604 review questions missing'
    Assert-Condition (@($blueprint.scope) -contains '速度与平均速度') 'NS604 should infer speed scope from teacher request'

    $dbState = Invoke-ScalarSql "select status || '|' || coalesce(confirmed_paper_basket_id::text,'') from paper_blueprint_reviews where id='$($blueprint.id)';"
    Assert-Condition ($dbState -eq 'pending_review|') "NS604 DB state must remain pending_review without basket: $dbState"

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS604'
        checkedAt = (Get-Date).ToString('s')
        mode = 'natural_language_paper_request_understanding'
        productionEligible = $false
        externalAiCalls = 0
        realStudentDataUsed = $false
        activeAssetMutation = $false
        dependency = [ordered]@{
            ns603 = 'docs/evidence/20260530-ns603-paper-basket-report.json'
            e002 = 'tools/run-e002-paper-request-contract.ps1'
            m002 = 'tools/run-m002-nl-to-blueprint-production-chain.ps1'
        }
        parse = [ordered]@{
            mode = [string]$e002.mode
            schemaVersion = [string]$e002.schemaVersion
            totalScore = [int]$e002.totalScore
            blueprintRows = [int]$e002.blueprintRows
            reviewQuestions = [int]$e002.reviewQuestions
            knowledgeStatus = [string]$e002.knowledgeStatus
        }
        reviewableBlueprint = [ordered]@{
            blueprintReviewId = [string]$blueprint.id
            status = [string]$blueprint.status
            mode = [string]$blueprint.mode
            subject = [string]$blueprint.subject
            grade = [string]$blueprint.grade
            scope = @($blueprint.scope)
            totalScore = [int]$blueprint.totalScore
            blueprintRows = @($blueprint.blueprint).Count
            reviewQuestions = @($blueprint.reviewQuestions).Count
            confirmedPaperBasketId = $blueprint.confirmedPaperBasketId
        }
        acceptance = [ordered]@{
            teacherRequestProducesSystemUnderstanding = $true
            teacherRequestProducesReviewableBlueprint = $true
            pendingReviewBeforeTeacherConfirmation = $true
            reviewQuestionsVisible = $true
            noPaperBasketBeforeConfirmation = $true
            noOpaquePaperGeneration = $true
            noExternalAiCall = $true
            noRealStudentData = $true
            noActiveSwitch = $true
        }
        verification = [ordered]@{
            build = 'dotnet build apps/api/K12QuestionGraph.Api.csproj -c Release'
            test = 'tools/run-e002-paper-request-contract.ps1; POST /paper-blueprints pending_review smoke'
            contractInvariant = 'tools/run-m002-nl-to-blueprint-production-chain.ps1'
            hotspot = 'gate_na: no independent hotspot command; teacher workflow hotspot covered by visible understanding, review questions, pending_review guard, no basket before confirmation, no opaque generation'
        }
        boundary = 'NS604 proves natural-language paper requests are converted into reviewable understanding and blueprint drafts only; they do not create an opaque final paper or draft basket before teacher confirmation.'
        rollback = "delete from paper_blueprint_reviews where id = '$($blueprint.id)'; git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns604-paper-request-understanding.ps1 $ReportPath"
        next = 'NS605 can continue one-click replacement and undo snapshot verification.'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    if ($null -ne $process) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    $env:KQG_CONNECTION_STRING = $previousConnectionString
    $env:PGPASSWORD = $previousPgPassword
    Pop-Location
}

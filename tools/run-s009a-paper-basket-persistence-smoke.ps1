param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [int] $ApiPort = 5294,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $ReportPath = 'docs/evidence/20260507-s009a-paper-basket-persistence-smoke-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
if ([string]::IsNullOrWhiteSpace($DatabasePassword)) { throw 'DatabasePassword or PGPASSWORD is required for S009A smoke' }

$apiUrl = "http://127.0.0.1:$ApiPort"
$logOut = Join-Path $repoRoot 'docs/evidence/s009a-smoke-api.out.log'
$logErr = Join-Path $repoRoot 'docs/evidence/s009a-smoke-api.err.log'
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
    if ($LASTEXITCODE -ne 0) { throw 'S009A active knowledge query failed' }
    $knowledgeId = (($knowledgeId | Select-Object -First 1) ?? '').Trim()
    if ([string]::IsNullOrWhiteSpace($knowledgeId)) {
        $knowledgeId = [Guid]::NewGuid().ToString()
        $code = "S009A-ACTIVE-" + [Guid]::NewGuid().ToString('N').Substring(0, 8).ToUpperInvariant()
        & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c "insert into knowledge_nodes (id,subject,stage,code,title,node_type,level,status,version,metadata,created_at,updated_at) values ('$knowledgeId','physics','junior_middle_school','$code','S009A Active Seed','concept',2,'active',1,'{}',now(),now());"
        if ($LASTEXITCODE -ne 0) { throw 'S009A active knowledge seed failed' }
    }

    for ($i = 1; $i -le 2; $i++) {
        $questionBody = @{
            subject = 'physics'
            stage = 'junior_middle_school'
            grade = 'grade_8'
            questionType = 'single_choice'
            defaultScore = 3
            difficultyEstimated = 0.56
            status = 'draft'
            primaryKnowledgeId = $knowledgeId
            blocks = @(
                @{ blockType = 'text'; sortOrder = 0; content = @{ text = "S009A 题篮候选题 $i" }; sourceRegionId = $null }
            )
            assets = @()
            answer = @{ value = 'A' }
            solution = @{ text = 'S009A smoke' }
        } | ConvertTo-Json -Depth 8
        Invoke-RestMethod -Method Post -Uri "$apiUrl/questions" -ContentType 'application/json' -Body $questionBody -TimeoutSec 10 | Out-Null
    }

    $search = Invoke-RestMethod -Uri "$apiUrl/questions?subject=physics&stage=junior_middle_school&page=1&limit=2" -TimeoutSec 10
    $questionIds = @($search.items | Select-Object -First 2 | ForEach-Object { [string]$_.id })
    if ($questionIds.Count -lt 2) { throw 'S009A needs at least two searchable questions' }

    $createBody = @{
        title = 'S009A 持久化题篮'
        subject = 'physics'
        stage = 'junior_middle_school'
        grade = 'grade_8'
        knowledgeVersionStatus = 'active'
        knowledgeVersion = 1
        items = @(
            @{ questionItemId = $questionIds[0]; sectionNo = 1; questionNo = 1; subQuestionNo = $null; score = 3; sortOrder = 0 },
            @{ questionItemId = $questionIds[1]; sectionNo = 1; questionNo = 2; subQuestionNo = '2-1'; score = 5; sortOrder = 1 }
        )
    } | ConvertTo-Json -Depth 8

    $created = Invoke-RestMethod -Method Post -Uri "$apiUrl/paper-baskets" -ContentType 'application/json' -Body $createBody -TimeoutSec 10
    $loaded = Invoke-RestMethod -Uri "$apiUrl/paper-baskets/$($created.id)" -TimeoutSec 10

    if ($loaded.items.Count -ne 2) { throw 'S009A loaded basket item count mismatch' }
    if ([int]$loaded.items[0].questionNo -ne 1) { throw 'S009A questionNo not persisted' }
    if ([string]$loaded.items[1].subQuestionNo -ne '2-1') { throw 'S009A subQuestionNo not persisted' }
    if ([decimal]$loaded.items[1].score -ne 5) { throw 'S009A score not persisted' }
    if ([string]$loaded.knowledgeVersionStatus -ne 'active') { throw 'S009A knowledge version status mismatch' }
    if ([int]$loaded.knowledgeVersion -ne 1) { throw 'S009A knowledge version mismatch' }
    if ([int]$loaded.structure.itemCount -ne 2) { throw 'S009A structure itemCount mismatch' }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'S009A'
        checkedAt = (Get-Date).ToString('s')
        basketId = $loaded.id
        itemCount = $loaded.items.Count
        questionNumbers = @($loaded.items | ForEach-Object { $_.questionNo })
        subQuestionNumbers = @($loaded.items | ForEach-Object { $_.subQuestionNo })
        totalScore = $loaded.structure.totalScore
        knowledgeVersionStatus = $loaded.knowledgeVersionStatus
        knowledgeVersion = $loaded.knowledgeVersion
        conclusion = 'paper basket persists paper structure question numbers scores sub-question numbers and active knowledge version references'
    }
    $full = Join-Path $repoRoot $ReportPath
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $full -Encoding UTF8
    $report | ConvertTo-Json -Depth 10
}
finally {
    if ($null -ne $process) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
    $env:KQG_CONNECTION_STRING = $previousConnectionString
}

param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [int] $ApiPort = 5296,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $ReportPath = 'docs/evidence/20260508-s010a-export-preflight-api-smoke-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
if ([string]::IsNullOrWhiteSpace($DatabasePassword)) { throw 'DatabasePassword or PGPASSWORD is required for S010A smoke' }

$apiUrl = "http://127.0.0.1:$ApiPort"
$logOut = Join-Path $repoRoot 'docs/evidence/s010a-smoke-api.out.log'
$logErr = Join-Path $repoRoot 'docs/evidence/s010a-smoke-api.err.log'
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
    if ($LASTEXITCODE -ne 0) { throw 'S010A active knowledge query failed' }
    $knowledgeId = (($knowledgeId | Select-Object -First 1) ?? '').Trim()
    if ([string]::IsNullOrWhiteSpace($knowledgeId)) {
        $knowledgeId = [Guid]::NewGuid().ToString()
        $code = "S010A-ACTIVE-" + [Guid]::NewGuid().ToString('N').Substring(0, 8).ToUpperInvariant()
        & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c "insert into knowledge_nodes (id,subject,stage,code,title,node_type,level,status,version,metadata,created_at,updated_at) values ('$knowledgeId','physics','junior_middle_school','$code','S010A Active Seed','concept',2,'active',1,'{}',now(),now());"
        if ($LASTEXITCODE -ne 0) { throw 'S010A active knowledge seed failed' }
    }

    $sample = Join-Path $env:TEMP 'kqg-s010a-export-source.txt'
    Set-Content -LiteralPath $sample -Value "S010A export source $([Guid]::NewGuid())" -Encoding UTF8
    $upload = curl.exe -s -F "file=@$sample;filename=s010a-export-source.txt" -F "sourceType=school_paper" -F "sourceTitle=S010A Export Source" -F "ownerScope=school" -F "licenseOrPermission=internal_authorized" -F "sharingAllowed=true" -F "containsStudentPii=false" -F "anonymizationStatus=not_applicable" "$apiUrl/files" | ConvertFrom-Json
    $sourceDocumentId = [string]$upload.sourceDocument.id

    $regionBody = @{
        pageNumber = 1
        x = 12
        y = 10
        width = 70
        height = 22
        coordinateUnit = 'percent'
        screenshotRelativePath = $null
        regionType = 'question'
    } | ConvertTo-Json
    $region = Invoke-RestMethod -Method Post -Uri "$apiUrl/source-documents/$sourceDocumentId/regions" -ContentType 'application/json' -Body $regionBody -TimeoutSec 10

    $completeQuestionBody = @{
        subject = 'physics'
        stage = 'junior_middle_school'
        grade = 'grade_8'
        questionType = 'calculation'
        defaultScore = 6
        difficultyEstimated = 0.61
        status = 'draft'
        primaryKnowledgeId = $knowledgeId
        blocks = @(
            @{ blockType = 'text'; sortOrder = 0; content = @{ text = 'S010A 完整导出前审校题干' }; sourceRegionId = $region.id },
            @{ blockType = 'formula'; sortOrder = 1; content = @{ latex = 'v=s/t' }; sourceRegionId = $region.id },
            @{ blockType = 'table'; sortOrder = 2; content = @{ rows = @(@('s','t'),@('10m','2s')) }; sourceRegionId = $region.id }
        )
        assets = @(
            @{ fileAssetId = $upload.id; sourceRegionId = $region.id; assetType = 'image'; purpose = 'question_figure'; metadata = @{ from = 's010a' } }
        )
        answer = @{ value = '5m/s' }
        solution = @{ text = '速度等于路程除以时间。' }
    } | ConvertTo-Json -Depth 10
    $completeQuestion = Invoke-RestMethod -Method Post -Uri "$apiUrl/questions" -ContentType 'application/json' -Body $completeQuestionBody -TimeoutSec 10

    $riskQuestionBody = @{
        subject = 'physics'
        stage = 'junior_middle_school'
        grade = 'grade_8'
        questionType = 'short_answer'
        defaultScore = 4
        difficultyEstimated = 0.54
        status = 'draft'
        primaryKnowledgeId = $null
        blocks = @(
            @{ blockType = 'text'; sortOrder = 0; content = @{ text = 'S010A 缺少答案解析来源与版本引用的题目' }; sourceRegionId = $null }
        )
        assets = @()
        answer = $null
        solution = $null
    } | ConvertTo-Json -Depth 10
    $riskQuestion = Invoke-RestMethod -Method Post -Uri "$apiUrl/questions" -ContentType 'application/json' -Body $riskQuestionBody -TimeoutSec 10

    $basketBody = @{
        title = 'S010A 导出前审校题篮'
        subject = 'physics'
        stage = 'junior_middle_school'
        grade = 'grade_8'
        knowledgeVersionStatus = 'active'
        knowledgeVersion = 1
        items = @(
            @{ questionItemId = $completeQuestion.id; sectionNo = 1; questionNo = 1; subQuestionNo = $null; score = 6; sortOrder = 0 },
            @{ questionItemId = $riskQuestion.id; sectionNo = 1; questionNo = 2; subQuestionNo = $null; score = 4; sortOrder = 1 }
        )
    } | ConvertTo-Json -Depth 8
    $basket = Invoke-RestMethod -Method Post -Uri "$apiUrl/paper-baskets" -ContentType 'application/json' -Body $basketBody -TimeoutSec 10

    $preflightBody = @{ exportFormat = 'docx' } | ConvertTo-Json
    $preflight = Invoke-RestMethod -Method Post -Uri "$apiUrl/paper-baskets/$($basket.id)/export-preflight" -ContentType 'application/json' -Body $preflightBody -TimeoutSec 10

    if ([string]$preflight.status -ne 'blocked') { throw 'S010A preflight should block when required export risks exist' }
    if ([bool]$preflight.productionEligible) { throw 'S010A preflight must stay non-production eligible' }
    if ([int]$preflight.itemCount -ne 2) { throw 'S010A item count mismatch' }
    if ([int]$preflight.summary.formulaReadyCount -lt 1) { throw 'S010A formula check missing' }
    if ([int]$preflight.summary.tableReadyCount -lt 1) { throw 'S010A table check missing' }
    if ([int]$preflight.summary.imageReadyCount -lt 1) { throw 'S010A image check missing' }
    if ([int]$preflight.summary.answerReadyCount -lt 1) { throw 'S010A answer check missing' }
    if ([int]$preflight.summary.solutionReadyCount -lt 1) { throw 'S010A solution check missing' }
    if ([int]$preflight.summary.authorizedSourceCount -lt 1) { throw 'S010A source authorization check missing' }
    if ([int]$preflight.summary.activeKnowledgeVersionCount -ne 1) { throw 'S010A knowledge version reference count mismatch' }

    $issueCodes = @($preflight.items | ForEach-Object { $_.issues } | ForEach-Object { $_.code })
    foreach ($requiredIssue in @('answer_missing','solution_missing','source_missing','knowledge_version_reference_missing','image_not_attached')) {
        if ($issueCodes -notcontains $requiredIssue) { throw "S010A missing issue code: $requiredIssue" }
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'S010A'
        checkedAt = (Get-Date).ToString('s')
        paperBasketId = $basket.id
        preflightStatus = $preflight.status
        itemCount = $preflight.itemCount
        issueCodes = $issueCodes
        summary = $preflight.summary
        teacherMessage = $preflight.teacherMessage
        conclusion = 'export preflight API checks image formula table answer solution source authorization knowledge version references and blocks missing risks before artifact generation'
        rollback = 'revert the S010A API endpoint/service changes and remove the run-s010a gate entry; no migration is required'
    }
    $full = Join-Path $repoRoot $ReportPath
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $full -Encoding UTF8
    $report | ConvertTo-Json -Depth 10
}
finally {
    if ($null -ne $process) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
    $env:KQG_CONNECTION_STRING = $previousConnectionString
}

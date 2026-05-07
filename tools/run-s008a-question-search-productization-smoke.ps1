param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [int] $ApiPort = 5293,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $ReportPath = 'docs/evidence/20260506-s008a-question-search-productization-smoke-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
if ([string]::IsNullOrWhiteSpace($DatabasePassword)) { throw 'DatabasePassword or PGPASSWORD is required for S008A smoke' }

$apiUrl = "http://127.0.0.1:$ApiPort"
$logOut = Join-Path $repoRoot 'docs/evidence/s008a-smoke-api.out.log'
$logErr = Join-Path $repoRoot 'docs/evidence/s008a-smoke-api.err.log'
$previousConnectionString = $env:KQG_CONNECTION_STRING
$env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"

$process = $null
try {
    $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\\api\\K12QuestionGraph.Api.csproj','--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr
    $ready = $false
    for ($i = 0; $i -lt 180; $i++) {
        try { if ((Invoke-RestMethod -Uri "$apiUrl/health/ready" -TimeoutSec 2).status -eq 'ok') { $ready = $true; break } } catch {}
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { throw "API did not become ready on $apiUrl" }

    $sourceList = Invoke-RestMethod -Uri "$apiUrl/source-documents" -TimeoutSec 10
    $sourceId = [string]$sourceList.items[0].id
    if ([string]::IsNullOrWhiteSpace($sourceId)) { throw 'S008A needs at least one source document' }

    $activeKnowledge = Invoke-RestMethod -Uri "$apiUrl/questions?subject=physics&stage=junior_middle_school&page=1&limit=1" -TimeoutSec 10
    if ([string]$activeKnowledge.knowledgeStatus -ne 'active') { throw 'S008A default knowledge status must be active' }
    if ([int]$activeKnowledge.knowledgeVersion -ne 1) { throw 'S008A default knowledge version must be 1' }

    $uploadSample = Join-Path $env:TEMP 'kqg-s008a-image.txt'
    Set-Content -LiteralPath $uploadSample -Value "S008A image placeholder $([Guid]::NewGuid())" -Encoding UTF8
    $upload = curl.exe -s -F "file=@$uploadSample;filename=s008a-image.txt" -F "sourceType=school_paper" -F "sourceTitle=S008A Search Source" -F "ownerScope=school" -F "licenseOrPermission=internal_authorized" -F "sharingAllowed=true" -F "containsStudentPii=false" -F "anonymizationStatus=not_applicable" "$apiUrl/files" | ConvertFrom-Json
    $docId = [string]$upload.sourceDocument.id

    $regionBody = @{
        pageNumber = 1
        x = 10
        y = 10
        width = 70
        height = 20
        coordinateUnit = 'percent'
        screenshotRelativePath = $null
        regionType = 'question'
    } | ConvertTo-Json
    $region = Invoke-RestMethod -Method Post -Uri "$apiUrl/source-documents/$docId/regions" -ContentType 'application/json' -Body $regionBody -TimeoutSec 10

    $searchPage1 = Invoke-RestMethod -Uri "$apiUrl/questions?subject=physics&stage=junior_middle_school&page=1&limit=10" -TimeoutSec 10
    if ([int]$searchPage1.page -ne 1) { throw 'S008A page=1 response mismatch' }
    if ([int]$searchPage1.limit -ne 10) { throw 'S008A limit=10 response mismatch' }

    $psql = Join-Path $PgBin 'psql.exe'
    $activeKnowledgeId = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c "select id from knowledge_nodes where status='active' and version=1 order by created_at asc limit 1;"
    if ($LASTEXITCODE -ne 0) { throw 'S008A active knowledge query failed' }
    $activeKnowledgeId = (($activeKnowledgeId | Select-Object -First 1) ?? '').Trim()
    if ([string]::IsNullOrWhiteSpace($activeKnowledgeId)) {
        $newCode = "S008A-ACTIVE-" + [Guid]::NewGuid().ToString('N').Substring(0, 8).ToUpperInvariant()
        $newId = [Guid]::NewGuid().ToString()
        & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c "insert into knowledge_nodes (id,subject,stage,code,title,node_type,level,status,version,metadata,created_at,updated_at) values ('$newId','physics','junior_middle_school','$newCode','S008A Active Seed','concept',2,'active',1,'{}',now(),now());"
        if ($LASTEXITCODE -ne 0) { throw 'S008A failed to seed active knowledge node' }
        $activeKnowledgeId = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c "select id from knowledge_nodes where code='$newCode' limit 1;"
        if ($LASTEXITCODE -ne 0) { throw 'S008A failed to read seeded active knowledge node' }
        $activeKnowledgeId = (($activeKnowledgeId | Select-Object -First 1) ?? '').Trim()
    }
    if ([string]::IsNullOrWhiteSpace($activeKnowledgeId)) { throw 'S008A requires at least one active v1 knowledge node' }

    $questionBody = @{
        subject = 'physics'
        stage = 'junior_middle_school'
        grade = 'grade_8'
        questionType = 'single_choice'
        defaultScore = 4
        difficultyEstimated = 0.58
        status = 'draft'
        primaryKnowledgeId = $activeKnowledgeId
        blocks = @(
            @{ blockType = 'text'; sortOrder = 0; content = @{ text = 'S008A 题卡是否包含公式、表格、题图标记？' }; sourceRegionId = $region.id },
            @{ blockType = 'formula'; sortOrder = 1; content = @{ latex = 'F=ma' }; sourceRegionId = $region.id },
            @{ blockType = 'table'; sortOrder = 2; content = @{ rows = @(@('量','值'),@('F','10N')) }; sourceRegionId = $region.id }
        )
        assets = @(
            @{ fileAssetId = $upload.id; sourceRegionId = $region.id; assetType = 'image'; purpose = 'question_figure'; metadata = @{ from = 's008a' } }
        )
        answer = @{ value = 'A' }
        solution = @{ text = '验证题卡字段' }
    } | ConvertTo-Json -Depth 10
    $created = Invoke-RestMethod -Method Post -Uri "$apiUrl/questions" -ContentType 'application/json' -Body $questionBody -TimeoutSec 10

    $search = Invoke-RestMethod -Uri "$apiUrl/questions?subject=physics&stage=junior_middle_school&sourceType=school_paper&page=1&limit=10" -TimeoutSec 10
    $card = @($search.items | Where-Object { $_.id -eq $created.id })[0]
    if ($null -eq $card) { throw 'S008A created question should be searchable with sourceType filter' }
    if (-not [bool]$card.hasFormula) { throw 'S008A card.hasFormula should be true' }
    if (-not [bool]$card.hasTable) { throw 'S008A card.hasTable should be true' }
    if (-not [bool]$card.hasImage) { throw 'S008A card.hasImage should be true' }
    if (@($card.sources.types) -notcontains 'school_paper') { throw 'S008A source type summary missing school_paper' }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'S008A'
        checkedAt = (Get-Date).ToString('s')
        defaultKnowledge = [ordered]@{
            status = $activeKnowledge.knowledgeStatus
            version = $activeKnowledge.knowledgeVersion
        }
        pagination = [ordered]@{
            page = $searchPage1.page
            limit = $searchPage1.limit
            total = $searchPage1.total
        }
        cardFlags = [ordered]@{
            hasFormula = $card.hasFormula
            hasTable = $card.hasTable
            hasImage = $card.hasImage
            sourceTypes = @($card.sources.types)
        }
        conclusion = 'question search defaults to C002 active v1 and returns paginated cards with source summary and formula/table/image flags'
    }
    $full = Join-Path $repoRoot $ReportPath
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $full -Encoding UTF8
    $report | ConvertTo-Json -Depth 10
}
finally {
    if ($null -ne $process) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
    $env:KQG_CONNECTION_STRING = $previousConnectionString
}

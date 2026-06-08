param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [int] $ApiPort = 0,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $OutputRoot = 'tmp\s010b-paper-artifacts',
    [string] $ReportPath = 'docs\evidence\20260508-s010b-word-pdf-artifact-chain-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
if ([string]::IsNullOrWhiteSpace($DatabasePassword)) { throw 'DatabasePassword or PGPASSWORD is required for S010B smoke' }

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

function Test-FileHashMatches([string] $Path, [string] $ExpectedHash) {
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    Assert-True ($actual -eq $ExpectedHash.ToLowerInvariant()) "hash mismatch for $Path"
}

$requestedApiPort = $ApiPort
if ($ApiPort -le 0) {
    $ApiPort = Get-FreeTcpPort
}
$apiUrl = "http://127.0.0.1:$ApiPort"
$logOut = Join-Path $repoRoot 'docs/evidence/s010b-smoke-api.out.log'
$logErr = Join-Path $repoRoot 'docs/evidence/s010b-smoke-api.err.log'
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

    $psql = Join-Path $PgBin 'psql.exe'
    $knowledgeId = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c "select id from knowledge_nodes where status='active' and version=1 order by created_at asc limit 1;"
    if ($LASTEXITCODE -ne 0) { throw 'S010B active knowledge query failed' }
    $knowledgeId = (($knowledgeId | Select-Object -First 1) ?? '').Trim()
    if ([string]::IsNullOrWhiteSpace($knowledgeId)) {
        $knowledgeId = [Guid]::NewGuid().ToString()
        $code = "S010B-ACTIVE-" + [Guid]::NewGuid().ToString('N').Substring(0, 8).ToUpperInvariant()
        & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c "insert into knowledge_nodes (id,subject,stage,code,title,node_type,level,status,version,metadata,created_at,updated_at) values ('$knowledgeId','physics','junior_middle_school','$code','S010B Active Seed','concept',2,'active',1,'{}',now(),now());"
        if ($LASTEXITCODE -ne 0) { throw 'S010B active knowledge seed failed' }
    }

    $sample = Join-Path $env:TEMP 'kqg-s010b-export-source.txt'
    Set-Content -LiteralPath $sample -Value "S010B export source $([Guid]::NewGuid())" -Encoding UTF8
    $upload = curl.exe -s -F "file=@$sample;filename=s010b-export-source.txt" -F "sourceType=school_paper" -F "sourceTitle=S010B Export Source" -F "ownerScope=school" -F "licenseOrPermission=internal_authorized" -F "sharingAllowed=true" -F "containsStudentPii=false" -F "anonymizationStatus=not_applicable" "$apiUrl/files" | ConvertFrom-Json
    $sourceDocumentId = [string]$upload.sourceDocument.id

    $regionBody = @{
        pageNumber = 1
        x = 10
        y = 10
        width = 80
        height = 24
        coordinateUnit = 'percent'
        screenshotRelativePath = $null
        regionType = 'question'
    } | ConvertTo-Json
    $region = Invoke-RestMethod -Method Post -Uri "$apiUrl/source-documents/$sourceDocumentId/regions" -ContentType 'application/json' -Body $regionBody -TimeoutSec 10

    $questionBlocks = @(
        @{ blockType = 'text'; sortOrder = 0; content = @{ text = 'S010B 可导出题干：一辆小车做匀速直线运动。' }; sourceRegionId = $region.id },
        @{ blockType = 'formula'; sortOrder = 1; content = @{ latex = 'v=s/t' }; sourceRegionId = $region.id },
        @{ blockType = 'table'; sortOrder = 2; content = @{ rows = @(@('s','t'),@('10m','2s')) }; sourceRegionId = $region.id }
    )
    $questionAnswer = '5m/s'
    $questionSolution = '速度等于路程除以时间，10m 除以 2s 得 5m/s。'
    $questionBody = @{
        subject = 'physics'
        stage = 'junior_middle_school'
        grade = 'grade_8'
        questionType = 'calculation'
        defaultScore = 6
        difficultyEstimated = 0.61
        status = 'draft'
        primaryKnowledgeId = $knowledgeId
        blocks = $questionBlocks
        assets = @(
            @{ fileAssetId = $upload.id; sourceRegionId = $region.id; assetType = 'image'; purpose = 'question_figure'; metadata = @{ from = 's010b' } }
        )
        answer = @{ value = $questionAnswer }
        solution = @{ text = $questionSolution }
    } | ConvertTo-Json -Depth 10
    $question = Invoke-RestMethod -Method Post -Uri "$apiUrl/questions" -ContentType 'application/json' -Body $questionBody -TimeoutSec 10

    $basketBody = @{
        title = 'S010B Word PDF 导出题篮'
        subject = 'physics'
        stage = 'junior_middle_school'
        grade = 'grade_8'
        knowledgeVersionStatus = 'active'
        knowledgeVersion = 1
        items = @(
            @{ questionItemId = $question.id; sectionNo = 1; questionNo = 1; subQuestionNo = $null; score = 6; sortOrder = 0 }
        )
    } | ConvertTo-Json -Depth 8
    $basket = Invoke-RestMethod -Method Post -Uri "$apiUrl/paper-baskets" -ContentType 'application/json' -Body $basketBody -TimeoutSec 10

    $preflightBody = @{ exportFormat = 'docx' } | ConvertTo-Json
    $preflight = Invoke-RestMethod -Method Post -Uri "$apiUrl/paper-baskets/$($basket.id)/export-preflight" -ContentType 'application/json' -Body $preflightBody -TimeoutSec 10
    Assert-True ([string]$preflight.status -eq 'ready_for_review') 'S010B preflight should be ready for review before artifact generation'
    Assert-True (-not [bool]$preflight.productionEligible) 'S010B preflight must stay non-production eligible'
    Assert-True ([int]$preflight.summary.formulaReadyCount -eq 1) 'S010B formula check missing'
    Assert-True ([int]$preflight.summary.tableReadyCount -eq 1) 'S010B table check missing'
    Assert-True ([int]$preflight.summary.imageReadyCount -eq 1) 'S010B image check missing'
    Assert-True ([int]$preflight.summary.answerReadyCount -eq 1) 'S010B answer check missing'
    Assert-True ([int]$preflight.summary.solutionReadyCount -eq 1) 'S010B solution check missing'
    Assert-True ([int]$preflight.summary.authorizedSourceCount -eq 1) 'S010B source authorization check missing'
    Assert-True ([int]$preflight.summary.activeKnowledgeVersionCount -eq 1) 'S010B knowledge version reference check missing'

    $artifactInputPath = Join-Path $repoRoot (Join-Path $OutputRoot 's010b-paper-input.json')
    New-Item -ItemType Directory -Path (Split-Path -Parent $artifactInputPath) -Force | Out-Null
    $artifactInput = [ordered]@{
        taskId = 'S010B'
        paperBasketId = $basket.id
        basketTitle = $basket.title
        preflight = $preflight
        questions = @(
            [ordered]@{
                questionItemId = $question.id
                questionNo = 1
                score = 6
                title = '匀速直线运动速度计算'
                blocks = $questionBlocks
                hasImage = $true
                answer = $questionAnswer
                solution = $questionSolution
                sourceAuthorizationStatus = 'authorized'
                knowledgeVersionStatus = 'active'
                knowledgeVersion = 1
            }
        )
    }
    $artifactInput | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $artifactInputPath -Encoding UTF8

    python tools\s010b_paper_artifact_chain.py --input $artifactInputPath --output-root $OutputRoot --report $ReportPath | Write-Host
    if ($LASTEXITCODE -ne 0) { throw 'S010B artifact generator failed' }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    $report = Get-Content -LiteralPath $reportFullPath -Raw | ConvertFrom-Json
    Assert-True ($report.status -eq 'pass') 'S010B artifact report did not pass'
    Assert-True ($report.preflightStatus -eq 'ready_for_review') 'S010B report preflight status mismatch'

    $manifest = Get-Content -LiteralPath (Join-Path $repoRoot $report.manifestPath) -Raw | ConvertFrom-Json
    Assert-True ($manifest.schemaVersion -eq 'paper-artifact-manifest.s010b.v1') 'S010B manifest schema mismatch'
    Assert-True ($manifest.taskId -eq 'S010B') 'S010B manifest task mismatch'
    foreach ($variant in @('student','teacher','answer')) {
        $artifact = $manifest.variants.$variant
        Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot $artifact.docxPath)) "missing S010B $variant docx"
        Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot $artifact.pdfPath)) "missing S010B $variant pdf"
        Test-FileHashMatches -Path (Join-Path $repoRoot $artifact.docxPath) -ExpectedHash $artifact.docxSha256
        Test-FileHashMatches -Path (Join-Path $repoRoot $artifact.pdfPath) -ExpectedHash $artifact.pdfSha256
    }
    Assert-True ($manifest.checks.student.docx.studentHidesAnswer -eq $true) 'student version must hide answers and solutions'
    Assert-True ($manifest.checks.teacher.docx.hasAnswer -eq $true) 'teacher version must include answer'
    Assert-True ($manifest.checks.teacher.docx.hasSolution -eq $true) 'teacher version must include solution'
    Assert-True ($manifest.checks.answer.docx.hasAnswer -eq $true) 'answer version must include answer'

    $report | Add-Member -NotePropertyName requestedApiPort -NotePropertyValue $requestedApiPort -Force
    $report | Add-Member -NotePropertyName resolvedApiPort -NotePropertyValue $ApiPort -Force
    $report | Add-Member -NotePropertyName portFallbackApplied -NotePropertyValue ($requestedApiPort -ne $ApiPort) -Force
    $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 20
}
finally {
    if ($null -ne $process) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
    $env:KQG_CONNECTION_STRING = $previousConnectionString
    if ($pushedLocation) { Pop-Location }
}

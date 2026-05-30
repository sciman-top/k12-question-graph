param(
    [string] $ReportPath = 'docs/evidence/20260530-ns601-question-search-api-report.json',
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
    for ($i = 0; $i -lt 60; $i++) {
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

function Invoke-ScalarSql([string] $Sql) {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'DatabasePassword or PGPASSWORD is required for NS601 question search API.'
    $psql = Join-Path $PgBin 'psql.exe'
    $previous = $env:PGPASSWORD
    $env:PGPASSWORD = $DatabasePassword
    try {
        $value = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c $Sql
        Assert-Condition ($LASTEXITCODE -eq 0) "NS601 SQL failed: $Sql"
        return (($value | Select-Object -First 1) ?? '').Trim()
    }
    finally {
        $env:PGPASSWORD = $previous
    }
}

function Invoke-NonQuerySql([string] $Sql) {
    [void](Invoke-ScalarSql $Sql)
}

function Assert-ContainsQuestion([object] $Search, [string] $QuestionId, [string] $Label) {
    $item = @($Search.items | Where-Object { [string]$_.id -eq $QuestionId }) | Select-Object -First 1
    Assert-Condition ($null -ne $item) "$Label did not include expected question $QuestionId"
    return $item
}

function Assert-NotContainsQuestion([object] $Search, [string] $QuestionId, [string] $Label) {
    $item = @($Search.items | Where-Object { [string]$_.id -eq $QuestionId }) | Select-Object -First 1
    Assert-Condition ($null -eq $item) "$Label unexpectedly included question $QuestionId"
}

Push-Location $repoRoot
$process = $null
$createdQuestionIds = @()
$createdSourceDocumentIds = @()
$createdFileAssetIds = @()
try {
    $ns501 = Read-Json 'docs/evidence/20260530-ns501-c002-active-boundary.json'
    Assert-Condition ($ns501.status -eq 'pass') 'NS601 dependency NS501 report did not pass'
    Assert-Condition ([bool]$ns501.acceptance.questionSearchUsesActiveC002) 'NS601 requires active C002 question search dependency'
    Assert-Condition ([bool]$ns501.acceptance.candidateAssetsExcludedByDefault) 'NS601 requires candidate assets excluded by default'

    $program = Get-Content -LiteralPath 'apps/api/Program.cs' -Raw
    foreach ($marker in @('bool? hasFormula', 'bool? hasTable', 'bool? hasImage', 'QuestionSearchResponse', 'QuestionCardResponse', 'SourceSummaryResponse')) {
        Assert-Condition ($program.Contains($marker)) "NS601 API marker missing: $marker"
    }

    $previousConnectionString = $env:KQG_CONNECTION_STRING
    $previousPgPassword = $env:PGPASSWORD
    $env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
    $env:PGPASSWORD = $DatabasePassword

    try {
        dotnet ef database update --project apps\api\K12QuestionGraph.Api.csproj --startup-project apps\api\K12QuestionGraph.Api.csproj --configuration Release --no-build | Write-Host
        Assert-Condition ($LASTEXITCODE -eq 0) 'NS601 dotnet ef database update failed'

        .\tools\seed-knowledge.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host

        $knowledgeId = Invoke-ScalarSql "select id from knowledge_nodes where status = 'active' and version = 1 order by created_at asc limit 1;"
        Assert-Condition (-not [string]::IsNullOrWhiteSpace($knowledgeId)) 'NS601 requires at least one active v1 knowledge node'

        $port = Get-FreeTcpPort
        $apiUrl = "http://127.0.0.1:$port"
        $logOut = Join-Path $repoRoot 'docs\evidence\ns601-api.out.log'
        $logErr = Join-Path $repoRoot 'docs\evidence\ns601-api.err.log'
        $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\api\K12QuestionGraph.Api.csproj','-c','Release','--no-build','--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr
        Wait-ApiReady -Process $process -ApiUrl $apiUrl -LogErr $logErr

        $sample = Join-Path $env:TEMP 'kqg-ns601-search-source.txt'
        Set-Content -LiteralPath $sample -Value "NS601 question search source $([Guid]::NewGuid())" -Encoding UTF8
        $upload = curl.exe -s -F "file=@$sample;filename=ns601-search-source.txt" -F "sourceType=school_paper" -F "sourceTitle=NS601 Search Source" -F "ownerScope=school" -F "licenseOrPermission=synthetic_fixture" -F "sharingAllowed=true" -F "containsStudentPii=false" -F "anonymizationStatus=synthetic" "$apiUrl/files" | ConvertFrom-Json
        $createdFileAssetIds += [string]$upload.id
        $createdSourceDocumentIds += [string]$upload.sourceDocument.id

        $regionBody = [ordered]@{
            pageNumber = 1
            x = 10
            y = 12
            width = 68
            height = 24
            coordinateUnit = 'percent'
            screenshotRelativePath = $null
            regionType = 'question'
        } | ConvertTo-Json
        $region = Invoke-RestMethod -Method Post -Uri "$apiUrl/source-documents/$($upload.sourceDocument.id)/regions" -ContentType 'application/json' -Body $regionBody -TimeoutSec 10

        $richQuestionBody = [ordered]@{
            subject = 'physics'
            stage = 'junior_middle_school'
            grade = 'grade_8'
            questionType = 'single_choice'
            defaultScore = 4
            difficultyEstimated = 0.58
            status = 'draft'
            primaryKnowledgeId = $knowledgeId
            blocks = @(
                [ordered]@{ blockType = 'text'; sortOrder = 0; content = [ordered]@{ text = 'NS601 富媒体检索题，含公式、表格和题图。' }; sourceRegionId = $region.id },
                [ordered]@{ blockType = 'formula'; sortOrder = 1; content = [ordered]@{ latex = 'v=s/t' }; sourceRegionId = $region.id },
                [ordered]@{ blockType = 'table'; sortOrder = 2; content = [ordered]@{ rows = @(@('s','t'),@('10m','2s')) }; sourceRegionId = $region.id }
            )
            assets = @(
                [ordered]@{ fileAssetId = $upload.id; sourceRegionId = $region.id; assetType = 'image'; purpose = 'question_figure'; metadata = [ordered]@{ taskId = 'NS601' } }
            )
            answer = [ordered]@{ value = 'A' }
            solution = [ordered]@{ text = '用于验证题图、公式、表格筛选。' }
        } | ConvertTo-Json -Depth 10
        $rich = Invoke-RestMethod -Method Post -Uri "$apiUrl/questions" -ContentType 'application/json' -Body $richQuestionBody -TimeoutSec 10
        $createdQuestionIds += [string]$rich.id

        $plainQuestionBody = [ordered]@{
            subject = 'physics'
            stage = 'junior_middle_school'
            grade = 'grade_8'
            questionType = 'single_choice'
            defaultScore = 2
            difficultyEstimated = 0.32
            status = 'draft'
            primaryKnowledgeId = $knowledgeId
            blocks = @(
                [ordered]@{ blockType = 'text'; sortOrder = 0; content = [ordered]@{ text = 'NS601 普通检索题，不含公式、表格和题图。' }; sourceRegionId = $region.id }
            )
            assets = @()
            answer = [ordered]@{ value = 'B' }
            solution = [ordered]@{ text = '用于验证 hasFormula=false 等反向筛选。' }
        } | ConvertTo-Json -Depth 10
        $plain = Invoke-RestMethod -Method Post -Uri "$apiUrl/questions" -ContentType 'application/json' -Body $plainQuestionBody -TimeoutSec 10
        $createdQuestionIds += [string]$plain.id

        $defaultActive = Invoke-RestMethod -Method Get -Uri "$apiUrl/questions?subject=physics&stage=junior_middle_school&status=draft&knowledgeStatus=active&knowledgeVersion=1&sourceType=school_paper&page=1&limit=50" -TimeoutSec 10
        Assert-Condition ([string]$defaultActive.knowledgeStatus -eq 'active') 'NS601 default active search must report active knowledge status'
        Assert-Condition ([int]$defaultActive.knowledgeVersion -eq 1) 'NS601 default active search must report knowledge version 1'
        $richCard = Assert-ContainsQuestion -Search $defaultActive -QuestionId ([string]$rich.id) -Label 'default active search'
        $plainCard = Assert-ContainsQuestion -Search $defaultActive -QuestionId ([string]$plain.id) -Label 'default active search'
        Assert-Condition ([string]$richCard.primaryKnowledge.status -eq 'active') 'NS601 rich card must keep active knowledge reference'
        Assert-Condition ([int]$richCard.primaryKnowledge.version -eq 1) 'NS601 rich card must keep knowledge version reference'
        Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$richCard.preview)) 'NS601 rich card preview missing'
        Assert-Condition (@($richCard.sources.types) -contains 'school_paper') 'NS601 rich card source type summary missing'
        Assert-Condition ([bool]$richCard.hasFormula -and [bool]$richCard.hasTable -and [bool]$richCard.hasImage) 'NS601 rich card flags missing'
        Assert-Condition (-not [bool]$plainCard.hasFormula -and -not [bool]$plainCard.hasTable -and -not [bool]$plainCard.hasImage) 'NS601 plain card flags should be false'

        $baseUri = "$apiUrl/questions?subject=physics&stage=junior_middle_school&grade=grade_8&questionType=single_choice&status=draft&primaryKnowledgeId=$knowledgeId&sourceType=school_paper&page=1&limit=50"
        $difficultyHit = Invoke-RestMethod -Method Get -Uri "$baseUri&difficultyMin=0.5&difficultyMax=0.7" -TimeoutSec 10
        Assert-ContainsQuestion -Search $difficultyHit -QuestionId ([string]$rich.id) -Label 'difficulty filter' | Out-Null
        Assert-NotContainsQuestion -Search $difficultyHit -QuestionId ([string]$plain.id) -Label 'difficulty filter'

        $formulaHit = Invoke-RestMethod -Method Get -Uri "$baseUri&hasFormula=true" -TimeoutSec 10
        Assert-ContainsQuestion -Search $formulaHit -QuestionId ([string]$rich.id) -Label 'hasFormula=true filter' | Out-Null
        Assert-NotContainsQuestion -Search $formulaHit -QuestionId ([string]$plain.id) -Label 'hasFormula=true filter'

        $tableHit = Invoke-RestMethod -Method Get -Uri "$baseUri&hasTable=true" -TimeoutSec 10
        Assert-ContainsQuestion -Search $tableHit -QuestionId ([string]$rich.id) -Label 'hasTable=true filter' | Out-Null
        Assert-NotContainsQuestion -Search $tableHit -QuestionId ([string]$plain.id) -Label 'hasTable=true filter'

        $imageHit = Invoke-RestMethod -Method Get -Uri "$baseUri&hasImage=true" -TimeoutSec 10
        Assert-ContainsQuestion -Search $imageHit -QuestionId ([string]$rich.id) -Label 'hasImage=true filter' | Out-Null
        Assert-NotContainsQuestion -Search $imageHit -QuestionId ([string]$plain.id) -Label 'hasImage=true filter'

        $noFormulaHit = Invoke-RestMethod -Method Get -Uri "$baseUri&hasFormula=false&hasTable=false&hasImage=false" -TimeoutSec 10
        Assert-ContainsQuestion -Search $noFormulaHit -QuestionId ([string]$plain.id) -Label 'negative rich-media filter' | Out-Null
        Assert-NotContainsQuestion -Search $noFormulaHit -QuestionId ([string]$rich.id) -Label 'negative rich-media filter'

        $publishedMiss = Invoke-RestMethod -Method Get -Uri "$apiUrl/questions?subject=physics&stage=junior_middle_school&status=published&primaryKnowledgeId=$knowledgeId&sourceType=school_paper&page=1&limit=50" -TimeoutSec 10
        Assert-NotContainsQuestion -Search $publishedMiss -QuestionId ([string]$rich.id) -Label 'status=published miss filter'
        Assert-NotContainsQuestion -Search $publishedMiss -QuestionId ([string]$plain.id) -Label 'status=published miss filter'

        $report = [ordered]@{
            status = 'pass'
            taskId = 'NS601'
            checkedAt = (Get-Date).ToString('s')
            mode = 'question_search_api_runtime_filters_and_card_summary'
            productionEligible = $false
            queryReferenceProductionEligible = [bool]$ns501.queryReferenceProductionEligible
            externalAiCalls = 0
            realStudentDataUsed = $false
            dependency = [ordered]@{
                ns501 = 'docs/evidence/20260530-ns501-c002-active-boundary.json'
                api = 'apps/api/Program.cs:/questions'
            }
            activeVersionReference = [ordered]@{
                responseKnowledgeStatus = [string]$defaultActive.knowledgeStatus
                responseKnowledgeVersion = [int]$defaultActive.knowledgeVersion
                primaryKnowledgeId = [string]$richCard.primaryKnowledge.id
                primaryKnowledgeStatus = [string]$richCard.primaryKnowledge.status
                primaryKnowledgeVersion = [int]$richCard.primaryKnowledge.version
            }
            filtersVerified = [ordered]@{
                subject = 'physics'
                stage = 'junior_middle_school'
                grade = 'grade_8'
                questionType = 'single_choice'
                status = 'draft'
                primaryKnowledgeId = $knowledgeId
                knowledgeStatus = 'active'
                knowledgeVersion = 1
                difficultyRange = '0.5..0.7'
                sourceType = 'school_paper'
                hasFormula = $true
                hasTable = $true
                hasImage = $true
                negativeRichMediaFilter = $true
            }
            cards = [ordered]@{
                rich = [ordered]@{
                    id = [string]$rich.id
                    preview = [string]$richCard.preview
                    blockCount = [int]$richCard.blockCount
                    assetCount = [int]$richCard.assetCount
                    sourceTypes = @($richCard.sources.types)
                    hasFormula = [bool]$richCard.hasFormula
                    hasTable = [bool]$richCard.hasTable
                    hasImage = [bool]$richCard.hasImage
                }
                plain = [ordered]@{
                    id = [string]$plain.id
                    preview = [string]$plainCard.preview
                    blockCount = [int]$plainCard.blockCount
                    assetCount = [int]$plainCard.assetCount
                    sourceTypes = @($plainCard.sources.types)
                    hasFormula = [bool]$plainCard.hasFormula
                    hasTable = [bool]$plainCard.hasTable
                    hasImage = [bool]$plainCard.hasImage
                }
            }
            acceptance = [ordered]@{
                searchApiRuntimeReached = $true
                activeC002DefaultReferencePreserved = $true
                filtersCoverKnowledgeTypeDifficultySourceStatusAssets = $true
                cardSummaryIncludesPreviewSourcesFlagsAndVersion = $true
                candidateAssetsExcludedByDefault = [bool]$ns501.acceptance.candidateAssetsExcludedByDefault
                noExternalAiCall = $true
                noRealStudentData = $true
                real005StillNotClosed = $true
            }
            boundary = 'NS601 proves the question search API can filter by knowledge reference, question type, difficulty, source type, status, and rich-media flags, and returns question-card summaries with active version reference. This uses synthetic draft fixture questions, performs no production active switch, calls no external AI, uses no real student data, and does not close REAL005.'
            next = 'NS602 can continue question-card UI productization on top of the verified search API contract.'
            rollback = "delete from review_queue_items where payload->>'questionItemId' in ('$($rich.id)','$($plain.id)'); delete from question_assets where question_item_id in ('$($rich.id)','$($plain.id)'); delete from question_blocks where question_item_id in ('$($rich.id)','$($plain.id)'); delete from question_items where id in ('$($rich.id)','$($plain.id)'); delete from source_regions where source_document_id = '$($upload.sourceDocument.id)'; delete from source_documents where id = '$($upload.sourceDocument.id)'; delete from file_assets where id = '$($upload.id)'; git restore apps/api/Program.cs tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns601-question-search-api.ps1 docs/evidence/20260530-ns601-question-search-api-report.json"
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
        $env:PGPASSWORD = $previousPgPassword
    }
}
finally {
    Pop-Location
}

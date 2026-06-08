param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [int] $ApiPort = 0,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $ReportPath = 'docs/evidence/20260518-real009-table-structure-smoke-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for REAL009 table structure smoke'
}

function Write-PngFixture {
    param([Parameter(Mandatory = $true)][string] $RelativePath)
    $pngBytes = [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=')
    $fullPath = Join-Path $FileStoreRoot ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    New-Item -ItemType Directory -Path (Split-Path -Parent $fullPath) -Force | Out-Null
    [System.IO.File]::WriteAllBytes($fullPath, $pngBytes)
}

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

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
$logOut = Join-Path $repoRoot 'docs/evidence/real009-table-structure-api.out.log'
$logErr = Join-Path $repoRoot 'docs/evidence/real009-table-structure-api.err.log'
$previousConnectionString = $env:KQG_CONNECTION_STRING
$env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
$process = $null

try {
    Push-Location $repoRoot
    $process = Start-Process -FilePath dotnet -ArgumentList @(
        'run',
        '--project',
        'apps\api\K12QuestionGraph.Api.csproj',
        '-c',
        'Release',
        '--no-build',
        '--urls',
        $apiUrl
    ) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr

    $ready = $false
    for ($i = 0; $i -lt 180; $i++) {
        if ($process.HasExited) {
            throw "API exited before ready on $apiUrl; see $logOut and $logErr"
        }
        try {
            if ((Invoke-RestMethod -Uri "$apiUrl/health/ready" -TimeoutSec 2).status -eq 'ok') {
                $ready = $true
                break
            }
        }
        catch {}
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { throw "API did not become ready on $apiUrl; see $logOut and $logErr" }

    $sampleFile = Join-Path $env:TEMP "kqg-real009-$([Guid]::NewGuid().ToString('N')).txt"
    Set-Content -LiteralPath $sampleFile -Value 'REAL009 structured table source file' -Encoding UTF8
    $upload = curl.exe -s `
        -F "file=@$sampleFile;filename=real009-table.txt" `
        -F 'sourceType=school_paper' `
        -F 'sourceTitle=REAL009 Table Source' `
        -F 'ownerScope=school' `
        -F 'licenseOrPermission=internal_authorized' `
        -F 'sharingAllowed=true' `
        -F 'containsStudentPii=false' `
        -F 'anonymizationStatus=not_applicable' `
        "$apiUrl/files" | ConvertFrom-Json
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$upload.sourceDocument.id)) 'REAL009 upload did not return source document id'

    $stemScreenshot = "real009/table-structure/$([Guid]::NewGuid())-stem.png"
    $tableScreenshot = "real009/table-structure/$([Guid]::NewGuid())-table.png"
    Write-PngFixture -RelativePath $stemScreenshot
    Write-PngFixture -RelativePath $tableScreenshot

    $stemRegion = Invoke-RestMethod -Method Post -Uri "$apiUrl/source-documents/$($upload.sourceDocument.id)/regions" -ContentType 'application/json' -Body ([ordered]@{
        pageNumber = 1
        x = 6
        y = 10
        width = 76
        height = 14
        coordinateUnit = 'percent'
        screenshotRelativePath = $stemScreenshot
        regionType = 'question_stem'
    } | ConvertTo-Json) -TimeoutSec 10

    $tableRegion = Invoke-RestMethod -Method Post -Uri "$apiUrl/source-documents/$($upload.sourceDocument.id)/regions" -ContentType 'application/json' -Body ([ordered]@{
        pageNumber = 1
        x = 12
        y = 28
        width = 58
        height = 26
        coordinateUnit = 'percent'
        screenshotRelativePath = $tableScreenshot
        regionType = 'question_table'
    } | ConvertTo-Json) -TimeoutSec 10

    $psql = Join-Path $PgBin 'psql.exe'
    $activeKnowledgeId = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c "select id from knowledge_nodes where status='active' and version=1 order by created_at asc limit 1;"
    if ($LASTEXITCODE -ne 0) { throw 'REAL009 active knowledge query failed' }
    $activeKnowledgeId = (($activeKnowledgeId | Select-Object -First 1) ?? '').Trim()
    if ([string]::IsNullOrWhiteSpace($activeKnowledgeId)) {
        throw 'REAL009 requires at least one active v1 knowledge node'
    }

    $questionBody = [ordered]@{
        subject = 'physics'
        stage = 'junior_middle_school'
        grade = 'grade_9'
        questionType = 'experiment'
        defaultScore = 8
        difficultyEstimated = 0.66
        status = 'draft'
        primaryKnowledgeId = $activeKnowledgeId
        blocks = @(
            [ordered]@{
                blockType = 'text'
                sortOrder = 0
                content = [ordered]@{ text = 'REAL009 表格必须结构化入库，并保留来源截图。' }
                sourceRegionId = $stemRegion.id
            },
            [ordered]@{
                blockType = 'table'
                sortOrder = 1
                content = [ordered]@{
                    structureVersion = 'table.v1'
                    caption = 'REAL009 实验数据表'
                    columns = @('物理量', '数值', '单位')
                    rows = @(
                        @('电压', '3.0', 'V'),
                        @('电流', '0.20', 'A')
                    )
                    sourceRegionId = $tableRegion.id
                    confidence = 0.62
                    reviewStatus = 'pending_review'
                }
                sourceRegionId = $tableRegion.id
            }
        )
        assets = @()
        answer = [ordered]@{ value = '见表格数据' }
        solution = [ordered]@{ text = '表格以结构化 block 保存，来源截图用于核验。' }
    } | ConvertTo-Json -Depth 12

    $question = Invoke-RestMethod -Method Post -Uri "$apiUrl/questions" -ContentType 'application/json' -Body $questionBody -TimeoutSec 10
    $detail = Invoke-RestMethod -Uri "$apiUrl/questions/$($question.id)" -TimeoutSec 10
    $tableBlock = @($detail.blocks | Where-Object { $_.blockType -eq 'table' })[0]
    Assert-True ($null -ne $tableBlock) 'REAL009 table block missing from question detail'
    Assert-True ([string]$tableBlock.sourceRegionId -eq [string]$tableRegion.id) 'REAL009 table block sourceRegionId mismatch'
    Assert-True ([string]$tableBlock.content.caption -eq 'REAL009 实验数据表') 'REAL009 table caption missing'
    Assert-True (@($tableBlock.content.columns).Count -eq 3) 'REAL009 table columns missing'
    Assert-True (@($tableBlock.content.rows).Count -eq 2) 'REAL009 table rows missing'
    Assert-True ([double]$tableBlock.content.confidence -lt 0.8) 'REAL009 table confidence should be low for pending review'
    Assert-True ([string]$tableBlock.content.reviewStatus -eq 'pending_review') 'REAL009 table reviewStatus missing'

    $search = Invoke-RestMethod -Uri "$apiUrl/questions?subject=physics&stage=junior_middle_school&sourceType=school_paper&page=1&limit=50" -TimeoutSec 10
    $card = @($search.items | Where-Object { $_.id -eq $question.id })[0]
    Assert-True ($null -ne $card) 'REAL009 created question should be searchable with sourceType filter'
    Assert-True ([bool]$card.hasTable) 'REAL009 card.hasTable must come from table block'
    Assert-True (-not [bool]$card.hasImage) 'REAL009 table block must not be treated as image asset'

    $sources = Invoke-RestMethod -Uri "$apiUrl/questions/$($question.id)/sources" -TimeoutSec 10
    $tableSource = @($sources.sourceRegions | Where-Object { $_.id -eq $tableRegion.id })[0]
    Assert-True ($null -ne $tableSource) 'REAL009 source review must include table source region'
    Assert-True ([string]$tableSource.regionType -eq 'question_table') 'REAL009 table source region type mismatch'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$tableSource.screenshotUrl)) 'REAL009 table source screenshot URL missing'
    $imageResponse = Invoke-WebRequest -Uri "$apiUrl$($tableSource.screenshotUrl)" -TimeoutSec 10
    Assert-True ([int]$imageResponse.StatusCode -eq 200) 'REAL009 table screenshot endpoint must return 200'

    $queue = Invoke-RestMethod -Uri "$apiUrl/review-queue?status=open&reviewType=question_table_block_review&limit=100" -TimeoutSec 10
    $queueItem = @($queue.items | Where-Object { [string]$_.payload.questionItemId -eq [string]$question.id })[0]
    Assert-True ($null -ne $queueItem) 'REAL009 low confidence table must enter review queue'
    Assert-True ([string]$queueItem.requiredAction -eq 'review_table_structure') 'REAL009 table queue requiredAction mismatch'
    Assert-True ([string]$queueItem.reason -eq 'table_block_low_confidence_or_pending_review') 'REAL009 table queue reason mismatch'

    $report = [ordered]@{
        status = 'pass'
        task = 'REAL009'
        checkedAt = (Get-Date).ToString('s')
        requestedApiPort = $requestedApiPort
        resolvedApiPort = $ApiPort
        portFallbackApplied = ($requestedApiPort -ne $ApiPort)
        questionId = $question.id
        sourceDocumentId = $upload.sourceDocument.id
        tableBlockId = $tableBlock.id
        tableSourceRegionId = $tableRegion.id
        tableStructure = [ordered]@{
            caption = [string]$tableBlock.content.caption
            columnCount = @($tableBlock.content.columns).Count
            rowCount = @($tableBlock.content.rows).Count
            confidence = [double]$tableBlock.content.confidence
            reviewStatus = [string]$tableBlock.content.reviewStatus
            sourceRegionId = [string]$tableBlock.sourceRegionId
        }
        cardProbe = [ordered]@{
            hasTable = [bool]$card.hasTable
            hasImage = [bool]$card.hasImage
            assetCount = [int]$card.assetCount
        }
        sourceProbe = [ordered]@{
            sourceRegionCount = [int]$sources.sourceRegions.Count
            tableRegionType = [string]$tableSource.regionType
            tableScreenshotUrl = [string]$tableSource.screenshotUrl
            tableScreenshotStatusCode = [int]$imageResponse.StatusCode
        }
        reviewQueueProbe = [ordered]@{
            reviewType = [string]$queueItem.reviewType
            queueItemId = [string]$queueItem.id
            requiredAction = [string]$queueItem.requiredAction
            reason = [string]$queueItem.reason
            confidence = [double]$queueItem.confidence
        }
        rollback = "delete from review_queue_items where payload->>'questionItemId' = '$($question.id)'; delete from question_blocks where question_item_id = '$($question.id)'; delete from question_items where id = '$($question.id)';"
        summaryChinese = '表格已作为 QuestionBlock table 结构化保存，保留来源截图，低置信度进入人工审核队列，且不会被当成题图资产。'
    }
    $fullReportPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $fullReportPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $fullReportPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 10
}
finally {
    if ($null -ne $process) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    $env:KQG_CONNECTION_STRING = $previousConnectionString
    Pop-Location
}

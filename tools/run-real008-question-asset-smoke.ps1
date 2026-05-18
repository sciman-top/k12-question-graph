param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [int] $ApiPort = 5308,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $ReportPath = 'docs/evidence/20260518-real008-question-asset-smoke-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for REAL008 question asset smoke'
}

function Write-PngFixture {
    param(
        [Parameter(Mandatory = $true)][string] $RelativePath
    )

    $pngBytes = [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=')
    $fullPath = Join-Path $FileStoreRoot ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    New-Item -ItemType Directory -Path (Split-Path -Parent $fullPath) -Force | Out-Null
    [System.IO.File]::WriteAllBytes($fullPath, $pngBytes)
}

function Assert-True {
    param(
        [bool] $Condition,
        [string] $Message
    )
    if (-not $Condition) { throw $Message }
}

$apiUrl = "http://127.0.0.1:$ApiPort"
$logOut = Join-Path $repoRoot 'docs/evidence/real008-question-asset-api.out.log'
$logErr = Join-Path $repoRoot 'docs/evidence/real008-question-asset-api.err.log'
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

    $sampleFile = Join-Path $env:TEMP "kqg-real008-$([Guid]::NewGuid().ToString('N')).txt"
    Set-Content -LiteralPath $sampleFile -Value 'REAL008 question figure source file' -Encoding UTF8
    $upload = curl.exe -s `
        -F "file=@$sampleFile;filename=real008-question-asset.txt" `
        -F 'sourceType=school_paper' `
        -F 'sourceTitle=REAL008 Question Asset Source' `
        -F 'ownerScope=school' `
        -F 'licenseOrPermission=internal_authorized' `
        -F 'sharingAllowed=true' `
        -F 'containsStudentPii=false' `
        -F 'anonymizationStatus=not_applicable' `
        "$apiUrl/files" | ConvertFrom-Json
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$upload.id)) 'REAL008 upload did not return file asset id'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$upload.sourceDocument.id)) 'REAL008 upload did not return source document id'

    $stemScreenshot = "real008/question-assets/$([Guid]::NewGuid())-stem.png"
    $assetScreenshot = "real008/question-assets/$([Guid]::NewGuid())-figure.png"
    Write-PngFixture -RelativePath $stemScreenshot
    Write-PngFixture -RelativePath $assetScreenshot

    $stemRegionBody = [ordered]@{
        pageNumber = 1
        x = 8
        y = 12
        width = 62
        height = 18
        coordinateUnit = 'percent'
        screenshotRelativePath = $stemScreenshot
        regionType = 'question_stem'
    } | ConvertTo-Json
    $stemRegion = Invoke-RestMethod -Method Post -Uri "$apiUrl/source-documents/$($upload.sourceDocument.id)/regions" -ContentType 'application/json' -Body $stemRegionBody -TimeoutSec 10

    $assetRegionBody = [ordered]@{
        pageNumber = 1
        x = 18
        y = 34
        width = 28
        height = 20
        coordinateUnit = 'percent'
        screenshotRelativePath = $assetScreenshot
        regionType = 'question_asset'
    } | ConvertTo-Json
    $assetRegion = Invoke-RestMethod -Method Post -Uri "$apiUrl/source-documents/$($upload.sourceDocument.id)/regions" -ContentType 'application/json' -Body $assetRegionBody -TimeoutSec 10

    $psql = Join-Path $PgBin 'psql.exe'
    $activeKnowledgeId = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c "select id from knowledge_nodes where status='active' and version=1 order by created_at asc limit 1;"
    if ($LASTEXITCODE -ne 0) { throw 'REAL008 active knowledge query failed' }
    $activeKnowledgeId = (($activeKnowledgeId | Select-Object -First 1) ?? '').Trim()
    if ([string]::IsNullOrWhiteSpace($activeKnowledgeId)) {
        $newCode = "REAL008-ACTIVE-" + [Guid]::NewGuid().ToString('N').Substring(0, 8).ToUpperInvariant()
        $newId = [Guid]::NewGuid().ToString()
        & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c "insert into knowledge_nodes (id,subject,stage,code,title,node_type,level,status,version,metadata,created_at,updated_at) values ('$newId','physics','junior_middle_school','$newCode','REAL008 Active Seed','concept',2,'active',1,'{}',now(),now());"
        if ($LASTEXITCODE -ne 0) { throw 'REAL008 failed to seed active knowledge node' }
        $activeKnowledgeId = $newId
    }

    $questionBody = [ordered]@{
        subject = 'physics'
        stage = 'junior_middle_school'
        grade = 'grade_9'
        questionType = 'experiment'
        defaultScore = 6
        difficultyEstimated = 0.61
        status = 'draft'
        primaryKnowledgeId = $activeKnowledgeId
        blocks = @(
            [ordered]@{
                blockType = 'text'
                sortOrder = 0
                content = [ordered]@{ text = 'REAL008 题图资产必须由 question_assets 驱动，而不是仅靠来源截图误判。' }
                sourceRegionId = $stemRegion.id
            }
        )
        assets = @()
        answer = [ordered]@{ value = '见图分析' }
        solution = [ordered]@{ text = '先验证无题图，再关联、解除并重新关联题图。' }
    } | ConvertTo-Json -Depth 10
    $question = Invoke-RestMethod -Method Post -Uri "$apiUrl/questions" -ContentType 'application/json' -Body $questionBody -TimeoutSec 10

    $searchWithoutAsset = Invoke-RestMethod -Uri "$apiUrl/questions?subject=physics&stage=junior_middle_school&sourceType=school_paper&page=1&limit=50" -TimeoutSec 10
    $cardWithoutAsset = @($searchWithoutAsset.items | Where-Object { $_.id -eq $question.id })[0]
    Assert-True ($null -ne $cardWithoutAsset) 'REAL008 created question should be searchable before asset association'
    Assert-True (-not [bool]$cardWithoutAsset.hasImage) 'REAL008 card.hasImage must stay false before question_assets association'
    Assert-True ([int]$cardWithoutAsset.assetCount -eq 0) 'REAL008 assetCount must be 0 before association'

    $associateBody = [ordered]@{
        fileAssetId = $upload.id
        sourceRegionId = $assetRegion.id
        assetType = 'image'
        purpose = 'question_figure'
        metadata = [ordered]@{
            anchorBlockSortOrder = 0
            anchor = 'after_stem'
            associationMode = 'manual_api_smoke'
            sourceWorkflowKey = 'real008_question_asset_smoke'
        }
        reviewedBy = 'real008-smoke'
        reason = 'associate question figure to stem for REAL008'
    } | ConvertTo-Json -Depth 10
    $associated = Invoke-RestMethod -Method Post -Uri "$apiUrl/questions/$($question.id)/assets" -ContentType 'application/json' -Body $associateBody -TimeoutSec 10
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$associated.auditId)) 'REAL008 association audit id missing'

    $searchWithAsset = Invoke-RestMethod -Uri "$apiUrl/questions?subject=physics&stage=junior_middle_school&sourceType=school_paper&page=1&limit=50" -TimeoutSec 10
    $cardWithAsset = @($searchWithAsset.items | Where-Object { $_.id -eq $question.id })[0]
    Assert-True ([bool]$cardWithAsset.hasImage) 'REAL008 card.hasImage must come from question_assets after association'
    Assert-True ([int]$cardWithAsset.assetCount -eq 1) 'REAL008 assetCount must be 1 after association'

    $detailWithAsset = Invoke-RestMethod -Uri "$apiUrl/questions/$($question.id)" -TimeoutSec 10
    Assert-True ([int]$detailWithAsset.assets.Count -eq 1) 'REAL008 question detail must expose one QuestionAsset'
    Assert-True ([string]$detailWithAsset.assets[0].sourceRegionId -eq [string]$assetRegion.id) 'REAL008 detail asset sourceRegionId mismatch'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$detailWithAsset.assets[0].sourceRegionScreenshotUrl)) 'REAL008 detail asset screenshot URL missing'

    $sourcesWithAsset = Invoke-RestMethod -Uri "$apiUrl/questions/$($question.id)/sources" -TimeoutSec 10
    $sourceAssetRegion = @($sourcesWithAsset.sourceRegions | Where-Object { $_.id -eq $assetRegion.id })[0]
    Assert-True ($null -ne $sourceAssetRegion) 'REAL008 source review must include asset source region'
    Assert-True ([string]$sourceAssetRegion.regionType -eq 'question_asset') 'REAL008 asset source region type mismatch'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$sourceAssetRegion.screenshotUrl)) 'REAL008 asset source screenshot URL missing'
    $imageResponse = Invoke-WebRequest -Uri "$apiUrl$($sourceAssetRegion.screenshotUrl)" -TimeoutSec 10
    Assert-True ([int]$imageResponse.StatusCode -eq 200) 'REAL008 asset screenshot endpoint must return 200'

    $unlink = Invoke-RestMethod -Method Delete -Uri "$apiUrl/questions/$($question.id)/assets/$($associated.asset.id)?reviewedBy=real008-smoke&reason=unlink-for-regression" -TimeoutSec 10
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$unlink.auditId)) 'REAL008 unlink audit id missing'

    $searchAfterUnlink = Invoke-RestMethod -Uri "$apiUrl/questions?subject=physics&stage=junior_middle_school&sourceType=school_paper&page=1&limit=50" -TimeoutSec 10
    $cardAfterUnlink = @($searchAfterUnlink.items | Where-Object { $_.id -eq $question.id })[0]
    Assert-True (-not [bool]$cardAfterUnlink.hasImage) 'REAL008 card.hasImage must return false after unlink'
    Assert-True ([int]$cardAfterUnlink.assetCount -eq 0) 'REAL008 assetCount must return 0 after unlink'

    $reassociated = Invoke-RestMethod -Method Post -Uri "$apiUrl/questions/$($question.id)/assets" -ContentType 'application/json' -Body $associateBody -TimeoutSec 10
    $detailAfterReassociate = Invoke-RestMethod -Uri "$apiUrl/questions/$($question.id)" -TimeoutSec 10
    Assert-True ([int]$detailAfterReassociate.assets.Count -eq 1) 'REAL008 detail must expose one QuestionAsset after reassociation'

    $report = [ordered]@{
        status = 'pass'
        task = 'REAL008'
        checkedAt = (Get-Date).ToString('s')
        questionId = $question.id
        sourceDocumentId = $upload.sourceDocument.id
        stemSourceRegionId = $stemRegion.id
        assetSourceRegionId = $assetRegion.id
        cardProbe = [ordered]@{
            beforeAssociation = [ordered]@{
                hasImage = [bool]$cardWithoutAsset.hasImage
                assetCount = [int]$cardWithoutAsset.assetCount
                sourceScreenshotCount = [int]$cardWithoutAsset.sources.screenshotCount
            }
            afterAssociation = [ordered]@{
                hasImage = [bool]$cardWithAsset.hasImage
                assetCount = [int]$cardWithAsset.assetCount
                sourceScreenshotCount = [int]$cardWithAsset.sources.screenshotCount
            }
            afterUnlink = [ordered]@{
                hasImage = [bool]$cardAfterUnlink.hasImage
                assetCount = [int]$cardAfterUnlink.assetCount
                sourceScreenshotCount = [int]$cardAfterUnlink.sources.screenshotCount
            }
        }
        detailProbe = [ordered]@{
            assetCount = [int]$detailAfterReassociate.assets.Count
            assetType = [string]$detailAfterReassociate.assets[0].assetType
            purpose = [string]$detailAfterReassociate.assets[0].purpose
            sourceRegionScreenshotUrl = [string]$detailAfterReassociate.assets[0].sourceRegionScreenshotUrl
        }
        sourceProbe = [ordered]@{
            sourceRegionCount = [int]$sourcesWithAsset.sourceRegions.Count
            assetRegionType = [string]$sourceAssetRegion.regionType
            assetScreenshotUrl = [string]$sourceAssetRegion.screenshotUrl
            assetPageScreenshotUrl = [string]$sourceAssetRegion.pageScreenshotUrl
            assetScreenshotStatusCode = [int]$imageResponse.StatusCode
        }
        auditIds = [ordered]@{
            associate = $associated.auditId
            unlink = $unlink.auditId
            reassociate = $reassociated.auditId
        }
        rollback = "delete from question_assets where question_item_id = '$($question.id)'; delete from question_blocks where question_item_id = '$($question.id)'; delete from question_items where id = '$($question.id)';"
        summaryChinese = '题库卡片 hasImage/assetCount、题目详情题图和来源回看均已证明来自真实 QuestionAsset；关联、解除关联和重新关联均有 audit。'
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

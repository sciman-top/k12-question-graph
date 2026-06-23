param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [int] $ApiPort = 0,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $ReportPath = 'docs/evidence/20260518-real010-formula-fidelity-smoke-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for REAL010 formula fidelity smoke'
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
$logOut = Join-Path $repoRoot 'docs/evidence/real010-formula-fidelity-api.out.log'
$logErr = Join-Path $repoRoot 'docs/evidence/real010-formula-fidelity-api.err.log'
$previousConnectionString = $env:KQG_CONNECTION_STRING
$previousFileStoreRoot = $env:KqgPaths__FileStoreRoot
$env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
$env:KqgPaths__FileStoreRoot = $FileStoreRoot
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

    $sampleFile = Join-Path $env:TEMP "kqg-real010-$([Guid]::NewGuid().ToString('N')).txt"
    Set-Content -LiteralPath $sampleFile -Value 'REAL010 formula fidelity source file' -Encoding UTF8
    $upload = curl.exe -s `
        -F "file=@$sampleFile;filename=real010-formula.txt" `
        -F 'sourceType=school_paper' `
        -F 'sourceTitle=REAL010 Formula Source' `
        -F 'ownerScope=school' `
        -F 'licenseOrPermission=internal_authorized' `
        -F 'sharingAllowed=true' `
        -F 'containsStudentPii=false' `
        -F 'anonymizationStatus=not_applicable' `
        "$apiUrl/files" | ConvertFrom-Json
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$upload.sourceDocument.id)) 'REAL010 upload did not return source document id'

    $officeScreenshot = "real010/formula-fidelity/$([Guid]::NewGuid())-office.png"
    $scanScreenshot = "real010/formula-fidelity/$([Guid]::NewGuid())-scan.png"
    Write-PngFixture -RelativePath $officeScreenshot
    Write-PngFixture -RelativePath $scanScreenshot

    $officeRegion = Invoke-RestMethod -Method Post -Uri "$apiUrl/source-documents/$($upload.sourceDocument.id)/regions" -ContentType 'application/json' -Body ([ordered]@{
        pageNumber = 1
        x = 8
        y = 15
        width = 44
        height = 12
        coordinateUnit = 'percent'
        screenshotRelativePath = $officeScreenshot
        regionType = 'formula_omml'
    } | ConvertTo-Json) -TimeoutSec 10

    $scanRegion = Invoke-RestMethod -Method Post -Uri "$apiUrl/source-documents/$($upload.sourceDocument.id)/regions" -ContentType 'application/json' -Body ([ordered]@{
        pageNumber = 1
        x = 9
        y = 35
        width = 38
        height = 16
        coordinateUnit = 'percent'
        screenshotRelativePath = $scanScreenshot
        regionType = 'formula_scan_candidate'
    } | ConvertTo-Json) -TimeoutSec 10

    $psql = Join-Path $PgBin 'psql.exe'
    $activeKnowledgeId = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c "select id from knowledge_nodes where status='active' and version=1 order by created_at asc limit 1;"
    if ($LASTEXITCODE -ne 0) { throw 'REAL010 active knowledge query failed' }
    $activeKnowledgeId = (($activeKnowledgeId | Select-Object -First 1) ?? '').Trim()
    if ([string]::IsNullOrWhiteSpace($activeKnowledgeId)) {
        throw 'REAL010 requires at least one active v1 knowledge node'
    }

    $omml = '<m:oMath xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"><m:r><m:t>F=ma</m:t></m:r></m:oMath>'
    $questionBody = [ordered]@{
        subject = 'physics'
        stage = 'junior_middle_school'
        grade = 'grade_9'
        questionType = 'calculation'
        defaultScore = 6
        difficultyEstimated = 0.7
        status = 'draft'
        primaryKnowledgeId = $activeKnowledgeId
        blocks = @(
            [ordered]@{
                blockType = 'text'
                sortOrder = 0
                content = [ordered]@{ text = 'REAL010 公式保真：Office 公式优先 OMML，扫描公式进入审核。' }
                sourceRegionId = $officeRegion.id
            },
            [ordered]@{
                blockType = 'formula'
                sortOrder = 1
                content = [ordered]@{
                    sourceFormat = 'omml'
                    omml = $omml
                    latex = 'F=ma'
                    mathml = '<math><mi>F</mi><mo>=</mo><mi>m</mi><mi>a</mi></math>'
                    confidence = 1.0
                    reviewStatus = 'verified'
                    exportPreference = 'omml'
                    displayPreference = 'katex'
                }
                sourceRegionId = $officeRegion.id
            },
            [ordered]@{
                blockType = 'formula'
                sortOrder = 2
                content = [ordered]@{
                    sourceFormat = 'scanned_formula_candidate'
                    latex = 'R=U/I'
                    mathml = ''
                    confidence = 0.56
                    reviewStatus = 'pending_review'
                    fallbackImageSourceRegionId = $scanRegion.id
                    fallbackImageUrl = "/source-regions/$($scanRegion.id)/screenshot"
                    recognitionEngine = 'manual_fixture'
                }
                sourceRegionId = $scanRegion.id
            }
        )
        assets = @(
            [ordered]@{
                fileAssetId = $upload.id
                sourceRegionId = $scanRegion.id
                assetType = 'formula'
                purpose = 'formula_fallback_image'
                metadata = [ordered]@{
                    sourceWorkflowKey = 'real010_formula_fidelity'
                    reviewStatus = 'pending_review'
                    confidence = 0.56
                }
            }
        )
        answer = [ordered]@{ value = 'F=ma；R=U/I 待人工确认' }
        solution = [ordered]@{ text = 'Office 原生公式保留 OMML；扫描公式只作为候选。' }
    } | ConvertTo-Json -Depth 14

    $question = Invoke-RestMethod -Method Post -Uri "$apiUrl/questions" -ContentType 'application/json' -Body $questionBody -TimeoutSec 10
    $detail = Invoke-RestMethod -Uri "$apiUrl/questions/$($question.id)" -TimeoutSec 10
    $formulaBlocks = @($detail.blocks | Where-Object { $_.blockType -eq 'formula' } | Sort-Object sortOrder)
    Assert-True (@($formulaBlocks).Count -eq 2) 'REAL010 detail must expose two formula blocks'

    $officeFormula = $formulaBlocks[0]
    Assert-True ([string]$officeFormula.content.sourceFormat -eq 'omml') 'REAL010 office formula sourceFormat must be OMML'
    Assert-True ([string]$officeFormula.content.omml -like '*m:oMath*') 'REAL010 office formula OMML payload missing'
    Assert-True ([string]$officeFormula.content.latex -eq 'F=ma') 'REAL010 office formula LaTeX derivative missing'
    Assert-True ([string]$officeFormula.content.mathml -like '*math*') 'REAL010 office formula MathML derivative missing'
    Assert-True ([string]$officeFormula.content.exportPreference -eq 'omml') 'REAL010 office formula export preference must be OMML'

    $scanFormula = $formulaBlocks[1]
    Assert-True ([string]$scanFormula.content.sourceFormat -eq 'scanned_formula_candidate') 'REAL010 scan formula source format mismatch'
    Assert-True ([double]$scanFormula.content.confidence -lt 0.9) 'REAL010 scanned formula confidence should be low'
    Assert-True ([string]$scanFormula.content.reviewStatus -eq 'pending_review') 'REAL010 scanned formula must be pending_review'
    Assert-True ([string]$scanFormula.content.fallbackImageUrl -like '/source-regions/*/screenshot') 'REAL010 scanned formula fallback image URL missing'

    $search = Invoke-RestMethod -Uri "$apiUrl/questions?subject=physics&stage=junior_middle_school&sourceType=school_paper&page=1&limit=50" -TimeoutSec 10
    $card = @($search.items | Where-Object { $_.id -eq $question.id })[0]
    Assert-True ($null -ne $card) 'REAL010 created question should be searchable with sourceType filter'
    Assert-True ([bool]$card.hasFormula) 'REAL010 card.hasFormula must come from formula blocks'
    Assert-True (-not [bool]$card.hasImage) 'REAL010 formula fallback asset must not be treated as question image'

    $sources = Invoke-RestMethod -Uri "$apiUrl/questions/$($question.id)/sources" -TimeoutSec 10
    $scanSource = @($sources.sourceRegions | Where-Object { $_.id -eq $scanRegion.id })[0]
    Assert-True ($null -ne $scanSource) 'REAL010 source review must include scanned formula source region'
    Assert-True ([string]$scanSource.regionType -eq 'formula_scan_candidate') 'REAL010 scanned formula source region type mismatch'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$scanSource.screenshotUrl)) 'REAL010 scanned formula screenshot URL missing'
    $imageResponse = Invoke-WebRequest -Uri "$apiUrl$($scanSource.screenshotUrl)" -TimeoutSec 10
    Assert-True ([int]$imageResponse.StatusCode -eq 200) 'REAL010 scanned formula fallback image must return 200'

    $queue = Invoke-RestMethod -Uri "$apiUrl/review-queue?status=open&reviewType=question_formula_block_review&limit=100" -TimeoutSec 10
    $queueItems = @($queue.items | Where-Object { [string]$_.payload.questionItemId -eq [string]$question.id })
    Assert-True (@($queueItems).Count -eq 1) 'REAL010 should queue exactly one scanned formula review item'
    Assert-True ([string]$queueItems[0].payload.sourceFormat -eq 'scanned_formula_candidate') 'REAL010 queued formula source format mismatch'
    Assert-True ([string]$queueItems[0].requiredAction -eq 'review_formula_structure') 'REAL010 formula queue requiredAction mismatch'

    $report = [ordered]@{
        status = 'pass'
        task = 'REAL010'
        checkedAt = (Get-Date).ToString('s')
        requestedApiPort = $requestedApiPort
        resolvedApiPort = $ApiPort
        portFallbackApplied = ($requestedApiPort -ne $ApiPort)
        questionId = $question.id
        sourceDocumentId = $upload.sourceDocument.id
        officeFormula = [ordered]@{
            blockId = [string]$officeFormula.id
            sourceFormat = [string]$officeFormula.content.sourceFormat
            ommlPreserved = ([string]$officeFormula.content.omml).Contains('m:oMath')
            latex = [string]$officeFormula.content.latex
            mathmlPresent = -not [string]::IsNullOrWhiteSpace([string]$officeFormula.content.mathml)
            exportPreference = [string]$officeFormula.content.exportPreference
            reviewStatus = [string]$officeFormula.content.reviewStatus
        }
        scannedFormula = [ordered]@{
            blockId = [string]$scanFormula.id
            sourceFormat = [string]$scanFormula.content.sourceFormat
            confidence = [double]$scanFormula.content.confidence
            reviewStatus = [string]$scanFormula.content.reviewStatus
            fallbackImageUrl = [string]$scanFormula.content.fallbackImageUrl
            fallbackImageStatusCode = [int]$imageResponse.StatusCode
        }
        cardProbe = [ordered]@{
            hasFormula = [bool]$card.hasFormula
            hasImage = [bool]$card.hasImage
            assetCount = [int]$card.assetCount
        }
        reviewQueueProbe = [ordered]@{
            reviewType = [string]$queueItems[0].reviewType
            queueItemId = [string]$queueItems[0].id
            requiredAction = [string]$queueItems[0].requiredAction
            reason = [string]$queueItems[0].reason
            confidence = [double]$queueItems[0].confidence
        }
        rollback = "delete from review_queue_items where payload->>'questionItemId' = '$($question.id)'; delete from question_assets where question_item_id = '$($question.id)'; delete from question_blocks where question_item_id = '$($question.id)'; delete from question_items where id = '$($question.id)';"
        summaryChinese = 'Office 原生公式以 OMML 为第一真源，LaTeX/MathML 只作为派生；扫描公式保留 fallback 图并进入人工审核队列。'
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
    $env:KqgPaths__FileStoreRoot = $previousFileStoreRoot
    Pop-Location
}

param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [int] $ApiPort = 0,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $ReportPath = 'docs/evidence/20260518-real011-question-edit-smoke-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for REAL011 question edit smoke'
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
$logOut = Join-Path $repoRoot 'docs/evidence/real011-question-edit-api.out.log'
$logErr = Join-Path $repoRoot 'docs/evidence/real011-question-edit-api.err.log'
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

    $sampleFile = Join-Path $env:TEMP "kqg-real011-$([Guid]::NewGuid().ToString('N')).txt"
    Set-Content -LiteralPath $sampleFile -Value 'REAL011 editable question source file' -Encoding UTF8
    $upload = curl.exe -s `
        -F "file=@$sampleFile;filename=real011-question-edit.txt" `
        -F 'sourceType=school_paper' `
        -F 'sourceTitle=REAL011 Question Edit Source' `
        -F 'ownerScope=school' `
        -F 'licenseOrPermission=internal_authorized' `
        -F 'sharingAllowed=true' `
        -F 'containsStudentPii=false' `
        -F 'anonymizationStatus=not_applicable' `
        "$apiUrl/files" | ConvertFrom-Json
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$upload.sourceDocument.id)) 'REAL011 upload did not return source document id'

    $screenshot = "real011/question-edit/$([Guid]::NewGuid())-stem.png"
    Write-PngFixture -RelativePath $screenshot
    $region = Invoke-RestMethod -Method Post -Uri "$apiUrl/source-documents/$($upload.sourceDocument.id)/regions" -ContentType 'application/json' -Body ([ordered]@{
        pageNumber = 1
        x = 9
        y = 14
        width = 65
        height = 20
        coordinateUnit = 'percent'
        screenshotRelativePath = $screenshot
        regionType = 'question_stem'
    } | ConvertTo-Json) -TimeoutSec 10

    $psql = Join-Path $PgBin 'psql.exe'
    $activeKnowledgeId = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c "select id from knowledge_nodes where status='active' and version=1 order by created_at asc limit 1;"
    if ($LASTEXITCODE -ne 0) { throw 'REAL011 active knowledge query failed' }
    $activeKnowledgeId = (($activeKnowledgeId | Select-Object -First 1) ?? '').Trim()
    if ([string]::IsNullOrWhiteSpace($activeKnowledgeId)) {
        throw 'REAL011 requires at least one active v1 knowledge node'
    }

    $questionBody = [ordered]@{
        subject = 'physics'
        stage = 'junior_middle_school'
        grade = 'grade_9'
        questionType = 'short_answer'
        defaultScore = 4
        difficultyEstimated = 0.52
        status = 'draft'
        primaryKnowledgeId = $activeKnowledgeId
        blocks = @(
            [ordered]@{
                blockType = 'text'
                sortOrder = 0
                content = [ordered]@{ text = 'REAL011 原始题干，等待教师修订。' }
                sourceRegionId = $region.id
            }
        )
        assets = @()
        answer = [ordered]@{ value = '原答案' }
        solution = [ordered]@{ text = '原解析' }
    } | ConvertTo-Json -Depth 10
    $question = Invoke-RestMethod -Method Post -Uri "$apiUrl/questions" -ContentType 'application/json' -Body $questionBody -TimeoutSec 10
    $blockId = [string]$question.blocks[0].id

    $regionPatch = [ordered]@{
        x = 11
        y = 16
        width = 58
        height = 18
        regionType = 'question_stem_revised'
        reviewedBy = 'real011-smoke'
        reason = 're-crop stem bbox during abnormal question edit'
    } | ConvertTo-Json -Depth 5
    $regionRevision = Invoke-RestMethod -Method Patch -Uri "$apiUrl/source-regions/$($region.id)" -ContentType 'application/json' -Body $regionPatch -TimeoutSec 10
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$regionRevision.auditId)) 'REAL011 source region revision audit missing'

    $questionPatch = [ordered]@{
        questionType = 'calculation'
        defaultScore = 6
        difficultyEstimated = 0.74
        status = 'pending_review'
        blocks = @(
            [ordered]@{
                id = $blockId
                blockType = 'text'
                sortOrder = 0
                content = [ordered]@{ text = 'REAL011 修订后题干：已调整题干、分值、难度和来源框。' }
                sourceRegionId = $region.id
            },
            [ordered]@{
                blockType = 'solution'
                sortOrder = 1
                content = [ordered]@{ text = '新增解析块，保留审核记录。' }
                sourceRegionId = $region.id
            }
        )
        answer = [ordered]@{ value = '修订答案' }
        solution = [ordered]@{ text = '修订解析' }
        reviewedBy = 'real011-smoke'
        reason = 'teacher abnormal question correction'
    } | ConvertTo-Json -Depth 10
    $questionRevision = Invoke-RestMethod -Method Patch -Uri "$apiUrl/questions/$($question.id)" -ContentType 'application/json' -Body $questionPatch -TimeoutSec 10
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$questionRevision.auditId)) 'REAL011 question revision audit missing'

    $detail = Invoke-RestMethod -Uri "$apiUrl/questions/$($question.id)" -TimeoutSec 10
    $editedStem = @($detail.blocks | Where-Object { $_.id -eq $blockId })[0]
    Assert-True ([string]$detail.questionType -eq 'calculation') 'REAL011 questionType not updated'
    Assert-True ([double]$detail.defaultScore -eq 6) 'REAL011 defaultScore not updated'
    Assert-True ([string]$detail.status -eq 'pending_review') 'REAL011 status not updated'
    Assert-True ([string]$editedStem.content.text -like 'REAL011 修订后题干*') 'REAL011 stem content not updated'
    Assert-True (@($detail.blocks | Where-Object { $_.blockType -eq 'solution' }).Count -eq 1) 'REAL011 solution block not added'
    Assert-True ([string]$detail.customFields.answer.value -eq '修订答案') 'REAL011 answer not updated'
    Assert-True ([string]$detail.customFields.solution.text -eq '修订解析') 'REAL011 solution custom field not updated'

    $questionAudits = Invoke-RestMethod -Uri "$apiUrl/review-queue?status=resolved&reviewType=question_revision&limit=100" -TimeoutSec 10
    $questionAudit = @($questionAudits.items | Where-Object { [string]$_.payload.questionItemId -eq [string]$question.id })[0]
    Assert-True ($null -ne $questionAudit) 'REAL011 question_revision audit not queryable'
    Assert-True ([string]$questionAudit.payload.reviewAudit.decision -eq 'question_updated') 'REAL011 question audit decision mismatch'

    $sourceAudits = Invoke-RestMethod -Uri "$apiUrl/review-queue?status=resolved&reviewType=source_region_revision&limit=100" -TimeoutSec 10
    $sourceAudit = @($sourceAudits.items | Where-Object { [string]$_.payload.sourceRegionId -eq [string]$region.id })[0]
    Assert-True ($null -ne $sourceAudit) 'REAL011 source_region_revision audit not queryable'

    $report = [ordered]@{
        status = 'pass'
        task = 'REAL011'
        checkedAt = (Get-Date).ToString('s')
        questionId = $question.id
        sourceRegionId = $region.id
        questionEdit = [ordered]@{
            questionType = [string]$detail.questionType
            defaultScore = [double]$detail.defaultScore
            difficultyEstimated = [double]$detail.difficultyEstimated
            status = [string]$detail.status
            editedStem = [string]$editedStem.content.text
            answer = [string]$detail.customFields.answer.value
            solution = [string]$detail.customFields.solution.text
            blockCount = @($detail.blocks).Count
        }
        sourceRegionEdit = [ordered]@{
            auditId = [string]$regionRevision.auditId
            regionType = [string]$regionRevision.region.regionType
            x = [double]$regionRevision.region.x
            y = [double]$regionRevision.region.y
            width = [double]$regionRevision.region.width
            height = [double]$regionRevision.region.height
        }
        auditProbe = [ordered]@{
            questionRevisionAuditId = [string]$questionRevision.auditId
            questionAuditDecision = [string]$questionAudit.payload.reviewAudit.decision
            sourceRegionAuditId = [string]$regionRevision.auditId
        }
        rollback = "delete from review_queue_items where payload->>'questionItemId' = '$($question.id)' or payload->>'sourceRegionId' = '$($region.id)'; delete from question_blocks where question_item_id = '$($question.id)'; delete from question_items where id = '$($question.id)';"
        summaryChinese = '题干、答案、解析、题型、分值、难度和 SourceRegion bbox 均可修订，且题目与来源框修订都有 audit。'
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

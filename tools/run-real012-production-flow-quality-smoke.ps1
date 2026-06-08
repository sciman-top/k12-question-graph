param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [int] $ApiPort = 0,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $OutputRoot = 'tmp\real012-paper-artifacts',
    [string] $ReportPath = 'docs/evidence/20260518-real012-production-flow-quality-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for REAL012 production flow quality smoke'
}

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-ScalarSql([string] $Sql) {
    $psql = Join-Path $PgBin 'psql.exe'
    $value = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c $Sql
    if ($LASTEXITCODE -ne 0) { throw "REAL012 SQL failed: $Sql" }
    return (($value | Select-Object -First 1) ?? '').Trim()
}

function Get-ActiveKnowledgeId {
    $knowledgeId = Invoke-ScalarSql "select id from knowledge_nodes where status='active' and version=1 order by created_at asc limit 1;"
    if (-not [string]::IsNullOrWhiteSpace($knowledgeId)) {
        return $knowledgeId
    }

    $newId = [Guid]::NewGuid().ToString()
    $code = 'REAL012-ACTIVE-' + [Guid]::NewGuid().ToString('N').Substring(0, 8).ToUpperInvariant()
    Invoke-ScalarSql "insert into knowledge_nodes (id,subject,stage,code,title,node_type,level,status,version,metadata,created_at,updated_at) values ('$newId','physics','junior_middle_school','$code','REAL012 Active Seed','concept',2,'active',1,'{""task"":""REAL012""}',now(),now()) returning id;" | Out-Null
    return $newId
}

function Test-CustomFieldValue([object] $Container, [string] $FieldName) {
    if ($null -eq $Container) { return $false }
    $field = $Container.PSObject.Properties[$FieldName]
    if ($null -eq $field -or $null -eq $field.Value) { return $false }
    if ($field.Value -is [string]) { return -not [string]::IsNullOrWhiteSpace($field.Value) }
    return @($field.Value.PSObject.Properties).Count -gt 0
}

function Get-CustomText([object] $Container, [string] $FieldName, [string] $PropertyName) {
    if ($null -eq $Container) { return '' }
    $field = $Container.PSObject.Properties[$FieldName]
    if ($null -eq $field -or $null -eq $field.Value) { return '' }
    $property = $field.Value.PSObject.Properties[$PropertyName]
    if ($null -eq $property -or $null -eq $property.Value) { return '' }
    return [string]$property.Value
}

function ConvertTo-QuestionArtifact([object] $Detail, [object] $Card, [int] $QuestionNo, [decimal] $Score) {
    [ordered]@{
        questionItemId = [string]$Detail.id
        questionNo = $QuestionNo
        score = $Score
        title = if ([string]::IsNullOrWhiteSpace([string]$Card.preview)) { "2015 广州真卷第 $QuestionNo 题" } else { [string]$Card.preview }
        blocks = @($Detail.blocks)
        hasImage = (@($Detail.assets).Count -gt 0)
        answer = Get-CustomText -Container $Detail.customFields -FieldName 'answer' -PropertyName 'value'
        solution = Get-CustomText -Container $Detail.customFields -FieldName 'solution' -PropertyName 'text'
        sourceAuthorizationStatus = 'authorized'
        knowledgeVersionStatus = 'active'
        knowledgeVersion = 1
    }
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
$logOut = Join-Path $repoRoot 'docs/evidence/real012-production-flow-api.out.log'
$logErr = Join-Path $repoRoot 'docs/evidence/real012-production-flow-api.err.log'
$previousConnectionString = $env:KQG_CONNECTION_STRING
$env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
$process = $null

try {
    Push-Location $repoRoot

    & pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-guangzhou-2015-real-ingest-slice.ps1 `
        -DatabaseName $DatabaseName `
        -DatabaseUser $DatabaseUser `
        -DatabaseHost $DatabaseHost `
        -DatabasePort $DatabasePort `
        -DatabasePassword $DatabasePassword `
        -FileStoreRoot $FileStoreRoot `
        -Apply | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'REAL012 setup failed while applying Guangzhou 2015 ingest state' }

    & pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-guangzhou-2015-visual-region-slice.ps1 `
        -DatabaseName $DatabaseName `
        -DatabaseUser $DatabaseUser `
        -DatabaseHost $DatabaseHost `
        -DatabasePort $DatabasePort `
        -DatabasePassword $DatabasePassword `
        -FileStoreRoot $FileStoreRoot `
        -Apply | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'REAL012 setup failed while applying Guangzhou 2015 visual region state' }

    & pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-guangzhou-2015-source-region-screenshots.ps1 `
        -DatabaseName $DatabaseName `
        -DatabaseUser $DatabaseUser `
        -DatabaseHost $DatabaseHost `
        -DatabasePort $DatabasePort `
        -DatabasePassword $DatabasePassword `
        -FileStoreRoot $FileStoreRoot `
        -Apply | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'REAL012 setup failed while generating source region screenshots' }

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

    $queue = Invoke-RestMethod -Uri "$apiUrl/review-queue?status=open&reviewType=guangzhou_2015_question_review&sortBy=question_no&order=asc&limit=50" -TimeoutSec 10
    $queueItems = @($queue.items)
    Assert-True ($queueItems.Count -eq 24) "REAL012 expects 24 Guangzhou 2015 review items, got $($queueItems.Count)"
    $sourceDocumentId = [string]$queueItems[0].payload.sourceDocumentId
    Assert-True (-not [string]::IsNullOrWhiteSpace($sourceDocumentId)) 'REAL012 review payload missing sourceDocumentId'

    $activeKnowledgeId = Get-ActiveKnowledgeId
    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($item in $queueItems) {
        $detail = Invoke-RestMethod -Uri "$apiUrl/questions/$($item.payload.questionItemId)" -TimeoutSec 10
        if (@($detail.assets).Count -lt 1) { continue }
        if (-not (Test-CustomFieldValue -Container $detail.customFields -FieldName 'answer')) { continue }
        if (-not (Test-CustomFieldValue -Container $detail.customFields -FieldName 'solution')) { continue }
        $candidates.Add([pscustomobject]@{
            queueItem = $item
            detail = $detail
            questionNo = [int]$item.payload.questionNo
        })
        if ($candidates.Count -ge 3) { break }
    }
    Assert-True ($candidates.Count -ge 3) "REAL012 requires at least 3 real questions with image answer and solution, got $($candidates.Count)"

    $authorizedSourceDocumentIds = New-Object System.Collections.Generic.HashSet[string]
    $promoted = @()
    foreach ($candidate in $candidates) {
        $sources = Invoke-RestMethod -Uri "$apiUrl/questions/$($candidate.detail.id)/sources" -TimeoutSec 10
        foreach ($sourceId in @($sources.sourceRegions | ForEach-Object { [string]$_.sourceDocumentId } | Select-Object -Unique)) {
            if ($authorizedSourceDocumentIds.Add($sourceId)) {
                $authorizationBody = [ordered]@{
                    licenseOrPermission = 'internal_authorized'
                    sharingAllowed = $true
                    containsStudentPii = $false
                    anonymizationStatus = 'not_applicable'
                    externalAiAllowed = $false
                    mayUseForKnowledgeExtraction = $true
                    mayUseForExamPointExtraction = $true
                    mayUseForTrendAnalysis = $false
                    reviewedBy = 'real012-smoke'
                    reason = 'authorize reviewed real question sample for draft export preflight smoke'
                } | ConvertTo-Json -Depth 5
                Invoke-RestMethod -Method Patch -Uri "$apiUrl/source-documents/$sourceId/authorization" -ContentType 'application/json' -Body $authorizationBody -TimeoutSec 10 | Out-Null
            }
        }

        $score = if ($null -eq $candidate.detail.defaultScore) { 3 } else { [decimal]$candidate.detail.defaultScore }
        $difficulty = if ($null -eq $candidate.detail.difficultyEstimated) { 0.62 } else { [double]$candidate.detail.difficultyEstimated }
        $questionPatch = [ordered]@{
            status = 'usable'
            primaryKnowledgeId = $activeKnowledgeId
            defaultScore = $score
            difficultyEstimated = $difficulty
            reviewedBy = 'real012-smoke'
            reason = 'promote reviewed Guangzhou 2015 real question into searchable paper and analysis smoke'
        } | ConvertTo-Json -Depth 8
        $revision = Invoke-RestMethod -Method Patch -Uri "$apiUrl/questions/$($candidate.detail.id)" -ContentType 'application/json' -Body $questionPatch -TimeoutSec 10
        $promoted += [ordered]@{
            questionItemId = [string]$candidate.detail.id
            questionNo = [int]$candidate.questionNo
            auditId = [string]$revision.auditId
            status = [string]$revision.question.status
            primaryKnowledgeId = [string]$revision.question.primaryKnowledgeId
        }
    }

    $search = Invoke-RestMethod -Uri "$apiUrl/questions?subject=physics&stage=junior_middle_school&status=usable&sourceType=local_exam_paper&sortBy=question_no&order=asc&page=1&limit=50" -TimeoutSec 10
    $selectedIds = @($promoted | ForEach-Object { [string]$_.questionItemId })
    $cards = @($search.items | Where-Object { $selectedIds -contains [string]$_.id } | Sort-Object questionNo)
    Assert-True ($cards.Count -eq $promoted.Count) 'REAL012 promoted real questions must be searchable'
    $cardQuestionNos = @($cards | ForEach-Object { [int]$_.questionNo })
    Assert-True (($cardQuestionNos -join ',') -eq (($cardQuestionNos | Sort-Object) -join ',')) 'REAL012 search cards must preserve question number order'
    Assert-True (@($cards | Where-Object { -not $_.hasImage }).Count -eq 0) 'REAL012 selected real search cards must expose hasImage'

    $basketItems = @()
    $questionArtifacts = @()
    $sortOrder = 0
    foreach ($card in $cards) {
        $detail = Invoke-RestMethod -Uri "$apiUrl/questions/$($card.id)" -TimeoutSec 10
        $score = if ($null -eq $detail.defaultScore) { 3 } else { [decimal]$detail.defaultScore }
        $basketItems += [ordered]@{
            questionItemId = [string]$detail.id
            sectionNo = 1
            questionNo = [int]$card.questionNo
            subQuestionNo = $null
            score = $score
            sortOrder = $sortOrder
        }
        $questionArtifacts += ConvertTo-QuestionArtifact -Detail $detail -Card $card -QuestionNo ([int]$card.questionNo) -Score $score
        $sortOrder += 1
    }

    $basketBody = [ordered]@{
        title = 'REAL012 2015 广州真题抽样组卷'
        subject = 'physics'
        stage = 'junior_middle_school'
        grade = 'grade_9'
        knowledgeVersionStatus = 'active'
        knowledgeVersion = 1
        items = $basketItems
    } | ConvertTo-Json -Depth 10
    $basket = Invoke-RestMethod -Method Post -Uri "$apiUrl/paper-baskets" -ContentType 'application/json' -Body $basketBody -TimeoutSec 10
    Assert-True (@($basket.items).Count -eq $basketItems.Count) 'REAL012 paper basket item count mismatch'

    $preflight = Invoke-RestMethod -Method Post -Uri "$apiUrl/paper-baskets/$($basket.id)/export-preflight" -ContentType 'application/json' -Body (@{ exportFormat = 'docx' } | ConvertTo-Json) -TimeoutSec 10
    Assert-True ([string]$preflight.status -eq 'ready_for_review') "REAL012 export preflight should be ready_for_review, got $($preflight.status)"
    Assert-True ([int]$preflight.summary.imageReadyCount -eq $basketItems.Count) 'REAL012 export preflight image count mismatch'
    Assert-True ([int]$preflight.summary.answerReadyCount -eq $basketItems.Count) 'REAL012 export preflight answer count mismatch'
    Assert-True ([int]$preflight.summary.solutionReadyCount -eq $basketItems.Count) 'REAL012 export preflight solution count mismatch'
    Assert-True ([int]$preflight.summary.authorizedSourceCount -eq $basketItems.Count) 'REAL012 export preflight source authorization count mismatch'
    Assert-True ([int]$preflight.summary.activeKnowledgeVersionCount -eq $basketItems.Count) 'REAL012 export preflight knowledge version count mismatch'

    $artifactInputPath = Join-Path $repoRoot (Join-Path $OutputRoot 'real012-paper-input.json')
    New-Item -ItemType Directory -Path (Split-Path -Parent $artifactInputPath) -Force | Out-Null
    $artifactInput = [ordered]@{
        taskId = 'REAL012'
        paperBasketId = [string]$basket.id
        basketTitle = [string]$basket.title
        preflight = $preflight
        questions = $questionArtifacts
    }
    $artifactInput | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $artifactInputPath -Encoding UTF8
    $artifactReportPath = 'docs/evidence/20260518-real012-word-pdf-artifact-report.json'
    python tools/s010b_paper_artifact_chain.py --input $artifactInputPath --output-root $OutputRoot --report $artifactReportPath | Write-Host
    if ($LASTEXITCODE -ne 0) { throw 'REAL012 Word/PDF artifact generation failed' }
    $artifactReport = Get-Content -LiteralPath (Join-Path $repoRoot $artifactReportPath) -Raw | ConvertFrom-Json
    Assert-True ([string]$artifactReport.status -eq 'pass') 'REAL012 artifact report did not pass'

    $fieldMapping = [ordered]@{
        studentKey = 'student_code'
        totalScore = 'total_score'
        itemScores = @{}
    }
    $itemMaxScores = @{}
    $row1 = @{ student_code = 'SYN-REAL012-001'; total_score = '0' }
    $row2 = @{ student_code = 'SYN-REAL012-002'; total_score = '0' }
    $total = 0
    foreach ($item in $basketItems) {
        $field = "q$($item.questionNo)_score"
        $qKey = "Q$($item.questionNo)"
        $fieldMapping.itemScores[$qKey] = $field
        $itemMaxScores[$qKey] = [decimal]$item.score
        $row1[$field] = [string]([Math]::Max(0, [decimal]$item.score - 1))
        $row2[$field] = [string]([Math]::Max(0, [decimal]$item.score - 2))
        $total += [decimal]$item.score
    }
    $row1.total_score = [string]([Math]::Max(0, $total - $basketItems.Count))
    $row2.total_score = [string]([Math]::Max(0, $total - (2 * $basketItems.Count)))
    $scoreBody = [ordered]@{
        assessmentKey = 'real012-guangzhou-2015-sample'
        assessmentTitle = 'REAL012 Guangzhou 2015 real question sample'
        subject = 'physics'
        stage = 'junior_middle_school'
        grade = 'grade_9'
        templateKey = 'real012-score-template-v1'
        templateDisplayName = 'REAL012 score template'
        sourceFileName = 'real012-score-import.xlsx'
        containsStudentPii = $false
        productionEligible = $false
        maxTotalScore = $total
        fieldMapping = $fieldMapping
        itemMaxScores = $itemMaxScores
        rows = @(
            @{ rowNumber = 2; values = $row1 },
            @{ rowNumber = 3; values = $row2 }
        )
    } | ConvertTo-Json -Depth 12
    $scoreImport = Invoke-RestMethod -Method Post -Uri "$apiUrl/score-imports" -ContentType 'application/json' -Body $scoreBody -TimeoutSec 10
    Assert-True ([string]$scoreImport.status -eq 'imported') 'REAL012 score import should succeed'

    $mappings = @($basketItems | ForEach-Object {
        [ordered]@{ questionNo = "Q$($_.questionNo)"; questionItemId = [string]$_.questionItemId }
    })
    $analysisBody = [ordered]@{
        format = 'md'
        allowAiDraftText = $false
        mappings = $mappings
    } | ConvertTo-Json -Depth 8
    $analysis = Invoke-RestMethod -Method Post -Uri "$apiUrl/assessments/$($scoreImport.assessmentId)/commentary-report/export" -ContentType 'application/json' -Body $analysisBody -TimeoutSec 10
    Assert-True ([string]$analysis.status -eq 'ready') 'REAL012 commentary report should be ready'
    Assert-True (-not [bool]$analysis.allowAiDraftText) 'REAL012 analysis must keep AI draft text disabled'
    Assert-True (-not [bool]$analysis.writesProductionHistory) 'REAL012 analysis must not write formal history'
    Assert-True (@($analysis.weakKnowledgePoints).Count -ge 1) 'REAL012 analysis should reference mapped real questions'

    $quality = Invoke-RestMethod -Uri "$apiUrl/source-documents/$sourceDocumentId/quality-report" -TimeoutSec 10
    Assert-True ([int]$quality.metrics.questionCount -ge 24) 'REAL012 quality report must cover the uploaded 2015 paper questions'
    Assert-True ([int]$quality.metrics.answerCoveredCount -ge 24) 'REAL012 quality report answer coverage should include every 2015 question'
    Assert-True ([int]$quality.metrics.imageAssetCount -ge 1) 'REAL012 quality report must count question images'
    Assert-True ([int]$quality.metrics.pendingManualItemCount -ge 1) 'REAL012 quality report must expose remaining manual review items'
    Assert-True ([string]$quality.closureStatus -eq 'not_closed') 'REAL012 paper quality report must keep not_closed while manual items remain'
    Assert-True (@($quality.gaps).Count -ge 1) 'REAL012 quality report must list remaining per-paper gaps'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$quality.rollbackSql)) 'REAL012 quality report must include rollback SQL reference'

    & pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-real005-guangzhou-2015-2025-closure-standard.ps1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'REAL012 failed while refreshing REAL005 closure guard' }
    $real005 = Get-Content -LiteralPath (Join-Path $repoRoot 'docs/evidence/20260512-real005-guangzhou-2015-2025-closure-standard-report.json') -Raw | ConvertFrom-Json
    Assert-True ([string]$real005.closureStatus -eq 'not_closed') 'REAL012 must not close REAL005 full 2015-2025 standard'

    $report = [ordered]@{
        status = 'pass'
        task = 'REAL012'
        checkedAt = (Get-Date).ToString('s')
        requestedApiPort = $requestedApiPort
        resolvedApiPort = $ApiPort
        portFallbackApplied = ($requestedApiPort -ne $ApiPort)
        apiUrl = $apiUrl
        sourceDocumentId = $sourceDocumentId
        promotedQuestions = $promoted
        searchProbe = [ordered]@{
            total = [int]$search.total
            selectedQuestionNos = $cardQuestionNos
            hasImageCount = @($cards | Where-Object { [bool]$_.hasImage }).Count
            sortBy = 'question_no'
            order = 'asc'
        }
        paperBasket = [ordered]@{
            id = [string]$basket.id
            itemCount = @($basket.items).Count
            title = [string]$basket.title
        }
        exportPreflight = [ordered]@{
            status = [string]$preflight.status
            itemCount = [int]$preflight.itemCount
            summary = $preflight.summary
            issueCounts = $preflight.issueCounts
        }
        artifact = [ordered]@{
            reportPath = $artifactReportPath
            manifestPath = [string]$artifactReport.manifestPath
            status = [string]$artifactReport.status
        }
        analysis = [ordered]@{
            assessmentId = [string]$scoreImport.assessmentId
            status = [string]$analysis.status
            artifactPath = [string]$analysis.artifactPath
            allowAiDraftText = [bool]$analysis.allowAiDraftText
            writesProductionHistory = [bool]$analysis.writesProductionHistory
            weakKnowledgePointCount = @($analysis.weakKnowledgePoints).Count
        }
        qualityReport = [ordered]@{
            closureStatus = [string]$quality.closureStatus
            metrics = $quality.metrics
            gaps = $quality.gaps
            rollbackSql = [string]$quality.rollbackSql
        }
        real005ClosureStatus = [string]$real005.closureStatus
        rollback = "delete from review_queue_items where payload::text like '%REAL012%' or payload::text like '%real012-smoke%'; update question_items set status='pending_review', primary_knowledge_id=null where id in ('$(($selectedIds -join "','"))');"
        summaryChinese = '真实广州 2015 样题已进入题号排序检索、题篮、导出预检、Word/PDF 草稿产物和学情讲评引用；逐卷质量报告会继续把待人工项暴露为 not_closed。'
    }
    $fullReportPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $fullReportPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $fullReportPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 30
}
finally {
    if ($null -ne $process) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    $env:KQG_CONNECTION_STRING = $previousConnectionString
    Pop-Location
}

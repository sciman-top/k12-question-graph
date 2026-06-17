param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [int] $ApiPort = 0,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $OutputRoot = 'tmp\real005c1-paper-artifacts',
    [string] $ReportPath = '',
    [string] $MarkdownReportPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for REAL005C1 search/paper/export smoke'
}

$runDate = Get-Date -Format 'yyyyMMdd'
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = ('docs/evidence/{0}-real005c1-real-question-search-paper-export-smoke.json' -f $runDate)
}
if ([string]::IsNullOrWhiteSpace($MarkdownReportPath)) {
    $MarkdownReportPath = ('docs/evidence/{0}-real005c1-real-question-search-paper-export-smoke.md' -f $runDate)
}
$artifactReportPath = ('docs/evidence/{0}-real005c1-word-pdf-artifact-report.json' -f $runDate)

$workflowKey = 'guangzhou_2016_2025_reviewed_question_materialize_v1'
$reasonToken = 'real005c1_search_paper_export_smoke'
$successYears = @(2016, 2017, 2018, 2019, 2021, 2022, 2023, 2024, 2025)
$anomalyYear = 2020

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

function Wait-ApiReady {
    param([int] $ProcessId, [string] $ApiUrl, [string] $LogErr)
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) {
            if (Test-Path -LiteralPath $LogErr) {
                throw "API process exited early: $(Get-Content -LiteralPath $LogErr -Raw)"
            }
            throw 'API process exited early'
        }

        try {
            $health = Invoke-RestMethod -Method Get -Uri "$ApiUrl/health/ready" -TimeoutSec 2
            if ($health.status -eq 'ok') {
                return
            }
        }
        catch {}

        Start-Sleep -Milliseconds 500
    }

    throw 'API ready timeout'
}

function Invoke-RowSql {
    param([string] $Sql)
    $psql = Join-Path $PgBin 'psql.exe'
    $output = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -F '|' -v ON_ERROR_STOP=1 -c $Sql
    if ($LASTEXITCODE -ne 0) {
        throw "REAL005C1 SQL failed: $Sql"
    }

    $text = ($output | Out-String)
    return @(
        ($text -split "`r?`n") |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Invoke-ScalarSql {
    param([string] $Sql)
    $rows = @(Invoke-RowSql -Sql $Sql)
    if ($rows.Count -le 0) { return '' }
    return [string] $rows[0]
}

function ConvertTo-SqlStringLiteral {
    param([AllowNull()][string] $Value)
    if ($null -eq $Value) {
        return 'null'
    }

    return "'" + $Value.Replace("'", "''") + "'"
}

function Get-QuestionYear {
    param([object] $QuestionDetail)
    $sourceDocumentId = [string] $QuestionDetail.customFields.sourceDocumentId
    Assert-True (-not [string]::IsNullOrWhiteSpace($sourceDocumentId)) "question $($QuestionDetail.id) is missing customFields.sourceDocumentId"
    $year = Invoke-ScalarSql -Sql "select year::text from source_documents where id = '$sourceDocumentId';"
    Assert-True (-not [string]::IsNullOrWhiteSpace($year)) "source document $sourceDocumentId is missing year"
    return [int] $year
}

function ConvertTo-QuestionArtifact {
    param(
        [object] $Detail,
        [object] $Card,
        [int] $QuestionNo,
        [decimal] $Score,
        [int] $Year
    )

    return [ordered]@{
        questionItemId = [string] $Detail.id
        questionNo = $QuestionNo
        score = $Score
        title = if ([string]::IsNullOrWhiteSpace([string] $Card.preview)) {
            "广州 $Year 真题抽样第 $QuestionNo 题"
        }
        else {
            "[$Year] " + [string] $Card.preview
        }
        blocks = @($Detail.blocks)
        hasImage = (@($Detail.assets).Count -gt 0)
        answer = [string] $Detail.customFields.answer.value
        solution = [string] $Detail.customFields.solution.text
        sourceAuthorizationStatus = 'authorized'
        knowledgeVersionStatus = 'active'
        knowledgeVersion = 1
    }
}

function Join-IdsForSql {
    param([string[]] $Ids)
    return ($Ids | ForEach-Object { "'" + $_ + "'" }) -join ', '
}

function Get-IssueCount {
    param(
        [object] $Preflight,
        [string] $Code
    )

    $issueCounts = $Preflight.issueCounts
    if ($null -ne $issueCounts) {
        $property = $issueCounts.PSObject.Properties[$Code]
        if ($null -ne $property -and $null -ne $property.Value) {
            return [int] $property.Value
        }
    }

    $count = 0
    foreach ($item in @($Preflight.items)) {
        foreach ($issue in @($item.issues)) {
            if ([string] $issue.code -eq $Code) {
                $count += 1
            }
        }
    }
    return $count
}

$requestedApiPort = $ApiPort
if ($ApiPort -le 0) {
    $ApiPort = Get-FreeTcpPort
}

$apiUrl = "http://127.0.0.1:$ApiPort"
$logOut = Join-Path $repoRoot 'docs/evidence/real005c1-search-paper-export-api.out.log'
$logErr = Join-Path $repoRoot 'docs/evidence/real005c1-search-paper-export-api.err.log'
$previousConnectionString = $env:KQG_CONNECTION_STRING
$env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
$process = $null
$pushedLocation = $false

try {
    Push-Location $repoRoot
    $pushedLocation = $true

    & pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-real005b-reviewed-question-source-smoke.ps1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'REAL005C1 prerequisite REAL005B reviewed question source smoke failed'
    }

    $successRows = @(
        Invoke-RowSql -Sql @"
with ranked as (
  select
    sd.year,
    qi.id::text as question_id,
    coalesce(qi.custom_fields->>'questionNo','') as question_no,
    coalesce(qi.custom_fields->'answer'->>'value','') as answer_value,
    row_number() over (
      partition by sd.year
      order by nullif(qi.custom_fields->>'questionNo','')::int nulls last, qi.id
    ) as rn
  from question_items qi
  join source_documents sd on sd.id = (qi.custom_fields->>'sourceDocumentId')::uuid
  where coalesce(qi.custom_fields->>'sourceWorkflowKey','') = '$workflowKey'
    and coalesce(qi.custom_fields->'answer'->>'value','') <> ''
)
select year::text || '|' || question_no || '|' || answer_value || '|' || question_id
from ranked
where rn = 1
order by year;
"@
    )
    $successSamples = foreach ($row in $successRows) {
        $parts = $row -split '\|', 4
        [pscustomobject]@{
            year = [int] $parts[0]
            questionNo = [int] $parts[1]
            answer = [string] $parts[2]
            questionId = [string] $parts[3]
        }
    }

    $actualSuccessYears = @($successSamples | ForEach-Object { [int] $_.year })
    Assert-True (($actualSuccessYears -join ',') -eq ($successYears -join ',')) "REAL005C1 expected success samples for years $($successYears -join ',') but got $($actualSuccessYears -join ',')"

    $anomalyRows = @(
        Invoke-RowSql -Sql @"
with ranked as (
  select
    sd.year,
    qi.id::text as question_id,
    coalesce(qi.custom_fields->>'questionNo','') as question_no,
    row_number() over (
      partition by sd.year
      order by nullif(qi.custom_fields->>'questionNo','')::int nulls last, qi.id
    ) as rn
  from question_items qi
  join source_documents sd on sd.id = (qi.custom_fields->>'sourceDocumentId')::uuid
  where coalesce(qi.custom_fields->>'sourceWorkflowKey','') = '$workflowKey'
    and sd.year = $anomalyYear
    and coalesce(qi.custom_fields->'answer'->>'value','') = ''
)
select year::text || '|' || question_no || '|' || question_id
from ranked
where rn = 1;
"@
    )
    Assert-True ($anomalyRows.Count -eq 1) "REAL005C1 expected one anomaly sample for year $anomalyYear"
    $anomalyParts = $anomalyRows[0] -split '\|', 3
    $anomalySample = [pscustomobject]@{
        year = [int] $anomalyParts[0]
        questionNo = [int] $anomalyParts[1]
        questionId = [string] $anomalyParts[2]
    }

    $allSelectedQuestionIds = @($successSamples | ForEach-Object { [string] $_.questionId }) + @([string] $anomalySample.questionId)
    $selectedIdsSql = Join-IdsForSql -Ids $allSelectedQuestionIds

    $questionSnapshots = @{}
    $questionSnapshotRows = @(
        Invoke-RowSql -Sql @"
select
  qi.id::text,
  coalesce(qi.status,''),
  coalesce(qi.primary_knowledge_id::text,''),
  coalesce(qi.custom_fields::text,''),
  coalesce(qi.custom_fields->>'questionNo',''),
  coalesce(qi.custom_fields->>'sourceDocumentId',''),
  coalesce(qi.custom_fields->'answer'->>'value',''),
  coalesce(qi.custom_fields->'solution'->>'text','')
from question_items qi
where qi.id in ($selectedIdsSql)
order by nullif(qi.custom_fields->>'questionNo','')::int nulls last, qi.id;
"@
    )
    foreach ($row in $questionSnapshotRows) {
        $parts = $row -split '\|', 8
        $questionId = [string] $parts[0]
        $questionSnapshots[$questionId] = [ordered]@{
            id = $questionId
            status = [string] $parts[1]
            primaryKnowledgeId = if ([string]::IsNullOrWhiteSpace([string] $parts[2])) { $null } else { [string] $parts[2] }
            customFieldsJson = [string] $parts[3]
            questionNo = if ([string]::IsNullOrWhiteSpace([string] $parts[4])) { $null } else { [int] $parts[4] }
            sourceDocumentId = [string] $parts[5]
            assetCount = 0
            answerValue = [string] $parts[6]
            solutionText = [string] $parts[7]
        }
    }
    Assert-True ($questionSnapshots.Count -eq $allSelectedQuestionIds.Count) "REAL005C1 question snapshot count mismatch: expected $($allSelectedQuestionIds.Count), actual $($questionSnapshots.Count)"

    $sourceDocumentIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($questionId in $allSelectedQuestionIds) {
        $sourceDocumentId = [string] $questionSnapshots[$questionId].sourceDocumentId
        Assert-True (-not [string]::IsNullOrWhiteSpace($sourceDocumentId)) "REAL005C1 sample question $questionId is missing sourceDocumentId"
        [void] $sourceDocumentIds.Add($sourceDocumentId)
    }

    $sourceSnapshots = @{}
    foreach ($sourceDocumentId in $sourceDocumentIds) {
        $sourceRows = @(
            Invoke-RowSql -Sql @"
select
  id::text,
  coalesce(license_or_permission,''),
  sharing_allowed::text,
  contains_student_pii::text,
  coalesce(anonymization_status,''),
  external_ai_allowed::text,
  may_use_for_exam_point_extraction::text,
  may_use_for_knowledge_extraction::text,
  may_use_for_trend_analysis::text
from source_documents
where id = '$sourceDocumentId';
"@
        )
        Assert-True ($sourceRows.Count -eq 1) "REAL005C1 could not load source document snapshot for $sourceDocumentId"
        $parts = $sourceRows[0] -split '\|', 9
        $sourceSnapshots[$sourceDocumentId] = [ordered]@{
            id = [string] $parts[0]
            licenseOrPermission = [string] $parts[1]
            sharingAllowed = [string] $parts[2]
            containsStudentPii = [string] $parts[3]
            anonymizationStatus = [string] $parts[4]
            externalAiAllowed = [string] $parts[5]
            mayUseForExamPointExtraction = [string] $parts[6]
            mayUseForKnowledgeExtraction = [string] $parts[7]
            mayUseForTrendAnalysis = [string] $parts[8]
        }
    }

    $knowledgeId = [Guid]::NewGuid().ToString()
    $knowledgeCode = 'REAL005C1-ACTIVE-' + [Guid]::NewGuid().ToString('N').Substring(0, 8).ToUpperInvariant()
    Invoke-ScalarSql -Sql @"
insert into knowledge_nodes (
  id, subject, stage, code, title, node_type, level, status, version, metadata, created_at, updated_at
)
values (
  '$knowledgeId',
  'physics',
  'junior_middle_school',
  '$knowledgeCode',
  'REAL005C1 RG010 Active Seed',
  'concept',
  2,
  'active',
  1,
  '{"task":"REAL005C1","criterion":"RG010","reason":"$reasonToken"}',
  now(),
  now()
);
"@ | Out-Null

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
    Wait-ApiReady -ProcessId $process.Id -ApiUrl $apiUrl -LogErr $logErr

    foreach ($sourceDocumentId in $sourceDocumentIds) {
        $authorizationBody = [ordered]@{
            licenseOrPermission = 'internal_authorized'
            sharingAllowed = $true
            containsStudentPii = $false
            anonymizationStatus = 'not_applicable'
            externalAiAllowed = $false
            mayUseForKnowledgeExtraction = $true
            mayUseForExamPointExtraction = $true
            mayUseForTrendAnalysis = $false
            reviewedBy = 'real005c1-smoke'
            reason = $reasonToken + '_authorize_source'
        } | ConvertTo-Json -Depth 6
        Invoke-RestMethod -Method Patch -Uri "$apiUrl/source-documents/$sourceDocumentId/authorization" -ContentType 'application/json' -Body $authorizationBody -TimeoutSec 10 | Out-Null
    }

    $promotedSuccessSamples = New-Object System.Collections.Generic.List[object]
    foreach ($sample in $successSamples) {
        $detail = Invoke-RestMethod -Method Get -Uri "$apiUrl/questions/$($sample.questionId)" -TimeoutSec 10
        Assert-True (@($detail.assets).Count -ge 1) "REAL005C1 success sample $($sample.questionId) must expose at least one asset"
        $solutionText = "RG010 导出预检抽样解析：已审核答案为 $($sample.answer)；本解析仅用于 repo-side 检索/题篮/导出链 smoke，不代表全量解析治理完成。"
        $patchBody = [ordered]@{
            status = 'usable'
            primaryKnowledgeId = $knowledgeId
            defaultScore = if ($null -eq $detail.defaultScore) { 4 } else { [decimal] $detail.defaultScore }
            difficultyEstimated = if ($null -eq $detail.difficultyEstimated) { 0.62 } else { [double] $detail.difficultyEstimated }
            solution = [ordered]@{
                text = $solutionText
                source = $reasonToken
                reviewStatus = 'draft'
            }
            reviewedBy = 'real005c1-smoke'
            reason = $reasonToken + '_promote_success_sample'
        } | ConvertTo-Json -Depth 8
        $revision = Invoke-RestMethod -Method Patch -Uri "$apiUrl/questions/$($sample.questionId)" -ContentType 'application/json' -Body $patchBody -TimeoutSec 10
        $promotedSuccessSamples.Add([pscustomobject]@{
            year = [int] $sample.year
            questionNo = [int] $sample.questionNo
            questionItemId = [string] $sample.questionId
            auditId = [string] $revision.auditId
            status = [string] $revision.question.status
            primaryKnowledgeId = [string] $revision.question.primaryKnowledgeId
        })
    }

    $anomalyDetail = Invoke-RestMethod -Method Get -Uri "$apiUrl/questions/$($anomalySample.questionId)" -TimeoutSec 10
    $anomalyPatchBody = [ordered]@{
        status = 'usable'
        primaryKnowledgeId = $knowledgeId
        defaultScore = if ($null -eq $anomalyDetail.defaultScore) { 4 } else { [decimal] $anomalyDetail.defaultScore }
        difficultyEstimated = if ($null -eq $anomalyDetail.difficultyEstimated) { 0.58 } else { [double] $anomalyDetail.difficultyEstimated }
        reviewedBy = 'real005c1-smoke'
        reason = $reasonToken + '_promote_anomaly_sample'
    } | ConvertTo-Json -Depth 6
    $anomalyRevision = Invoke-RestMethod -Method Patch -Uri "$apiUrl/questions/$($anomalySample.questionId)" -ContentType 'application/json' -Body $anomalyPatchBody -TimeoutSec 10

    $search = Invoke-RestMethod -Method Get -Uri "$apiUrl/questions?subject=physics&stage=junior_middle_school&status=usable&primaryKnowledgeId=$knowledgeId&sourceType=local_exam_paper&sortBy=question_no&order=asc&page=1&limit=200" -TimeoutSec 10
    $searchItems = @($search.items)
    $returnedIds = @($searchItems | ForEach-Object { [string] $_.id })
    foreach ($questionId in $allSelectedQuestionIds) {
        Assert-True ($returnedIds -contains $questionId) "REAL005C1 search did not return promoted real question $questionId"
    }

    $successCards = @($searchItems | Where-Object { @($promotedSuccessSamples | ForEach-Object { $_.questionItemId }) -contains [string] $_.id })
    Assert-True ($successCards.Count -eq $promotedSuccessSamples.Count) 'REAL005C1 success sample cards are incomplete in search response'

    $basketItems = @()
    $questionArtifacts = @()
    $sortOrder = 0
    $displayQuestionNo = 1
    foreach ($sample in @($promotedSuccessSamples | Sort-Object year, questionNo)) {
        $card = @($successCards | Where-Object { [string] $_.id -eq [string] $sample.questionItemId } | Select-Object -First 1)[0]
        $detail = Invoke-RestMethod -Method Get -Uri "$apiUrl/questions/$($sample.questionItemId)" -TimeoutSec 10
        $score = if ($null -eq $detail.defaultScore) { 4 } else { [decimal] $detail.defaultScore }
        $basketItems += [ordered]@{
            questionItemId = [string] $detail.id
            sectionNo = 1
            questionNo = $displayQuestionNo
            subQuestionNo = $null
            score = $score
            sortOrder = $sortOrder
        }
        $questionArtifacts += ConvertTo-QuestionArtifact -Detail $detail -Card $card -QuestionNo $displayQuestionNo -Score $score -Year ([int] $sample.year)
        $sortOrder += 1
        $displayQuestionNo += 1
    }

    $basketBody = [ordered]@{
        title = 'REAL005C1 2016-2025 广州 reviewed 真题抽样组卷'
        subject = 'physics'
        stage = 'junior_middle_school'
        grade = 'grade_9'
        knowledgeVersionStatus = 'active'
        knowledgeVersion = 1
        items = $basketItems
    } | ConvertTo-Json -Depth 10
    $successBasket = Invoke-RestMethod -Method Post -Uri "$apiUrl/paper-baskets" -ContentType 'application/json' -Body $basketBody -TimeoutSec 10

    $preflightBody = @{ exportFormat = 'docx' } | ConvertTo-Json
    $successPreflight = Invoke-RestMethod -Method Post -Uri "$apiUrl/paper-baskets/$($successBasket.id)/export-preflight" -ContentType 'application/json' -Body $preflightBody -TimeoutSec 10
    Assert-True ([string] $successPreflight.status -eq 'ready_for_review') 'REAL005C1 success basket preflight must be ready_for_review'
    Assert-True (-not [bool] $successPreflight.productionEligible) 'REAL005C1 success preflight must remain non-production eligible'
    Assert-True ([int] $successPreflight.itemCount -eq $promotedSuccessSamples.Count) 'REAL005C1 success preflight item count mismatch'
    Assert-True (@($successPreflight.issueCounts.PSObject.Properties).Count -eq 0) 'REAL005C1 success preflight should not expose blockers'
    Assert-True ([int] $successPreflight.summary.answerReadyCount -eq $promotedSuccessSamples.Count) 'REAL005C1 success preflight must cover all answers'
    Assert-True ([int] $successPreflight.summary.solutionReadyCount -eq $promotedSuccessSamples.Count) 'REAL005C1 success preflight must cover all solutions'
    Assert-True ([int] $successPreflight.summary.authorizedSourceCount -eq $promotedSuccessSamples.Count) 'REAL005C1 success preflight must cover all authorized sources'
    Assert-True ([int] $successPreflight.summary.activeKnowledgeVersionCount -eq $promotedSuccessSamples.Count) 'REAL005C1 success preflight must cover all active knowledge references'

    $artifactInputRelativePath = Join-Path $OutputRoot 'real005c1-paper-input.json'
    $artifactInputFullPath = Join-Path $repoRoot $artifactInputRelativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $artifactInputFullPath) -Force | Out-Null
    $artifactInput = [ordered]@{
        taskId = 'REAL005C1'
        paperBasketId = $successBasket.id
        basketTitle = $successBasket.title
        preflight = $successPreflight
        questions = $questionArtifacts
    }
    $artifactInput | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $artifactInputFullPath -Encoding UTF8

    & python tools\s010b_paper_artifact_chain.py --input $artifactInputRelativePath --output-root $OutputRoot --report $artifactReportPath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'REAL005C1 artifact generator failed'
    }

    $reportFullPath = Join-Path $repoRoot ($ReportPath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $artifactReportFullPath = Join-Path $repoRoot ($artifactReportPath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $artifactReport = Get-Content -LiteralPath $artifactReportFullPath -Raw | ConvertFrom-Json
    Assert-True ([string] $artifactReport.status -eq 'pass') 'REAL005C1 artifact report must pass'
    Assert-True ([string] $artifactReport.preflightStatus -eq 'ready_for_review') 'REAL005C1 artifact report preflight must stay ready_for_review'

    $anomalyBasketBody = [ordered]@{
        title = 'REAL005C1 2020 anomaly export preflight'
        subject = 'physics'
        stage = 'junior_middle_school'
        grade = 'grade_9'
        knowledgeVersionStatus = 'active'
        knowledgeVersion = 1
        items = @(
            [ordered]@{
                questionItemId = [string] $anomalySample.questionId
                sectionNo = 1
                questionNo = 1
                subQuestionNo = $null
                score = if ($null -eq $anomalyDetail.defaultScore) { 4 } else { [decimal] $anomalyDetail.defaultScore }
                sortOrder = 0
            }
        )
    } | ConvertTo-Json -Depth 8
    $anomalyBasket = Invoke-RestMethod -Method Post -Uri "$apiUrl/paper-baskets" -ContentType 'application/json' -Body $anomalyBasketBody -TimeoutSec 10
    $anomalyPreflight = Invoke-RestMethod -Method Post -Uri "$apiUrl/paper-baskets/$($anomalyBasket.id)/export-preflight" -ContentType 'application/json' -Body $preflightBody -TimeoutSec 10
    $anomalyFirstItem = @($anomalyPreflight.items)[0]
    $anomalyAnswerMissingCount = Get-IssueCount -Preflight $anomalyPreflight -Code 'answer_missing'
    $anomalySolutionMissingCount = Get-IssueCount -Preflight $anomalyPreflight -Code 'solution_missing'
    Assert-True ([string] $anomalyPreflight.status -eq 'blocked') 'REAL005C1 anomaly preflight must stay blocked'
    Assert-True ($anomalySolutionMissingCount -ge 1) 'REAL005C1 anomaly preflight must expose solution_missing'
    Assert-True (-not [bool] $anomalyFirstItem.hasSolution) 'REAL005C1 anomaly item must still lack solution'
    Assert-True ([bool] $anomalyFirstItem.hasAnswer) 'REAL005C1 anomaly should currently expose an answer object even when its value is empty'
    Assert-True ([int] $anomalyPreflight.summary.authorizedSourceCount -eq 1) 'REAL005C1 anomaly source authorization should be isolated from answer/solution blockers'
    Assert-True ([int] $anomalyPreflight.summary.activeKnowledgeVersionCount -eq 1) 'REAL005C1 anomaly should still prove knowledge reference wiring'

    $questionRollbackLines = New-Object System.Collections.Generic.List[string]
    foreach ($questionId in $allSelectedQuestionIds) {
        $snapshot = $questionSnapshots[$questionId]
        $primaryKnowledgeSql = if ([string]::IsNullOrWhiteSpace([string] $snapshot.primaryKnowledgeId)) {
            'null'
        }
        else {
            "'" + [string] $snapshot.primaryKnowledgeId + "'"
        }
        $questionRollbackLines.Add(
            "update question_items set status = $(ConvertTo-SqlStringLiteral -Value ([string] $snapshot.status)), primary_knowledge_id = $primaryKnowledgeSql, custom_fields = $(ConvertTo-SqlStringLiteral -Value ([string] $snapshot.customFieldsJson))::jsonb where id = '$questionId';"
        ) | Out-Null
    }

    $sourceRollbackLines = New-Object System.Collections.Generic.List[string]
    foreach ($sourceDocumentId in $sourceDocumentIds) {
        $snapshot = $sourceSnapshots[$sourceDocumentId]
        $sourceRollbackLines.Add(
            "update source_documents set license_or_permission = $(ConvertTo-SqlStringLiteral -Value ([string] $snapshot.licenseOrPermission)), sharing_allowed = $([string] $snapshot.sharingAllowed), contains_student_pii = $([string] $snapshot.containsStudentPii), anonymization_status = $(ConvertTo-SqlStringLiteral -Value ([string] $snapshot.anonymizationStatus)), external_ai_allowed = $([string] $snapshot.externalAiAllowed), may_use_for_exam_point_extraction = $([string] $snapshot.mayUseForExamPointExtraction), may_use_for_knowledge_extraction = $([string] $snapshot.mayUseForKnowledgeExtraction), may_use_for_trend_analysis = $([string] $snapshot.mayUseForTrendAnalysis) where id = '$sourceDocumentId';"
        ) | Out-Null
    }

    $rollbackLines = New-Object System.Collections.Generic.List[string]
    $rollbackLines.Add('begin;') | Out-Null
    $rollbackLines.Add("delete from paper_basket_items where paper_basket_id in ('$($successBasket.id)','$($anomalyBasket.id)');") | Out-Null
    $rollbackLines.Add("delete from paper_baskets where id in ('$($successBasket.id)','$($anomalyBasket.id)');") | Out-Null
    $rollbackLines.Add("delete from review_queue_items where payload::text like '%$reasonToken%';") | Out-Null
    $rollbackLines.Add("delete from knowledge_mappings where question_item_id in ($selectedIdsSql) and knowledge_node_id = '$knowledgeId';") | Out-Null
    foreach ($line in $questionRollbackLines) {
        $rollbackLines.Add([string] $line) | Out-Null
    }
    foreach ($line in $sourceRollbackLines) {
        $rollbackLines.Add([string] $line) | Out-Null
    }
    $rollbackLines.Add("delete from knowledge_nodes where id = '$knowledgeId';") | Out-Null
    $rollbackLines.Add('commit;') | Out-Null
    $rollbackSql = [string]::Join("`r`n", $rollbackLines)

    $successPreflightSummary = [ordered]@{
        imageReadyCount = [int] $successPreflight.summary.imageReadyCount
        formulaReadyCount = [int] $successPreflight.summary.formulaReadyCount
        tableReadyCount = [int] $successPreflight.summary.tableReadyCount
        answerReadyCount = [int] $successPreflight.summary.answerReadyCount
        solutionReadyCount = [int] $successPreflight.summary.solutionReadyCount
        authorizedSourceCount = [int] $successPreflight.summary.authorizedSourceCount
        activeKnowledgeVersionCount = [int] $successPreflight.summary.activeKnowledgeVersionCount
    }
    $anomalyPreflightSummary = [ordered]@{
        imageReadyCount = [int] $anomalyPreflight.summary.imageReadyCount
        formulaReadyCount = [int] $anomalyPreflight.summary.formulaReadyCount
        tableReadyCount = [int] $anomalyPreflight.summary.tableReadyCount
        answerReadyCount = [int] $anomalyPreflight.summary.answerReadyCount
        solutionReadyCount = [int] $anomalyPreflight.summary.solutionReadyCount
        authorizedSourceCount = [int] $anomalyPreflight.summary.authorizedSourceCount
        activeKnowledgeVersionCount = [int] $anomalyPreflight.summary.activeKnowledgeVersionCount
    }
    $successIssueCounts = [ordered]@{}
    foreach ($property in @($successPreflight.issueCounts.PSObject.Properties)) {
        $successIssueCounts[$property.Name] = [int] $property.Value
    }
    $anomalyIssueCounts = [ordered]@{}
    foreach ($property in @($anomalyPreflight.issueCounts.PSObject.Properties)) {
        $anomalyIssueCounts[$property.Name] = [int] $property.Value
    }
    $promotedSuccessSampleReports = @(
        $promotedSuccessSamples | ForEach-Object {
            [ordered]@{
                year = [int] $_.year
                questionNo = [int] $_.questionNo
                questionItemId = [string] $_.questionItemId
                auditId = [string] $_.auditId
                status = [string] $_.status
                primaryKnowledgeId = [string] $_.primaryKnowledgeId
            }
        }
    )

    $finalReport = [ordered]@{
        status = 'pass'
        taskId = 'REAL005C1_REAL_QUESTION_SEARCH_PAPER_EXPORT_SMOKE'
        criterionId = 'RG010'
        rg010Status = 'pass'
        checkedAt = (Get-Date).ToString('s')
        requestedApiPort = $requestedApiPort
        resolvedApiPort = $ApiPort
        portFallbackApplied = ($requestedApiPort -ne $ApiPort)
        apiUrl = $apiUrl
        workflowKey = $workflowKey
        activeWrite = $true
        externalAiCalls = 0
        realStudentDataUsed = $false
        productionEligible = $false
        sampleStrategy = [ordered]@{
            successYears = $successYears
            anomalyYear = $anomalyYear
            successSampleCount = $promotedSuccessSamples.Count
            anomalySampleCount = 1
        }
        promotedSuccessSamples = $promotedSuccessSampleReports
        anomalySample = [ordered]@{
            year = $anomalySample.year
            questionNo = $anomalySample.questionNo
            questionItemId = $anomalySample.questionId
            auditId = [string] $anomalyRevision.auditId
            status = [string] $anomalyRevision.question.status
            primaryKnowledgeId = [string] $anomalyRevision.question.primaryKnowledgeId
        }
        searchProbe = [ordered]@{
            total = [int] $search.total
            selectedQuestionCount = $allSelectedQuestionIds.Count
            returnedSelectedQuestionIds = @($returnedIds | Where-Object { $allSelectedQuestionIds -contains $_ })
            successYears = @($promotedSuccessSamples | ForEach-Object { [int] $_.year })
            anomalyYear = $anomalySample.year
        }
        successPreflight = [ordered]@{
            paperBasketId = [string] $successBasket.id
            status = [string] $successPreflight.status
            itemCount = [int] $successPreflight.itemCount
            summary = $successPreflightSummary
            issueCounts = $successIssueCounts
        }
        anomalyPreflight = [ordered]@{
            paperBasketId = [string] $anomalyBasket.id
            status = [string] $anomalyPreflight.status
            itemCount = [int] $anomalyPreflight.itemCount
            summary = $anomalyPreflightSummary
            issueCounts = $anomalyIssueCounts
            derivedIssueCounts = [ordered]@{
                answer_missing = $anomalyAnswerMissingCount
                solution_missing = $anomalySolutionMissingCount
            }
            itemFlags = [ordered]@{
                hasAnswer = [bool] $anomalyFirstItem.hasAnswer
                hasSolution = [bool] $anomalyFirstItem.hasSolution
            }
        }
        artifact = [ordered]@{
            reportPath = $artifactReportPath
            manifestPath = [string] $artifactReport.manifestPath
            status = [string] $artifactReport.status
        }
        blockers = @()
        rollbackSql = $rollbackSql
        cleanup = @(
            "Remove generated artifacts under $OutputRoot after applying rollback SQL.",
            "Delete $(($artifactInputRelativePath -replace '\\', '/')) if the report is reverted."
        )
        boundary = 'Repo-side RG010 smoke only: it proves sampled reviewed real questions can enter search, basket, export preflight, and Word/PDF draft artifacts while a 2020 empty-answer/no-solution anomaly still blocks preflight. REAL005 must remain not_closed until RG011-RG016 also pass.'
        summaryChinese = '2016-2025 reviewed real questions now have repo-side RG010 evidence: sampled years进入检索/题篮/导出链，2020 空答案且缺解析异常仍按当前 API 合同被导出预检阻断。'
    }

    $finalReport | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8

    $markdownFullPath = Join-Path $repoRoot ($MarkdownReportPath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    @(
        '# REAL005C1 Reviewed Real Question Search Paper Export Smoke',
        '',
        "- status: $($finalReport.status)",
        "- criterion_id: $($finalReport.criterionId)",
        "- rg010_status: $($finalReport.rg010Status)",
        "- success_sample_count: $($finalReport.sampleStrategy.successSampleCount)",
        "- anomaly_sample_year: $($finalReport.sampleStrategy.anomalyYear)",
        "- success_preflight_status: $($finalReport.successPreflight.status)",
        "- anomaly_preflight_status: $($finalReport.anomalyPreflight.status)",
        "- artifact_status: $($finalReport.artifact.status)",
        '',
        '## Boundary',
        $finalReport.boundary
    ) | Set-Content -LiteralPath $markdownFullPath -Encoding UTF8

    $finalReport | ConvertTo-Json -Depth 12
}
finally {
    if ($null -ne $process) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    $env:KQG_CONNECTION_STRING = $previousConnectionString
    if ($pushedLocation) {
        Pop-Location
    }
}

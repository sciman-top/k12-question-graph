param(
    [Parameter(Mandatory)]
    [string] $BackupManifest,
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

$workflowKey = 'guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1'
$reasonToken = 'real005c1_search_paper_export_smoke'
$successYears = @(2016, 2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024, 2025)
$anomalyYear = 2015

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

function Invoke-CommandSql {
    param([string] $Sql)
    $psql = Join-Path $PgBin 'psql.exe'
    $commandId = [Guid]::NewGuid().ToString('N')
    $commandDir = Join-Path $repoRoot 'tmp\real005c-sql'
    $sqlPath = Join-Path $commandDir "$commandId.sql"
    $outPath = Join-Path $commandDir "$commandId.out.log"
    $errPath = Join-Path $commandDir "$commandId.err.log"
    New-Item -ItemType Directory -Path $commandDir -Force | Out-Null
    [System.IO.File]::WriteAllText($sqlPath, $Sql, [System.Text.UTF8Encoding]::new($false))
    try {
        $sqlProcess = Start-Process -FilePath $psql -ArgumentList @(
            '-h', $DatabaseHost, '-p', [string] $DatabasePort, '-U', $DatabaseUser,
            '-d', $DatabaseName, '-v', 'ON_ERROR_STOP=1', '-f', $sqlPath
        ) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $outPath -RedirectStandardError $errPath
        if ($sqlProcess.ExitCode -ne 0) {
            throw "REAL005C1 command SQL failed: $(Get-Content -LiteralPath $errPath -Raw)"
        }
    }
    finally {
        Remove-Item -LiteralPath $sqlPath, $outPath, $errPath -Force -ErrorAction SilentlyContinue
    }
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
        [int] $Year,
        [string[]] $ImagePaths
    )

    return [ordered]@{
        questionItemId = [string] $Detail.id
        questionNo = $QuestionNo
        score = $Score
        title = "$Year 年广州中考物理第 $QuestionNo 题"
        blocks = @($Detail.blocks)
        hasImage = (@($Detail.assets).Count -gt 0)
        imagePaths = @($ImagePaths)
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
$rollbackSql = ''
$rollbackApplied = $false
$knowledgeId = ''
$successBasket = $null
$anomalyBasket = $null
$questionSnapshots = @{}
$sourceSnapshots = @{}
$allSelectedQuestionIds = @()

$backupVerification = & (Join-Path $PSScriptRoot 'verify-backup.ps1') -ManifestPath $BackupManifest | ConvertFrom-Json
Assert-True ([string] $backupVerification.status -eq 'ok') 'REAL005C1 backup verification failed'

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
    and coalesce(qi.custom_fields->'solution'->>'text','') <> ''
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
    and coalesce(qi.custom_fields->'answer'->>'value','') <> ''
    and coalesce(qi.custom_fields->'solution'->>'text','') = ''
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
    $linkedSourceDocumentRows = @(Invoke-RowSql -Sql @"
select distinct source_document_id::text
from (
  select sr.source_document_id
  from question_blocks qb
  join source_regions sr on sr.id=qb.source_region_id
  where qb.question_item_id in ($selectedIdsSql)
  union
  select sr.source_document_id
  from question_assets qa
  join source_regions sr on sr.id=qa.source_region_id
  where qa.question_item_id in ($selectedIdsSql)
  union
  select (qi.custom_fields->>'sourceDocumentId')::uuid
  from question_items qi
  where qi.id in ($selectedIdsSql)
) linked
order by source_document_id;
"@)
    foreach ($sourceDocumentId in $linkedSourceDocumentRows) {
        [void] $sourceDocumentIds.Add([string] $sourceDocumentId)
    }
    Assert-True ($sourceDocumentIds.Count -ge 2) 'REAL005C1 must resolve both paper and answer/solution source documents'

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

    $candidateFilterRows = @(Invoke-RowSql -Sql @"
select concat_ws('|',
  qi.id::text,
  qi.custom_fields->>'year',
  qi.custom_fields->>'questionNo',
  qi.question_type,
  qi.difficulty_estimated::text,
  qi.custom_fields->'knowledgeCandidateIds'->>0,
  qi.custom_fields->'examPointCandidateIds'->>0
)
from question_items qi
where qi.custom_fields->>'sourceWorkflowKey'='$workflowKey'
  and qi.status='pending_review'
  and jsonb_array_length(coalesce(qi.custom_fields->'knowledgeCandidateIds','[]'::jsonb)) > 0
  and jsonb_array_length(coalesce(qi.custom_fields->'examPointCandidateIds','[]'::jsonb)) > 0
  and exists (
    select 1 from question_assets qa
    where qa.question_item_id=qi.id
      and qa.asset_type in ('image','question_region_image')
  )
order by (qi.custom_fields->>'year')::int, (qi.custom_fields->>'questionNo')::int
limit 1;
"@)
    Assert-True ($candidateFilterRows.Count -eq 1) 'REAL005C1 requires one pending-review candidate with knowledge, exam point, difficulty, and image metadata'
    $candidateFilterParts = $candidateFilterRows[0] -split '\|', 7
    $candidateFilterSample = [ordered]@{
        questionItemId = [string] $candidateFilterParts[0]
        year = [int] $candidateFilterParts[1]
        questionNo = [int] $candidateFilterParts[2]
        questionType = [string] $candidateFilterParts[3]
        difficulty = [double]::Parse([string] $candidateFilterParts[4], [System.Globalization.CultureInfo]::InvariantCulture)
        knowledgeCandidateId = [string] $candidateFilterParts[5]
        examPointCandidateId = [string] $candidateFilterParts[6]
    }
    $difficultyMin = ($candidateFilterSample.difficulty - 0.001).ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture)
    $difficultyMax = ($candidateFilterSample.difficulty + 0.001).ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture)
    $candidateSearchUri = "$apiUrl/questions?subject=physics&stage=junior_middle_school&status=pending_review&year=$($candidateFilterSample.year)&questionType=$([Uri]::EscapeDataString($candidateFilterSample.questionType))&knowledgeCandidateId=$([Uri]::EscapeDataString($candidateFilterSample.knowledgeCandidateId))&examPointCandidateId=$([Uri]::EscapeDataString($candidateFilterSample.examPointCandidateId))&difficultyMin=$difficultyMin&difficultyMax=$difficultyMax&hasImage=true&page=1&limit=1"
    $candidateSearch = Invoke-RestMethod -Method Get -Uri $candidateSearchUri -TimeoutSec 10
    Assert-True ([string] $candidateSearch.knowledgeStatus -eq 'candidate_filters') 'REAL005C1 candidate search must expose candidate_filters boundary'
    Assert-True (-not [bool] $candidateSearch.productionEligible) 'REAL005C1 candidate search must remain non-production eligible'
    Assert-True ([int] $candidateSearch.total -ge 1) 'REAL005C1 combined candidate filters returned no real questions'
    Assert-True ([string] @($candidateSearch.items)[0].id -eq [string] $candidateFilterSample.questionItemId) 'REAL005C1 combined candidate filters returned the wrong question'
    Assert-True ([bool] @($candidateSearch.items)[0].hasImage) 'REAL005C1 question_region_image must satisfy hasImage=true'

    $candidateMissYear = [int] $candidateFilterSample.year + 1
    $candidateMiss = Invoke-RestMethod -Method Get -Uri ($candidateSearchUri -replace "year=$($candidateFilterSample.year)", "year=$candidateMissYear") -TimeoutSec 10
    Assert-True (@($candidateMiss.items | Where-Object { [string] $_.id -eq [string] $candidateFilterSample.questionItemId }).Count -eq 0) 'REAL005C1 wrong-year negative filter returned the selected question'

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
        $patchBody = [ordered]@{
            status = 'usable'
            primaryKnowledgeId = $knowledgeId
            defaultScore = if ($null -eq $detail.defaultScore) { 4 } else { [decimal] $detail.defaultScore }
            difficultyEstimated = if ($null -eq $detail.difficultyEstimated) { 0.62 } else { [double] $detail.difficultyEstimated }
            reviewedBy = 'real005c1-smoke'
            reason = $reasonToken + '_temporary_qualification_sample'
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
    $sourceImageRoot = Join-Path $repoRoot (Join-Path $OutputRoot 'source-images')
    New-Item -ItemType Directory -Path $sourceImageRoot -Force | Out-Null
    $sortOrder = 0
    $displayQuestionNo = 1
    foreach ($sample in @($promotedSuccessSamples | Sort-Object year, questionNo)) {
        $card = @($successCards | Where-Object { [string] $_.id -eq [string] $sample.questionItemId } | Select-Object -First 1)[0]
        $detail = Invoke-RestMethod -Method Get -Uri "$apiUrl/questions/$($sample.questionItemId)" -TimeoutSec 10
        $imagePaths = @()
        $assetIndex = 0
        foreach ($asset in @($detail.assets)) {
            if ([string]::IsNullOrWhiteSpace([string] $asset.sourceRegionScreenshotUrl)) { continue }
            $assetIndex += 1
            $imageRelativePath = Join-Path $OutputRoot ("source-images\q{0:D2}-{1:D2}.png" -f $displayQuestionNo, $assetIndex)
            $imageFullPath = Join-Path $repoRoot $imageRelativePath
            Invoke-WebRequest -UseBasicParsing -Uri ($apiUrl + [string] $asset.sourceRegionScreenshotUrl) -OutFile $imageFullPath -TimeoutSec 20
            Assert-True ((Get-Item -LiteralPath $imageFullPath).Length -gt 1000) "REAL005C1 source image is empty: $imageRelativePath"
            $imagePaths += ($imageRelativePath -replace '\\', '/')
        }
        Assert-True ($imagePaths.Count -ge 1) "REAL005C1 question $($sample.questionItemId) has no downloadable source image"
        $score = if ($null -eq $detail.defaultScore) { 4 } else { [decimal] $detail.defaultScore }
        $basketItems += [ordered]@{
            questionItemId = [string] $detail.id
            sectionNo = 1
            questionNo = $displayQuestionNo
            subQuestionNo = $null
            score = $score
            sortOrder = $sortOrder
        }
        $questionArtifacts += ConvertTo-QuestionArtifact -Detail $detail -Card $card -QuestionNo $displayQuestionNo -Score $score -Year ([int] $sample.year) -ImagePaths $imagePaths
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
    Assert-True ([string] $successPreflight.status -eq 'ready_for_review') "REAL005C1 success basket preflight must be ready_for_review; status=$([string] $successPreflight.status); issueCounts=$($successPreflight.issueCounts | ConvertTo-Json -Compress)"
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
        basketTitle = '2016-2025 年广州中考物理真题抽样卷'
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
        title = 'REAL005C1 2015 missing-solution anomaly export preflight'
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
    Assert-True ([bool] $anomalyFirstItem.hasAnswer) 'REAL005C1 anomaly must keep its extracted answer while solution is missing'
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

    Invoke-CommandSql -Sql $rollbackSql
    $rollbackApplied = $true
    $postRollbackRow = @(Invoke-RowSql -Sql @"
select concat_ws('|',
  count(*) filter (where status='pending_review'),
  count(*) filter (where primary_knowledge_id is null),
  count(*) filter (where coalesce((custom_fields->>'productionEligible')::boolean,false)=false),
  (select count(*) from review_queue_items where payload->>'sourceWorkflowKey'='$workflowKey' and status='open'),
  (select count(*) from paper_baskets where id in ('$($successBasket.id)','$($anomalyBasket.id)')),
  (select count(*) from knowledge_nodes where id='$knowledgeId')
)
from question_items
where custom_fields->>'sourceWorkflowKey'='$workflowKey';
"@)
    Assert-True ($postRollbackRow.Count -eq 1) 'REAL005C1 post-rollback invariant query failed'
    $postRollbackParts = $postRollbackRow[0] -split '\|', 6
    Assert-True (($postRollbackParts[0..3] -join '|') -eq '234|234|234|234') 'REAL005C1 did not restore all Guangzhou v2 pending-review invariants'
    Assert-True (($postRollbackParts[4..5] -join '|') -eq '0|0') 'REAL005C1 temporary basket or knowledge node remains after rollback'

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
        transientActiveWrite = $true
        activeWrite = $false
        rollbackApplied = $rollbackApplied
        backupManifest = (Resolve-Path -LiteralPath $BackupManifest).Path
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
            candidateFilters = [ordered]@{
                questionItemId = $candidateFilterSample.questionItemId
                year = $candidateFilterSample.year
                questionNo = $candidateFilterSample.questionNo
                questionType = $candidateFilterSample.questionType
                knowledgeCandidateId = $candidateFilterSample.knowledgeCandidateId
                examPointCandidateId = $candidateFilterSample.examPointCandidateId
                difficultyMin = $difficultyMin
                difficultyMax = $difficultyMax
                hasImage = [bool] @($candidateSearch.items)[0].hasImage
                total = [int] $candidateSearch.total
                wrongYearExcludesSelectedQuestion = $true
            }
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
        boundary = 'Repo-side reversible RG010 smoke only: it temporarily qualifies v2 pending-review samples for API exercise, generates draft Word/PDF artifacts, and restores every database mutation before reporting. It does not simulate or persist teacher approval. The 2015 answer-present/solution-missing sample remains blocked, and REAL005 stays not_closed.'
        summaryChinese = '2016-2025 v2 待审核真题仅在可逆 smoke 窗口内临时进入检索、题篮和 Word/PDF 草稿链；2015 有答案但缺解析样本仍被阻断，数据库已自动恢复，未留下教师确认或 active 写入。'
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
    if (-not $rollbackApplied -and $questionSnapshots.Count -gt 0) {
        $emergencyLines = [System.Collections.Generic.List[string]]::new()
        $emergencyLines.Add('begin;') | Out-Null
        foreach ($basket in @($successBasket, $anomalyBasket)) {
            if ($null -ne $basket -and -not [string]::IsNullOrWhiteSpace([string] $basket.id)) {
                $emergencyLines.Add("delete from paper_baskets where id='$([string] $basket.id)';") | Out-Null
            }
        }
        $emergencyLines.Add("delete from review_queue_items where payload::text like '%$reasonToken%';") | Out-Null
        if (-not [string]::IsNullOrWhiteSpace($knowledgeId)) {
            $emergencyLines.Add("delete from knowledge_mappings where knowledge_node_id='$knowledgeId';") | Out-Null
        }
        foreach ($questionId in $allSelectedQuestionIds) {
            $snapshot = $questionSnapshots[[string] $questionId]
            $primaryKnowledgeSql = if ([string]::IsNullOrWhiteSpace([string] $snapshot.primaryKnowledgeId)) { 'null' } else { "'$([string] $snapshot.primaryKnowledgeId)'" }
            $emergencyLines.Add("update question_items set status=$(ConvertTo-SqlStringLiteral ([string] $snapshot.status)), primary_knowledge_id=$primaryKnowledgeSql, custom_fields=$(ConvertTo-SqlStringLiteral ([string] $snapshot.customFieldsJson))::jsonb where id='$questionId';") | Out-Null
        }
        foreach ($sourceDocumentId in @($sourceSnapshots.Keys)) {
            $snapshot = $sourceSnapshots[[string] $sourceDocumentId]
            $emergencyLines.Add("update source_documents set license_or_permission=$(ConvertTo-SqlStringLiteral ([string] $snapshot.licenseOrPermission)), sharing_allowed=$([string] $snapshot.sharingAllowed), contains_student_pii=$([string] $snapshot.containsStudentPii), anonymization_status=$(ConvertTo-SqlStringLiteral ([string] $snapshot.anonymizationStatus)), external_ai_allowed=$([string] $snapshot.externalAiAllowed), may_use_for_exam_point_extraction=$([string] $snapshot.mayUseForExamPointExtraction), may_use_for_knowledge_extraction=$([string] $snapshot.mayUseForKnowledgeExtraction), may_use_for_trend_analysis=$([string] $snapshot.mayUseForTrendAnalysis) where id='$sourceDocumentId';") | Out-Null
        }
        if (-not [string]::IsNullOrWhiteSpace($knowledgeId)) {
            $emergencyLines.Add("delete from knowledge_nodes where id='$knowledgeId';") | Out-Null
        }
        $emergencyLines.Add('commit;') | Out-Null
        Invoke-CommandSql -Sql ([string]::Join("`r`n", $emergencyLines))
    }
    $env:KQG_CONNECTION_STRING = $previousConnectionString
    if ($pushedLocation) {
        Pop-Location
    }
}

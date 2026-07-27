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
    [string] $ReportPath = '',
    [string] $MarkdownReportPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for REAL005C2 analysis reference smoke'
}

$runDate = Get-Date -Format 'yyyyMMdd'
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = ('docs/evidence/{0}-real005c2-real-question-analysis-reference-smoke.json' -f $runDate)
}
if ([string]::IsNullOrWhiteSpace($MarkdownReportPath)) {
    $MarkdownReportPath = ('docs/evidence/{0}-real005c2-real-question-analysis-reference-smoke.md' -f $runDate)
}

$workflowKey = 'guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1'
$reasonToken = 'real005c2_analysis_reference_smoke'
$successYears = @(2016, 2017, 2018, 2019)

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
        throw "REAL005C2 SQL failed: $Sql"
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
            throw "REAL005C2 command SQL failed: $(Get-Content -LiteralPath $errPath -Raw)"
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

function Join-IdsForSql {
    param([string[]] $Ids)
    return ($Ids | ForEach-Object { "'" + $_ + "'" }) -join ', '
}

$requestedApiPort = $ApiPort
if ($ApiPort -le 0) {
    $ApiPort = Get-FreeTcpPort
}

$apiUrl = "http://127.0.0.1:$ApiPort"
$logOut = Join-Path $repoRoot 'docs/evidence/real005c2-analysis-reference-api.out.log'
$logErr = Join-Path $repoRoot 'docs/evidence/real005c2-analysis-reference-api.err.log'
$previousConnectionString = $env:KQG_CONNECTION_STRING
$env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
$process = $null
$pushedLocation = $false
$rollbackSql = ''
$rollbackApplied = $false
$knowledgeId = ''
$assessmentId = ''
$studentIds = @()
$questionSnapshots = @{}
$allQuestionIds = @()

$backupVerification = & (Join-Path $PSScriptRoot 'verify-backup.ps1') -ManifestPath $BackupManifest | ConvertFrom-Json
Assert-True ([string] $backupVerification.status -eq 'ok') 'REAL005C2 backup verification failed'

try {
    Push-Location $repoRoot
    $pushedLocation = $true

    & pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-real005c1-real-question-search-paper-export-smoke.ps1 -BackupManifest $BackupManifest | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'REAL005C2 prerequisite REAL005C1 smoke failed'
    }

    $successRows = @(
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
    and coalesce(qi.custom_fields->'answer'->>'value','') <> ''
)
select year::text || '|' || question_no || '|' || question_id
from ranked
where rn = 1
order by year;
"@
    )
    $successSamples = foreach ($row in $successRows) {
        $parts = $row -split '\|', 3
        [pscustomobject]@{
            year = [int] $parts[0]
            questionNo = [int] $parts[1]
            questionId = [string] $parts[2]
        }
    }
    $selectedSuccessSamples = @($successSamples | Where-Object { $successYears -contains $_.year })
    Assert-True ($selectedSuccessSamples.Count -eq $successYears.Count) "REAL005C2 expected success samples for years $($successYears -join ',')"

    $anomalyRow = @(
        Invoke-RowSql -Sql @"
select sd.year::text || '|' || coalesce(qi.custom_fields->>'questionNo','') || '|' || qi.id::text
from question_items qi
join source_documents sd on sd.id = (qi.custom_fields->>'sourceDocumentId')::uuid
where coalesce(qi.custom_fields->>'sourceWorkflowKey','') = '$workflowKey'
  and sd.year = 2021
  and qi.primary_knowledge_id is null
order by nullif(qi.custom_fields->>'questionNo','')::int nulls last, qi.id
limit 1;
"@
    )
    Assert-True ($anomalyRow.Count -eq 1) 'REAL005C2 expected one anomaly sample without primary knowledge'
    $anomalyParts = $anomalyRow[0] -split '\|', 3
    $anomalySample = [pscustomobject]@{
        year = [int] $anomalyParts[0]
        questionNo = [int] $anomalyParts[1]
        questionId = [string] $anomalyParts[2]
    }

    $successQuestionIds = @($selectedSuccessSamples | ForEach-Object { [string] $_.questionId })
    $allQuestionIds = $successQuestionIds + @([string] $anomalySample.questionId)
    $selectedIdsSql = Join-IdsForSql -Ids $allQuestionIds

    $questionSnapshotRows = @(
        Invoke-RowSql -Sql @"
select
  qi.id::text,
  coalesce(qi.status,''),
  coalesce(qi.primary_knowledge_id::text,''),
  coalesce(qi.custom_fields::text,'')
from question_items qi
where qi.id in ($selectedIdsSql)
order by qi.id;
"@
    )
    foreach ($row in $questionSnapshotRows) {
        $parts = $row -split '\|', 4
        $questionSnapshots[[string] $parts[0]] = [ordered]@{
            id = [string] $parts[0]
            status = [string] $parts[1]
            primaryKnowledgeId = if ([string]::IsNullOrWhiteSpace([string] $parts[2])) { $null } else { [string] $parts[2] }
            customFieldsJson = [string] $parts[3]
        }
    }
    Assert-True ($questionSnapshots.Count -eq $allQuestionIds.Count) "REAL005C2 question snapshot count mismatch: expected $($allQuestionIds.Count), actual $($questionSnapshots.Count)"

    $assessmentKey = "real005c2-$((Get-Date).ToString('yyyyMMddHHmmss'))"
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

    $knowledgeId = [Guid]::NewGuid().ToString()
    $knowledgeCode = 'REAL005C2-ACTIVE-' + [Guid]::NewGuid().ToString('N').Substring(0, 8).ToUpperInvariant()
    Invoke-ScalarSql -Sql @"
insert into knowledge_nodes (
  id, subject, stage, code, title, node_type, level, status, version, metadata, created_at, updated_at
)
values (
  '$knowledgeId',
  'physics',
  'junior_middle_school',
  '$knowledgeCode',
  'REAL005C2 RG011 Active Seed',
  'concept',
  2,
  'active',
  1,
  '{"task":"REAL005C2","criterion":"RG011","reason":"$reasonToken"}',
  now(),
  now()
);
"@ | Out-Null

    $promotedSuccessSamples = New-Object System.Collections.Generic.List[object]
    foreach ($sample in $selectedSuccessSamples) {
        $detail = Invoke-RestMethod -Method Get -Uri "$apiUrl/questions/$($sample.questionId)" -TimeoutSec 10
        $patchBody = [ordered]@{
            status = 'usable'
            primaryKnowledgeId = $knowledgeId
            reviewedBy = 'real005c2-smoke'
            reason = $reasonToken + '_promote_success_sample'
        } | ConvertTo-Json -Depth 6
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

    $importBody = [ordered]@{
        assessmentKey = $assessmentKey
        assessmentTitle = 'REAL005C2 reviewed real question analysis smoke'
        subject = 'physics'
        stage = 'junior_middle_school'
        grade = 'grade_9'
        templateKey = 'real005c2-score-template-v1'
        templateDisplayName = 'REAL005C2 score template'
        sourceFileName = 'real005c2-score-import.xlsx'
        containsStudentPii = $false
        productionEligible = $false
        maxTotalScore = 100
        fieldMapping = [ordered]@{
            studentKey = 'student_code'
            totalScore = 'total_score'
            itemScores = [ordered]@{
                Q1 = 'q1_score'
                Q2 = 'q2_score'
                Q3 = 'q3_score'
                Q4 = 'q4_score'
            }
        }
        itemMaxScores = [ordered]@{
            Q1 = 25
            Q2 = 25
            Q3 = 25
            Q4 = 25
        }
        rows = @(
            @{ rowNumber = 2; values = @{ student_code = 'REAL005C2-001'; total_score = '90'; q1_score = '24'; q2_score = '23'; q3_score = '22'; q4_score = '21' } },
            @{ rowNumber = 3; values = @{ student_code = 'REAL005C2-002'; total_score = '78'; q1_score = '20'; q2_score = '19'; q3_score = '18'; q4_score = '21' } },
            @{ rowNumber = 4; values = @{ student_code = 'REAL005C2-003'; total_score = '63'; q1_score = '16'; q2_score = '15'; q3_score = '14'; q4_score = '18' } }
        )
    } | ConvertTo-Json -Depth 10
    $import = Invoke-RestMethod -Method Post -Uri "$apiUrl/score-imports" -ContentType 'application/json' -Body $importBody -TimeoutSec 10
    Assert-True ([string] $import.status -eq 'imported') 'REAL005C2 score import should succeed'
    Assert-True (-not [bool] $import.productionEligible) 'REAL005C2 score import must stay non-production'
    Assert-True (-not [bool] $import.realStudentDataUsed) 'REAL005C2 score import must not use real student data'
    $assessmentId = [string] $import.assessmentId
    $studentIds = @(
        Invoke-RowSql -Sql "select distinct student_id::text from score_records where assessment_id='$assessmentId' order by student_id;"
    )
    Assert-True ($studentIds.Count -eq 3) 'REAL005C2 expected three synthetic students'

    $mappingEntries = @()
    $itemIndex = 1
    foreach ($sample in @($promotedSuccessSamples | Sort-Object year, questionNo)) {
        $mappingEntries += [ordered]@{
            questionNo = "Q$itemIndex"
            questionItemId = [string] $sample.questionItemId
        }
        $itemIndex += 1
    }
    $exportBody = [ordered]@{
        format = 'md'
        allowAiDraftText = $false
        mappings = $mappingEntries
    } | ConvertTo-Json -Depth 8
    $export = Invoke-RestMethod -Method Post -Uri "$apiUrl/assessments/$assessmentId/commentary-report/export" -ContentType 'application/json' -Body $exportBody -TimeoutSec 10
    Assert-True ([string] $export.status -eq 'ready') 'REAL005C2 commentary export should be ready'
    Assert-True ([string] $export.mode -eq 'draft_test') 'REAL005C2 commentary export must stay draft_test'
    Assert-True (-not [bool] $export.productionEligible) 'REAL005C2 commentary export must stay non-production'
    Assert-True (-not [bool] $export.realStudentDataUsed) 'REAL005C2 commentary export must not use real student data'
    Assert-True (-not [bool] $export.writesProductionHistory) 'REAL005C2 commentary export must not write production history'
    Assert-True (-not [bool] $export.allowAiDraftText) 'REAL005C2 smoke keeps AI draft text disabled'
    Assert-True (@($export.blockingIssues).Count -eq 0) 'REAL005C2 success export must not keep blocking issues'

    $weakQuestionNos = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in @($export.weakKnowledgePoints)) {
        [void] $weakQuestionNos.Add([string] $row.questionNo)
        Assert-True ([int] $row.version -eq 1) "REAL005C2 weak knowledge point must keep active knowledge version=1 for question $($row.questionNo)"
        Assert-True (-not [string]::IsNullOrWhiteSpace([string] $row.knowledgeNodeId)) "REAL005C2 weak knowledge point missing knowledgeNodeId for question $($row.questionNo)"
    }
    Assert-True ($weakQuestionNos.Count -ge 1) 'REAL005C2 weak knowledge point list must not be empty'

    $previewSuccessBody = [ordered]@{
        mappings = $mappingEntries
    } | ConvertTo-Json -Depth 6
    $mappingPreview = Invoke-RestMethod -Method Post -Uri "$apiUrl/assessments/$assessmentId/item-score-mappings/preview" -ContentType 'application/json' -Body $previewSuccessBody -TimeoutSec 10
    Assert-True ([int] $mappingPreview.unclearCount -eq 0) 'REAL005C2 success mapping preview must be fully mapped'
    Assert-True (-not [bool] $mappingPreview.writesProductionHistory) 'REAL005C2 mapping preview must not write production history'

    $blockedPreviewBody = [ordered]@{
        mappings = @(
            @{ questionNo = 'Q1'; questionItemId = [string] $anomalySample.questionId }
        )
    } | ConvertTo-Json -Depth 6
    $blockedPreview = Invoke-RestMethod -Method Post -Uri "$apiUrl/assessments/$assessmentId/item-score-mappings/preview" -ContentType 'application/json' -Body $blockedPreviewBody -TimeoutSec 10
    Assert-True ([int] $blockedPreview.unclearCount -ge 1) 'REAL005C2 blocked mapping preview must expose unclear mappings'
    $blockedExportBody = [ordered]@{
        format = 'md'
        allowAiDraftText = $false
        mappings = @(
            @{ questionNo = 'Q1'; questionItemId = [string] $anomalySample.questionId }
        )
    } | ConvertTo-Json -Depth 6
    $blockedExport = Invoke-RestMethod -Method Post -Uri "$apiUrl/assessments/$assessmentId/commentary-report/export" -ContentType 'application/json' -Body $blockedExportBody -TimeoutSec 10 -SkipHttpErrorCheck
    Assert-True ([string] $blockedExport.status -eq 'blocked') 'REAL005C2 blocked export must stay blocked'
    Assert-True (-not [bool] $blockedExport.writesProductionHistory) 'REAL005C2 blocked export must not write production history'
    Assert-True (-not [bool] $blockedExport.allowAiDraftText) 'REAL005C2 blocked export must not allow AI draft text'
    $blockedIssueCodes = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($issue in @($blockedExport.blockingIssues)) {
        foreach ($code in @($issue.codes)) {
            [void] $blockedIssueCodes.Add([string] $code)
        }
    }
    Assert-True ($blockedIssueCodes.Contains('knowledge_mapping_missing')) 'REAL005C2 blocked export must expose knowledge_mapping_missing'

    $successQuestionIdsSql = Join-IdsForSql -Ids $successQuestionIds
    $assessmentSnapshotRows = @(
        Invoke-RowSql -Sql @"
select id::text, assessment_key, status, mode, production_eligible::text, synthetic_fixture::text, contains_student_pii::text
from assessments
where id = '$assessmentId';
"@
    )
    Assert-True ($assessmentSnapshotRows.Count -eq 1) 'REAL005C2 assessment snapshot missing'
    $studentIdsSql = Join-IdsForSql -Ids $studentIds

    $questionRollbackLines = New-Object System.Collections.Generic.List[string]
    foreach ($questionId in $allQuestionIds) {
        $snapshot = $questionSnapshots[$questionId]
        $primaryKnowledgeSql = if ([string]::IsNullOrWhiteSpace([string] $snapshot.primaryKnowledgeId)) { 'null' } else { "'" + [string] $snapshot.primaryKnowledgeId + "'" }
        $questionRollbackLines.Add(
            "update question_items set status = $(ConvertTo-SqlStringLiteral -Value ([string] $snapshot.status)), primary_knowledge_id = $primaryKnowledgeSql, custom_fields = $(ConvertTo-SqlStringLiteral -Value ([string] $snapshot.customFieldsJson))::jsonb where id = '$questionId';"
        ) | Out-Null
    }

    $rollbackLines = New-Object System.Collections.Generic.List[string]
    $rollbackLines.Add('begin;') | Out-Null
    $rollbackLines.Add("delete from item_scores where score_record_id in (select id from score_records where assessment_id = '$assessmentId');") | Out-Null
    $rollbackLines.Add("delete from score_records where assessment_id = '$assessmentId';") | Out-Null
    $rollbackLines.Add("delete from score_import_batches where assessment_id = '$assessmentId';") | Out-Null
    $rollbackLines.Add("delete from assessments where id = '$assessmentId';") | Out-Null
    $rollbackLines.Add("delete from students where id in ($studentIdsSql) and not exists (select 1 from score_records where score_records.student_id=students.id) and not exists (select 1 from assessment_enrollments where assessment_enrollments.student_id=students.id);") | Out-Null
    $rollbackLines.Add("delete from score_import_templates where template_key like 'real005c2-score-template-v1%';") | Out-Null
    $rollbackLines.Add("delete from review_queue_items where payload::text like '%$reasonToken%';") | Out-Null
    $rollbackLines.Add("delete from knowledge_mappings where question_item_id in ($successQuestionIdsSql) and knowledge_node_id = '$knowledgeId';") | Out-Null
    foreach ($line in $questionRollbackLines) {
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
  (select count(*) from assessments where id='$assessmentId'),
  (select count(*) from knowledge_nodes where id='$knowledgeId'),
  (select count(*) from students where id in ($studentIdsSql))
)
from question_items
where custom_fields->>'sourceWorkflowKey'='$workflowKey';
"@)
    Assert-True ($postRollbackRow.Count -eq 1) 'REAL005C2 post-rollback invariant query failed'
    $postRollbackParts = $postRollbackRow[0] -split '\|', 7
    Assert-True (($postRollbackParts[0..3] -join '|') -eq '234|234|234|234') 'REAL005C2 did not restore all Guangzhou v2 pending-review invariants'
    Assert-True (($postRollbackParts[4..6] -join '|') -eq '0|0|0') 'REAL005C2 temporary assessment, knowledge node, or students remain after rollback'

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
        taskId = 'REAL005C2_REAL_QUESTION_ANALYSIS_REFERENCE_SMOKE'
        criterionId = 'RG011'
        rg011Status = 'pass'
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
        assessmentId = $assessmentId
        sampleStrategy = [ordered]@{
            successYears = $successYears
            successSampleCount = $promotedSuccessSampleReports.Count
            anomalyYear = $anomalySample.year
            anomalyQuestionNo = $anomalySample.questionNo
        }
        promotedSuccessSamples = $promotedSuccessSampleReports
        anomalySample = [ordered]@{
            year = $anomalySample.year
            questionNo = $anomalySample.questionNo
            questionItemId = $anomalySample.questionId
        }
        scoreImport = [ordered]@{
            status = [string] $import.status
            assessmentId = [string] $import.assessmentId
            importedCount = [int] $import.importedCount
            rowCount = [int] $import.rowCount
            errorCount = [int] $import.errorCount
            productionEligible = [bool] $import.productionEligible
            realStudentDataUsed = [bool] $import.realStudentDataUsed
        }
        mappingPreview = [ordered]@{
            mappedCount = [int] $mappingPreview.mappedCount
            unclearCount = [int] $mappingPreview.unclearCount
            writesProductionHistory = [bool] $mappingPreview.writesProductionHistory
        }
        successExport = [ordered]@{
            status = [string] $export.status
            writesProductionHistory = [bool] $export.writesProductionHistory
            allowAiDraftText = [bool] $export.allowAiDraftText
            weakKnowledgePointCount = @($export.weakKnowledgePoints).Count
            practiceSuggestionCount = @($export.practiceSuggestions).Count
            blockingIssueCount = @($export.blockingIssues).Count
            artifactPath = [string] $export.artifactPath
            manifestSha256 = [string] $export.manifestSha256
            auditTrail = @($export.auditTrail)
        }
        blockedExport = [ordered]@{
            status = [string] $blockedExport.status
            writesProductionHistory = [bool] $blockedExport.writesProductionHistory
            allowAiDraftText = [bool] $blockedExport.allowAiDraftText
            blockingIssueCodes = @($blockedIssueCodes)
        }
        rollbackSql = $rollbackSql
        boundary = 'Repo-side reversible RG011 smoke only: it uses anonymous synthetic scores and temporarily qualified v2 pending-review samples, then restores every database mutation before reporting. It does not simulate teacher approval, use real student data, or write production history. REAL005 remains not_closed.'
        summaryChinese = 'v2 待审核真题仅在可逆 smoke 窗口内驱动匿名 synthetic 成绩、小题映射和确定性讲评导出；缺主知识点样本继续阻断，数据库已自动恢复，未留下教师确认、真实学生数据或正式历史。'
    }

    $reportFullPath = Join-Path $repoRoot ($ReportPath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $markdownFullPath = Join-Path $repoRoot ($MarkdownReportPath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $finalReport | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    @(
        '# REAL005C2 Reviewed Real Question Analysis Reference Smoke',
        '',
        "- status: $($finalReport.status)",
        "- criterion_id: $($finalReport.criterionId)",
        "- rg011_status: $($finalReport.rg011Status)",
        "- success_sample_count: $($finalReport.sampleStrategy.successSampleCount)",
        "- success_export_status: $($finalReport.successExport.status)",
        "- blocked_export_status: $($finalReport.blockedExport.status)",
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
        if (-not [string]::IsNullOrWhiteSpace($assessmentId)) {
            $emergencyLines.Add("delete from assessments where id='$assessmentId';") | Out-Null
        }
        if ($studentIds.Count -gt 0) {
            $emergencyStudentIdsSql = Join-IdsForSql -Ids $studentIds
            $emergencyLines.Add("delete from students where id in ($emergencyStudentIdsSql) and not exists (select 1 from score_records where score_records.student_id=students.id) and not exists (select 1 from assessment_enrollments where assessment_enrollments.student_id=students.id);") | Out-Null
        }
        $emergencyLines.Add("delete from score_import_templates where template_key like 'real005c2-score-template-v1%';") | Out-Null
        $emergencyLines.Add("delete from review_queue_items where payload::text like '%$reasonToken%';") | Out-Null
        if (-not [string]::IsNullOrWhiteSpace($knowledgeId)) {
            $emergencyLines.Add("delete from knowledge_mappings where knowledge_node_id='$knowledgeId';") | Out-Null
        }
        foreach ($questionId in $allQuestionIds) {
            $snapshot = $questionSnapshots[[string] $questionId]
            $primaryKnowledgeSql = if ([string]::IsNullOrWhiteSpace([string] $snapshot.primaryKnowledgeId)) { 'null' } else { "'$([string] $snapshot.primaryKnowledgeId)'" }
            $emergencyLines.Add("update question_items set status=$(ConvertTo-SqlStringLiteral ([string] $snapshot.status)), primary_knowledge_id=$primaryKnowledgeSql, custom_fields=$(ConvertTo-SqlStringLiteral ([string] $snapshot.customFieldsJson))::jsonb where id='$questionId';") | Out-Null
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

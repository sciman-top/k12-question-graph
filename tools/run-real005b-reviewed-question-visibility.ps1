param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $ReportPath = '',
    [string] $MarkdownReportPath = '',
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runDate = Get-Date -Format 'yyyyMMdd'
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = ('docs/evidence/{0}-real005b-reviewed-question-visibility.json' -f $runDate)
}

if ([string]::IsNullOrWhiteSpace($MarkdownReportPath)) {
    $MarkdownReportPath = ('docs/evidence/{0}-real005b-reviewed-question-visibility.md' -f $runDate)
}

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for REAL005B reviewed-question visibility diagnostics'
}

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Invoke-QueryRows([string] $Sql) {
    $psql = Join-Path $PgBin 'psql.exe'
    if (-not (Test-Path -LiteralPath $psql)) {
        throw "psql not found: $psql"
    }

    $output = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -F '|' -v ON_ERROR_STOP=1 -c $Sql
    if ($LASTEXITCODE -ne 0) {
        throw "REAL005B reviewed-question visibility SQL failed: $Sql"
    }

    $text = ($output | Out-String)
    return @(
        ($text -split "`r?`n") |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function ConvertTo-RowObjects([string[]] $Rows, [string[]] $Columns) {
    $result = @()
    foreach ($row in $Rows) {
        $parts = @($row -split '\|', $Columns.Count)
        $item = [ordered]@{}
        for ($index = 0; $index -lt $Columns.Count; $index++) {
            $value = if ($index -lt $parts.Count) { $parts[$index].Trim() } else { '' }
            $item[$Columns[$index]] = $value
        }
        $result += [pscustomobject] $item
    }
    return $result
}

function ConvertTo-ScalarInt([string[]] $Rows) {
    if ($Rows.Count -le 0) {
        return 0
    }

    return [int]([string]($Rows | Select-Object -First 1)).Trim()
}

$statusRows = ConvertTo-RowObjects `
    -Rows (Invoke-QueryRows "select status, count(*) from question_items group by status order by status;") `
    -Columns @('status', 'count')

$workflowRows = ConvertTo-RowObjects `
    -Rows (Invoke-QueryRows @"
select
  coalesce(custom_fields->>'sourceWorkflowKey','<null>') as workflow_key,
  status,
  count(*)
from question_items
group by workflow_key, status
order by workflow_key, status;
"@) `
    -Columns @('workflowKey', 'status', 'count')

$usableRows = ConvertTo-RowObjects `
    -Rows (Invoke-QueryRows @"
select
  id::text,
  status,
  coalesce(custom_fields->>'questionNo', ''),
  coalesce(custom_fields->>'sourceWorkflowKey','<null>'),
  coalesce(custom_fields->>'sourceDocumentId','')
from question_items
where status = 'usable'
order by updated_at desc
limit 20;
"@) `
    -Columns @('id', 'status', 'questionNo', 'workflowKey', 'sourceDocumentId')

$guangzhouNon2015Rows = Invoke-QueryRows @"
select count(*)
from question_items
where coalesce(custom_fields->>'sourceWorkflowKey','') like 'guangzhou_%'
  and coalesce(custom_fields->>'sourceWorkflowKey','') not in ('guangzhou_2015_real_ingest_v1','guangzhou_2015_visual_region_v1');
"@
$guangzhouNon2015QuestionCount = ConvertTo-ScalarInt $guangzhouNon2015Rows

$sourceDocumentRows = Invoke-QueryRows "select count(*) from source_documents where year between 2016 and 2025;"
$sourceDocumentCount2016_2025 = ConvertTo-ScalarInt $sourceDocumentRows

$sourceRegionRows = Invoke-QueryRows @"
select count(*)
from source_regions sr
join source_documents sd on sd.id = sr.source_document_id
where sd.year between 2016 and 2025;
"@
$sourceRegionCount2016_2025 = ConvertTo-ScalarInt $sourceRegionRows

$usableWorkflowSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($row in $usableRows) {
    [void]$usableWorkflowSet.Add([string]$row.workflowKey)
}

$hasOnly2015UsableQuestions = $usableWorkflowSet.Count -eq 1 -and $usableWorkflowSet.Contains('guangzhou_2015_real_ingest_v1')
$hasApiVisible2016_2025ReviewedQuestions = $guangzhouNon2015QuestionCount -gt 0
$visibilityClosureReady = $hasApiVisible2016_2025ReviewedQuestions -and $sourceRegionCount2016_2025 -gt 0

$blockers = @()
if (-not $hasApiVisible2016_2025ReviewedQuestions) {
    $blockers += 'no_2016_2025_real_questions_materialized_into_question_items'
}
if ($sourceRegionCount2016_2025 -le 0) {
    $blockers += 'no_2016_2025_source_regions_materialized_for_api_source_review'
}

$report = [ordered]@{
    status = 'pass'
    taskId = 'REAL005B_REVIEWED_QUESTION_VISIBILITY'
    checkedAt = (Get-Date).ToString('s')
    activeWrite = $false
    externalAiCalls = 0
    realStudentDataUsed = $false
    sourceEvidence = @(
        'guangzhou-physics-full-research-package-2016-2025/csv/c003-evidence-index.csv',
        'guangzhou-physics-full-research-package-2016-2025/quality-review-complete-csv-package/c003-quality-issue-review-evidence.csv',
        'guangzhou-physics-full-research-package-2016-2025/quality-review-complete-csv-package/c003-quality-issue-registry.csv'
    )
    questionStatusCounts = @($statusRows | ForEach-Object {
        [ordered]@{
            status = [string]$_.status
            count = [int]$_.count
        }
    })
    workflowStatusCounts = @($workflowRows | ForEach-Object {
        [ordered]@{
            workflowKey = [string]$_.workflowKey
            status = [string]$_.status
            count = [int]$_.count
        }
    })
    usableQuestionSample = @($usableRows | ForEach-Object {
        [ordered]@{
            id = [string]$_.id
            status = [string]$_.status
            questionNo = if ([string]::IsNullOrWhiteSpace([string]$_.questionNo)) { $null } else { [int]$_.questionNo }
            workflowKey = [string]$_.workflowKey
            sourceDocumentId = if ([string]::IsNullOrWhiteSpace([string]$_.sourceDocumentId)) { $null } else { [string]$_.sourceDocumentId }
        }
    })
    sourceDocumentCount2016_2025 = $sourceDocumentCount2016_2025
    sourceRegionCount2016_2025 = $sourceRegionCount2016_2025
    guangzhouNon2015QuestionCount = $guangzhouNon2015QuestionCount
    hasOnly2015UsableQuestions = $hasOnly2015UsableQuestions
    hasApiVisible2016_2025ReviewedQuestions = $hasApiVisible2016_2025ReviewedQuestions
    visibilityClosureReady = $visibilityClosureReady
    blockers = @($blockers)
    conclusion = if ($visibilityClosureReady) {
        '2016-2025 reviewed real questions are materialized into API-visible question/source state.'
    }
    else {
        '2016-2025 quality-review CSV evidence exists, but current database/API state does not expose reviewed real questions for RG009 save/detail/source-review smoke.'
    }
    rollback = 'No rollback required; this diagnostic is read-only.'
}

$reportFullPath = Join-Path $repoRoot ($ReportPath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
$markdownFullPath = Join-Path $repoRoot ($MarkdownReportPath -replace '/', [System.IO.Path]::DirectorySeparatorChar)

New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8

$lines = @(
    '# REAL005B Reviewed Question Visibility',
    '',
    "- status: $($report.status)",
    "- checked_at: $($report.checkedAt)",
    "- api_visible_2016_2025_reviewed_questions: $($report.hasApiVisible2016_2025ReviewedQuestions)",
    "- source_document_count_2016_2025: $($report.sourceDocumentCount2016_2025)",
    "- source_region_count_2016_2025: $($report.sourceRegionCount2016_2025)",
    "- guangzhou_non_2015_question_count: $($report.guangzhouNon2015QuestionCount)",
    '',
    '## Conclusion',
    $report.conclusion,
    '',
    '## Blockers'
)

if (@($report.blockers).Count -eq 0) {
    $lines += '- none'
}
else {
    foreach ($blocker in @($report.blockers)) {
        $lines += "- $blocker"
    }
}

$lines += ''
$lines += '## Usable Question Sample'
if (@($report.usableQuestionSample).Count -eq 0) {
    $lines += '- none'
}
else {
    foreach ($row in @($report.usableQuestionSample)) {
        $lines += "- id=$($row.id); status=$($row.status); questionNo=$($row.questionNo); workflowKey=$($row.workflowKey)"
    }
}

$lines += ''
$lines += '## Boundary'
$lines += 'This diagnostic reads PostgreSQL state and existing CSV evidence only. It does not create, update, review, or promote any question, source, or audit row.'

$lines | Set-Content -LiteralPath $markdownFullPath -Encoding UTF8

$report | ConvertTo-Json -Depth 10

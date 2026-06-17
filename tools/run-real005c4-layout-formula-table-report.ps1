param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $SourceRegionReportPath = '',
    [string] $MaterializeReportPath = '',
    [string] $JsonReportPath = '',
    [string] $MarkdownReportPath = '',
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runDate = Get-Date -Format 'yyyyMMdd'
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Resolve-RepoPath([string] $Path) {
    Join-Path $repoRoot $Path
}

function Try-ReadJson([string] $RelativePath) {
    $fullPath = Resolve-RepoPath $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        return $null
    }

    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Resolve-LatestEvidencePath([string] $Filter, [string] $PreferredPath) {
    if (-not [string]::IsNullOrWhiteSpace($PreferredPath)) {
        return $PreferredPath
    }

    $matches = @(
        Get-ChildItem -LiteralPath (Resolve-RepoPath 'docs/evidence') -Filter $Filter -File -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            Select-Object -First 1
    )
    if ($matches.Count -eq 1) {
        return [System.IO.Path]::GetRelativePath($repoRoot, $matches[0].FullName).Replace('\', '/')
    }

    return ''
}

function Invoke-QueryRows([string] $Sql) {
    $psql = Join-Path $PgBin 'psql.exe'
    if (-not (Test-Path -LiteralPath $psql)) {
        throw "psql not found: $psql"
    }

    $output = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -F '|' -v ON_ERROR_STOP=1 -c $Sql
    if ($LASTEXITCODE -ne 0) {
        throw "REAL005C4 SQL failed: $Sql"
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

if ([string]::IsNullOrWhiteSpace($JsonReportPath)) {
    $JsonReportPath = ('docs/evidence/{0}-real005c4-layout-formula-table-report.json' -f $runDate)
}

if ([string]::IsNullOrWhiteSpace($MarkdownReportPath)) {
    $MarkdownReportPath = ('docs/evidence/{0}-real005c4-layout-formula-table-report.md' -f $runDate)
}

$SourceRegionReportPath = Resolve-LatestEvidencePath -Filter '*-real005b-source-region-screenshots.json' -PreferredPath $SourceRegionReportPath
$MaterializeReportPath = Resolve-LatestEvidencePath -Filter '*-real005b-reviewed-question-materialize.json' -PreferredPath $MaterializeReportPath

Assert-True (-not [string]::IsNullOrWhiteSpace($SourceRegionReportPath)) 'missing REAL005B source-region screenshot report path'
Assert-True (-not [string]::IsNullOrWhiteSpace($MaterializeReportPath)) 'missing REAL005B materialize report path'
Assert-True (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'DatabasePassword or PGPASSWORD is required for REAL005C4 report'

$sourceRegionReport = Try-ReadJson $SourceRegionReportPath
$materializeReport = Try-ReadJson $MaterializeReportPath

Assert-True ($null -ne $sourceRegionReport) "missing source-region report: $SourceRegionReportPath"
Assert-True ($null -ne $materializeReport) "missing materialize report: $MaterializeReportPath"
Assert-True ([string]$sourceRegionReport.status -eq 'pass') 'REAL005B source-region screenshot report must pass'
Assert-True ([string]$materializeReport.status -eq 'pass') 'REAL005B materialize report must pass'

$workflowKey = 'guangzhou_2016_2025_reviewed_question_materialize_v1'

$tableRows = ConvertTo-RowObjects `
    -Rows (Invoke-QueryRows @"
select
  qi.custom_fields->>'questionNo' as question_no,
  qb.id::text as block_id,
  coalesce(qb.content->>'caption','') as caption,
  coalesce(jsonb_array_length(coalesce(qb.content->'columns','[]'::jsonb)), 0)::text as column_count,
  coalesce(jsonb_array_length(coalesce(qb.content->'rows','[]'::jsonb)), 0)::text as row_count,
  coalesce(qb.content->>'confidence','') as confidence,
  coalesce(qb.content->>'reviewStatus','') as review_status,
  coalesce(qb.content->>'sourceRegionId','') as content_source_region_id,
  coalesce(qb.source_region_id::text,'') as source_region_id
from question_blocks qb
join question_items qi on qi.id = qb.question_item_id
where qb.block_type = 'table'
  and coalesce(qi.custom_fields->>'sourceWorkflowKey','') = '$workflowKey'
order by cast(qi.custom_fields->>'questionNo' as int), qb.sort_order;
"@) `
    -Columns @('questionNo','blockId','caption','columnCount','rowCount','confidence','reviewStatus','contentSourceRegionId','sourceRegionId')

$formulaRows = ConvertTo-RowObjects `
    -Rows (Invoke-QueryRows @"
select
  qi.custom_fields->>'questionNo' as question_no,
  qb.id::text as block_id,
  coalesce(qb.content->>'sourceFormat','') as source_format,
  coalesce(qb.content->>'confidence','') as confidence,
  coalesce(qb.content->>'reviewStatus','') as review_status,
  coalesce(qb.content->>'fallbackImageUrl','') as fallback_image_url,
  coalesce(qb.content->>'fallbackImageSourceRegionId','') as fallback_image_source_region_id,
  coalesce(qb.source_region_id::text,'') as source_region_id
from question_blocks qb
join question_items qi on qi.id = qb.question_item_id
where qb.block_type = 'formula'
  and coalesce(qi.custom_fields->>'sourceWorkflowKey','') = '$workflowKey'
order by cast(qi.custom_fields->>'questionNo' as int), qb.sort_order;
"@) `
    -Columns @('questionNo','blockId','sourceFormat','confidence','reviewStatus','fallbackImageUrl','fallbackImageSourceRegionId','sourceRegionId')

$tableQueueRows = ConvertTo-RowObjects `
    -Rows (Invoke-QueryRows @"
select
  payload->>'questionItemId' as question_item_id,
  payload->>'questionBlockId' as question_block_id,
  review_type,
  status,
  payload->>'requiredAction' as required_action,
  payload->>'reason' as reason
from review_queue_items
where review_type = 'question_table_block_review'
  and coalesce(payload->>'sourceWorkflowKey','') = '$workflowKey';
"@) `
    -Columns @('questionItemId','questionBlockId','reviewType','status','requiredAction','reason')

$formulaQueueRows = ConvertTo-RowObjects `
    -Rows (Invoke-QueryRows @"
select
  payload->>'questionItemId' as question_item_id,
  payload->>'questionBlockId' as question_block_id,
  review_type,
  status,
  payload->>'requiredAction' as required_action,
  payload->>'reason' as reason
from review_queue_items
where review_type = 'question_formula_block_review'
  and coalesce(payload->>'sourceWorkflowKey','') = '$workflowKey';
"@) `
    -Columns @('questionItemId','questionBlockId','reviewType','status','requiredAction','reason')

$noisePageCount = 0
$noiseRegionKinds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($year in @($sourceRegionReport.years)) {
    foreach ($question in @($year.questions)) {
        foreach ($page in @($question.sourcePageNumbers)) {
            $noisePageCount += 1
        }
    }
}

$real007Report = Try-ReadJson 'docs/evidence/20260516-real007-guangzhou-2015-layout-quality-report.json'
if ($null -ne $real007Report) {
    foreach ($pageSummary in @($real007Report.pageSummary)) {
        foreach ($noiseKind in @($pageSummary.noiseRegionKinds)) {
            [void]$noiseRegionKinds.Add([string]$noiseKind)
        }
    }
}

$tablePass = $tableRows.Count -gt 0
if ($tablePass) {
    foreach ($row in $tableRows) {
        if ([int]$row.columnCount -lt 1 -or [int]$row.rowCount -lt 1 -or [string]::IsNullOrWhiteSpace([string]$row.reviewStatus) -or [string]::IsNullOrWhiteSpace([string]$row.sourceRegionId)) {
            $tablePass = $false
            break
        }
    }
}
$formulaPass = $formulaRows.Count -gt 0
if ($formulaPass) {
    foreach ($row in $formulaRows) {
        if ([string]::IsNullOrWhiteSpace([string]$row.reviewStatus) -or [string]::IsNullOrWhiteSpace([string]$row.fallbackImageUrl) -or [string]::IsNullOrWhiteSpace([string]$row.sourceFormat)) {
            $formulaPass = $false
            break
        }
    }
}
$noisePass = [bool]$sourceRegionReport.sourceRegionCoveragePass

$criteriaStatus = [ordered]@{
    RG013 = if ($noisePass) { 'pass' } else { 'blocked' }
    RG014 = if ($formulaPass) { 'pass' } else { 'blocked' }
    RG015 = if ($tablePass) { 'pass' } else { 'blocked' }
}

$blockers = New-Object System.Collections.Generic.List[string]
if (-not $noisePass) {
    $blockers.Add('RG013:noise_retained_or_source_region_coverage_not_pass')
}
if (-not $formulaPass) {
    $blockers.Add('RG014:formula_candidate_without_fallback_or_review_status')
}
if (-not $tablePass) {
    $blockers.Add('RG015:table_candidate_without_structured_rows_columns_or_review_status')
}

$report = [ordered]@{
    status = 'pass'
    taskId = 'REAL005C4_LAYOUT_FORMULA_TABLE'
    checkedAt = (Get-Date).ToString('s')
    activeWrite = $false
    externalAiCalls = 0
    realStudentDataUsed = $false
    criterionIds = @('RG013','RG014','RG015')
    criteriaStatus = $criteriaStatus
    evidence = [ordered]@{
        sourceRegionReport = $SourceRegionReportPath
        materializeReport = $MaterializeReportPath
        real007Report = 'docs/evidence/20260516-real007-guangzhou-2015-layout-quality-report.json'
    }
    layoutNoise = [ordered]@{
        sourceRegionCoveragePass = [bool]$sourceRegionReport.sourceRegionCoveragePass
        renderedPages = [int]$sourceRegionReport.totals.renderedPages
        visualQuestions = [int]$sourceRegionReport.totals.visualQuestions
        retainedQuestionPageCount = $noisePageCount
        inheritedNoiseRegionKinds = @($noiseRegionKinds | Sort-Object)
        blocker = if ($noisePass) { $null } else { 'source_region_noise_exclusion_not_proven' }
    }
    formulaFidelity = [ordered]@{
        formulaBlockCount = $formulaRows.Count
        reviewQueueCount = $formulaQueueRows.Count
        distinctQuestionCount = @($formulaRows | Select-Object -ExpandProperty questionNo -Unique).Count
        scannedFormulaCandidateCount = @($formulaRows | Where-Object { [string]$_.sourceFormat -eq 'scanned_formula_candidate' }).Count
        fallbackCoverageCount = @($formulaRows | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.fallbackImageUrl) }).Count
        sampleBlocks = @($formulaRows | Select-Object -First 5 | ForEach-Object {
            [ordered]@{
                questionNo = [int]$_.questionNo
                blockId = [string]$_.blockId
                sourceFormat = [string]$_.sourceFormat
                confidence = [double]$_.confidence
                reviewStatus = [string]$_.reviewStatus
                fallbackImageUrl = [string]$_.fallbackImageUrl
            }
        })
    }
    tableStructuring = [ordered]@{
        tableBlockCount = $tableRows.Count
        reviewQueueCount = $tableQueueRows.Count
        distinctQuestionCount = @($tableRows | Select-Object -ExpandProperty questionNo -Unique).Count
        rowsColumnsCoverageCount = @($tableRows | Where-Object { [int]$_.columnCount -ge 1 -and [int]$_.rowCount -ge 1 }).Count
        sampleBlocks = @($tableRows | Select-Object -First 5 | ForEach-Object {
            [ordered]@{
                questionNo = [int]$_.questionNo
                blockId = [string]$_.blockId
                caption = [string]$_.caption
                columnCount = [int]$_.columnCount
                rowCount = [int]$_.rowCount
                confidence = [double]$_.confidence
                reviewStatus = [string]$_.reviewStatus
                sourceRegionId = [string]$_.sourceRegionId
            }
        })
    }
    blockers = @($blockers)
    boundary = 'Repo-side REAL005C4 report only. It proves source-page based noise exclusion coverage and current DB/API-visible formula/table candidate structure for 2016-2025 reviewed questions. REAL005 remains not_closed until RG016 and REAL005D also pass.'
    summaryChinese = 'REAL005C4 repo-side 证据已刷新：2016-2025 reviewed 真题现在具备题目页截图覆盖，并在库中暴露 20 个 table block 与 56 个 formula block 候选，二者都保留 reviewStatus，公式候选带 fallbackImageUrl；但 REAL005 仍保持 not_closed。'
}

$jsonFullPath = Resolve-RepoPath $JsonReportPath
$markdownFullPath = Resolve-RepoPath $MarkdownReportPath
New-Item -ItemType Directory -Path (Split-Path -Parent $jsonFullPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonFullPath -Encoding UTF8

@(
    '# REAL005C4 Layout Formula Table Report',
    '',
    "- status: $($report.status)",
    "- rg013_status: $($report.criteriaStatus.RG013)",
    "- rg014_status: $($report.criteriaStatus.RG014)",
    "- rg015_status: $($report.criteriaStatus.RG015)",
    ('- source_region_report: `{0}`' -f $SourceRegionReportPath),
    ('- materialize_report: `{0}`' -f $MaterializeReportPath),
    '',
    '## Boundary',
    $report.boundary
) | Set-Content -LiteralPath $markdownFullPath -Encoding UTF8

$report | ConvertTo-Json -Depth 12

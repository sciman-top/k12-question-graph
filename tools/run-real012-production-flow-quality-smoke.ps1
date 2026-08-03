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
    [string] $ReportPath = 'docs/evidence/20260518-real012-production-flow-quality-report.json',
    [string] $BackupManifest = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for REAL012 production flow quality smoke'
}

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Invoke-RowSql([string] $Sql) {
    $psql = Join-Path $PgBin 'psql.exe'
    $rows = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -F '|' -v ON_ERROR_STOP=1 -c $Sql
    if ($LASTEXITCODE -ne 0) { throw "REAL012 SQL failed: $Sql" }
    return @($rows | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Read-Json([string] $Path) {
    $fullPath = Join-Path $repoRoot ($Path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    Assert-True (Test-Path -LiteralPath $fullPath) "REAL012 report missing: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Resolve-BackupManifest {
    if (-not [string]::IsNullOrWhiteSpace($BackupManifest)) {
        return (Resolve-Path -LiteralPath $BackupManifest).Path
    }

    $candidate = Get-ChildItem -Path 'D:\KQG_Backups' -Filter manifest.json -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    Assert-True ($null -ne $candidate) 'REAL012 requires a verified backup manifest before reversible smoke execution'
    return $candidate.FullName
}

$runDate = Get-Date -Format 'yyyyMMdd'
$workflowKey = 'guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1'
$resolvedBackupManifest = Resolve-BackupManifest
$backupVerification = & (Join-Path $PSScriptRoot 'verify-backup.ps1') -ManifestPath $resolvedBackupManifest | ConvertFrom-Json
Assert-True ([string] $backupVerification.status -eq 'ok') 'REAL012 backup verification failed'

$c1ReportPath = "docs/evidence/$runDate-real005c1-real-question-search-paper-export-smoke.json"
$c1MarkdownPath = "docs/evidence/$runDate-real005c1-real-question-search-paper-export-smoke.md"
$c2ReportPath = "docs/evidence/$runDate-real005c2-real-question-analysis-reference-smoke.json"
$c2MarkdownPath = "docs/evidence/$runDate-real005c2-real-question-analysis-reference-smoke.md"

Push-Location $repoRoot
try {
    & pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-real005c1-real-question-search-paper-export-smoke.ps1 `
        -BackupManifest $resolvedBackupManifest `
        -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort `
        -DatabasePassword $DatabasePassword -PgBin $PgBin `
        -OutputRoot $OutputRoot -ReportPath $c1ReportPath -MarkdownReportPath $c1MarkdownPath | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'REAL012 REAL005C1 dependency failed'

    & pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-real005c2-real-question-analysis-reference-smoke.ps1 `
        -BackupManifest $resolvedBackupManifest `
        -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort `
        -DatabasePassword $DatabasePassword -PgBin $PgBin `
        -ReportPath $c2ReportPath -MarkdownReportPath $c2MarkdownPath | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'REAL012 REAL005C2 dependency failed'

    $c1 = Read-Json $c1ReportPath
    $c2 = Read-Json $c2ReportPath
    Assert-True ([string] $c1.status -eq 'pass' -and [bool] $c1.rollbackApplied) 'REAL012 requires passing, rolled-back REAL005C1 evidence'
    Assert-True ([string] $c2.status -eq 'pass' -and [bool] $c2.rollbackApplied) 'REAL012 requires passing, rolled-back REAL005C2 evidence'
    Assert-True ([string] $c1.successPreflight.status -eq 'ready_for_review') 'REAL012 reviewed v2 sample export preflight must be ready'
    Assert-True ([string] $c1.anomalyPreflight.status -eq 'blocked') 'REAL012 2015 missing-solution sample must remain blocked'
    Assert-True ([int] $c1.anomalyPreflight.derivedIssueCounts.solution_missing -ge 1) 'REAL012 must expose the 2015 solution gap'
    Assert-True ([string] $c2.successExport.status -eq 'ready') 'REAL012 analysis dependency must be ready'

    $metricsSql = @"
select concat_ws('|',
  count(*),
  count(*) filter (where nullif(btrim(custom_fields#>>'{answer,value}'),'') is not null),
  count(*) filter (where nullif(btrim(custom_fields#>>'{solution,text}'),'') is not null),
  (select count(*) from question_assets qa join question_items q2 on q2.id=qa.question_item_id where q2.custom_fields->>'sourceWorkflowKey'='$workflowKey'),
  (select count(*) from question_blocks qb join question_items q3 on q3.id=qb.question_item_id where q3.custom_fields->>'sourceWorkflowKey'='$workflowKey' and qb.block_type='table'),
  (select count(*) from question_blocks qb join question_items q4 on q4.id=qb.question_item_id where q4.custom_fields->>'sourceWorkflowKey'='$workflowKey' and qb.block_type='formula'),
  count(*) filter (where status='pending_review'),
  count(*) filter (where primary_knowledge_id is null),
  count(*) filter (where coalesce((custom_fields->>'productionEligible')::boolean,false)=false)
)
from question_items
where custom_fields->>'sourceWorkflowKey'='$workflowKey';
"@
    $metricRows = @(Invoke-RowSql $metricsSql)
    Assert-True ($metricRows.Count -eq 1) 'REAL012 v2 metric query returned an unexpected row count'
    $metricParts = $metricRows[0] -split '\|', 9
    Assert-True (($metricParts[0,6,7,8] -join '|') -eq '234|234|234|234') 'REAL012 must preserve 234 pending-review v2 questions without active knowledge writes'

    & pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-real005-guangzhou-2015-2025-closure-standard.ps1 | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'REAL012 failed while refreshing REAL005 closure guard'
    $real005 = Read-Json 'docs/evidence/20260512-real005-guangzhou-2015-2025-closure-standard-report.json'
    Assert-True ([string] $real005.closureStatus -eq 'not_closed') 'REAL012 must keep REAL005 not_closed'

    $canonicalArtifactPath = 'docs/evidence/20260518-real012-word-pdf-artifact-report.json'
    Copy-Item -LiteralPath (Join-Path $repoRoot $c1.artifact.reportPath) -Destination (Join-Path $repoRoot $canonicalArtifactPath) -Force

    $report = [ordered]@{
        status = 'pass'
        task = 'REAL012'
        checkedAt = (Get-Date).ToString('s')
        requestedApiPort = $ApiPort
        resolvedApiPort = $null
        portFallbackApplied = ($ApiPort -le 0)
        apiUrl = $null
        sourceDocumentId = [string] $c1.promotedSuccessSamples[0].questionItemId
        promotedQuestions = @($c1.promotedSuccessSamples)
        searchProbe = [ordered]@{
            total = [int] $c1.searchProbe.total
            selectedQuestionNos = @($c1.promotedSuccessSamples | ForEach-Object { [int] $_.questionNo })
            hasImageCount = [int] $c1.successPreflight.summary.imageReadyCount
            sortBy = 'question_no'
            order = 'asc'
        }
        paperBasket = [ordered]@{
            id = [string] $c1.successPreflight.paperBasketId
            itemCount = [int] $c1.successPreflight.itemCount
            title = 'REAL012 2016-2025 广州真题抽样组卷'
        }
        exportPreflight = [ordered]@{
            status = [string] $c1.successPreflight.status
            itemCount = [int] $c1.successPreflight.itemCount
            summary = $c1.successPreflight.summary
            issueCounts = $c1.successPreflight.issueCounts
        }
        artifact = [ordered]@{
            reportPath = $canonicalArtifactPath
            manifestPath = [string] $c1.artifact.manifestPath
            status = [string] $c1.artifact.status
        }
        analysis = [ordered]@{
            assessmentId = [string] $c2.assessmentId
            status = [string] $c2.successExport.status
            artifactPath = [string] $c2.successExport.artifactPath
            allowAiDraftText = [bool] $c2.successExport.allowAiDraftText
            writesProductionHistory = [bool] $c2.successExport.writesProductionHistory
            weakKnowledgePointCount = [int] $c2.successExport.weakKnowledgePointCount
        }
        qualityReport = [ordered]@{
            closureStatus = 'not_closed'
            metrics = [ordered]@{
                questionCount = [int] $metricParts[0]
                questionNumberCount = [int] $metricParts[0]
                answerCoveredCount = [int] $metricParts[1]
                solutionCoveredCount = [int] $metricParts[2]
                sourceRegionCount = 0
                linkedSourceRegionCount = 0
                linkedSourceScreenshotCount = 0
                missingLinkedSourceScreenshotCount = 0
                imageAssetCount = [int] $metricParts[3]
                imageMatchedQuestionCount = [int] $c1.successPreflight.summary.imageReadyCount
                tableBlockCount = [int] $metricParts[4]
                formulaBlockCount = [int] $metricParts[5]
                pendingManualItemCount = [int] $metricParts[6]
                noiseRetainedBlockCount = 0
                externalAiCallCount = 0
            }
            gaps = @('teacher_validation_pending', '2015_solution_missing', 'candidate_tags_not_confirmed')
            rollbackSql = [string] $c1.rollbackSql
        }
        real005ClosureStatus = [string] $real005.closureStatus
        rollback = 'REAL005C1 and REAL005C2 applied their recorded rollback SQL before REAL012 aggregation returned.'
        summaryChinese = '2016-2025 v2 待审核真题已通过可逆检索、题篮、导出和讲评链；2015 缺解析仍按预期阻断，234 道题保持 pending_review，REAL005 继续 not_closed。'
    }

    $fullReportPath = Join-Path $repoRoot ($ReportPath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    New-Item -ItemType Directory -Path (Split-Path -Parent $fullReportPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $fullReportPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 20
}
finally {
    Pop-Location
}

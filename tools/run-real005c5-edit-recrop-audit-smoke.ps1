param(
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

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runDate = Get-Date -Format 'yyyyMMdd'
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for REAL005C5 edit/recrop audit smoke'
}

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = ('docs/evidence/{0}-real005c5-edit-recrop-audit-smoke.json' -f $runDate)
}

if ([string]::IsNullOrWhiteSpace($MarkdownReportPath)) {
    $MarkdownReportPath = ('docs/evidence/{0}-real005c5-edit-recrop-audit-smoke.md' -f $runDate)
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

function Invoke-QueryRows([string] $Sql) {
    $psql = Join-Path $PgBin 'psql.exe'
    if (-not (Test-Path -LiteralPath $psql)) {
        throw "psql not found: $psql"
    }

    $output = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -F '|' -v ON_ERROR_STOP=1 -c $Sql
    if ($LASTEXITCODE -ne 0) {
        throw "REAL005C5 SQL failed: $Sql"
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

function Get-QuestionBlock([object] $Detail, [string] $BlockType) {
    return @($Detail.blocks | Where-Object { [string] $_.blockType -eq $BlockType } | Sort-Object sortOrder | Select-Object -First 1)[0]
}

function Clone-JsonLike([object] $Value) {
    if ($null -eq $Value) { return $null }
    return ($Value | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
}

function New-QuestionBlockPatch([object] $Block, [object] $ContentOverride, [string] $SourceRegionIdOverride = '') {
    [ordered]@{
        id = [string] $Block.id
        blockType = [string] $Block.blockType
        sortOrder = [int] $Block.sortOrder
        content = $ContentOverride
        sourceRegionId = if ([string]::IsNullOrWhiteSpace($SourceRegionIdOverride)) { [string] $Block.sourceRegionId } else { $SourceRegionIdOverride }
    }
}

function Resolve-RepoPath([string] $RelativePath) {
    Join-Path $repoRoot $RelativePath
}

$requestedApiPort = $ApiPort
if ($ApiPort -le 0) {
    $ApiPort = Get-FreeTcpPort
}

$apiUrl = "http://127.0.0.1:$ApiPort"
$logOut = Join-Path $repoRoot 'docs/evidence/real005c5-edit-recrop-audit-api.out.log'
$logErr = Join-Path $repoRoot 'docs/evidence/real005c5-edit-recrop-audit-api.err.log'
$previousConnectionString = $env:KQG_CONNECTION_STRING
$runtimeRoot = Join-Path $repoRoot 'tmp\real005c5-runtime'
$runtimeDataRoot = Join-Path $runtimeRoot 'data'
$runtimeFileStoreRoot = Join-Path $runtimeDataRoot 'file_store'
$runtimeBackupRoot = Join-Path $runtimeRoot 'backups'
$runtimeLogsRoot = Join-Path $runtimeDataRoot 'logs'
$runtimeCacheRoot = Join-Path $runtimeDataRoot 'cache'
$sourceFileStoreRoot = if ([string]::IsNullOrWhiteSpace($env:KqgPaths__FileStoreRoot)) { 'D:\KQG_Data\file_store' } else { $env:KqgPaths__FileStoreRoot }
$previousDataRoot = $env:KqgPaths__DataRoot
$previousFileStoreRoot = $env:KqgPaths__FileStoreRoot
$previousBackupRoot = $env:KqgPaths__BackupRoot
$previousLogsRoot = $env:KqgPaths__LogsRoot
$previousCacheRoot = $env:KqgPaths__CacheRoot
$previousEnvironment = $env:ASPNETCORE_ENVIRONMENT
$previousDocumentWorkerScript = $env:PythonWorker__DocumentWorkerScript
$env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
$process = $null

try {
    Push-Location $repoRoot
    foreach ($path in @($runtimeDataRoot, $runtimeFileStoreRoot, $runtimeBackupRoot, $runtimeLogsRoot, $runtimeCacheRoot)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
    $sourceGeneratedRoot = Join-Path $sourceFileStoreRoot 'generated'
    $runtimeGeneratedRoot = Join-Path $runtimeFileStoreRoot 'generated'
    if ((Test-Path -LiteralPath $sourceGeneratedRoot) -and -not (Test-Path -LiteralPath $runtimeGeneratedRoot)) {
        New-Item -ItemType Junction -Path $runtimeGeneratedRoot -Target $sourceGeneratedRoot | Out-Null
    }
    $env:KqgPaths__DataRoot = $runtimeDataRoot
    $env:KqgPaths__FileStoreRoot = $runtimeFileStoreRoot
    $env:KqgPaths__BackupRoot = $runtimeBackupRoot
    $env:KqgPaths__LogsRoot = $runtimeLogsRoot
    $env:KqgPaths__CacheRoot = $runtimeCacheRoot
    $env:ASPNETCORE_ENVIRONMENT = 'Development'
    $env:PythonWorker__DocumentWorkerScript = '..\..\workers\document\worker.py'
    $process = Start-Process -FilePath dotnet -ArgumentList @(
        'run',
        '--project',
        'apps\api\K12QuestionGraph.Api.csproj',
        '-c',
        'Release',
        '--no-build',
        '--no-launch-profile',
        '--urls',
        $apiUrl
    ) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr

    $ready = $false
    $lastHealthStatus = $null
    $lastHealthBody = ''
    for ($i = 0; $i -lt 300; $i++) {
        if ($process.HasExited) {
            throw "API exited before ready on $apiUrl; see $logOut and $logErr"
        }
        try {
            $healthResponse = Invoke-WebRequest -Uri "$apiUrl/health/ready" -TimeoutSec 2 -SkipHttpErrorCheck
            $lastHealthStatus = [int] $healthResponse.StatusCode
            $lastHealthBody = [string] $healthResponse.Content
            if ($lastHealthStatus -eq 200) {
                $ready = $true
                break
            }
        }
        catch {
            if ($_.Exception.Response) {
                try {
                    $lastHealthStatus = [int] $_.Exception.Response.StatusCode
                    $reader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
                    try {
                        $lastHealthBody = $reader.ReadToEnd()
                    }
                    finally {
                        $reader.Dispose()
                    }
                }
                catch {}
            }
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) {
        throw "API did not become ready on $apiUrl; lastStatus=$lastHealthStatus; lastBody=$lastHealthBody; see $logOut and $logErr"
    }

    $workflowKey = 'guangzhou_2016_2025_reviewed_question_materialize_v1'
    $targetRows = ConvertTo-RowObjects `
        -Rows (Invoke-QueryRows @"
select
  qi.id::text as question_item_id,
  qi.custom_fields->>'questionNo' as question_no,
  qi.custom_fields->>'sourceFile' as source_file
from question_items qi
where coalesce(qi.custom_fields->>'sourceWorkflowKey','') = '$workflowKey'
  and exists (select 1 from question_blocks qb where qb.question_item_id = qi.id and qb.block_type = 'table')
  and exists (select 1 from question_blocks qb where qb.question_item_id = qi.id and qb.block_type = 'formula')
order by cast(qi.custom_fields->>'questionNo' as int), qi.custom_fields->>'sourceFile'
limit 1;
"@) `
        -Columns @('questionItemId','questionNo','sourceFile')
    Assert-True ($targetRows.Count -eq 1) 'REAL005C5 requires one reviewed real question with both table and formula blocks'

    $knowledgeRows = ConvertTo-RowObjects `
        -Rows (Invoke-QueryRows @"
select id::text, code, title
from knowledge_nodes
where status = 'active'
  and version = 1
order by code
limit 2;
"@) `
        -Columns @('id','code','title')
    Assert-True ($knowledgeRows.Count -eq 2) 'REAL005C5 requires two active knowledge nodes for audited remap'

    $targetQuestionId = [string] $targetRows[0].questionItemId
    $targetQuestionNo = [int] $targetRows[0].questionNo
    $targetSourceFile = [string] $targetRows[0].sourceFile
    $knowledgeA = [string] $knowledgeRows[0].id
    $knowledgeB = [string] $knowledgeRows[1].id

    $detailOriginal = Invoke-RestMethod -Uri "$apiUrl/questions/$targetQuestionId" -TimeoutSec 10
    $sourcesOriginal = Invoke-RestMethod -Uri "$apiUrl/questions/$targetQuestionId/sources" -TimeoutSec 10

    $textBlock = Get-QuestionBlock -Detail $detailOriginal -BlockType 'text'
    $formulaBlock = Get-QuestionBlock -Detail $detailOriginal -BlockType 'formula'
    $tableBlock = Get-QuestionBlock -Detail $detailOriginal -BlockType 'table'
    Assert-True ($null -ne $textBlock -and $null -ne $formulaBlock -and $null -ne $tableBlock) 'REAL005C5 target question must expose text/formula/table blocks'

    $questionRegion = @($sourcesOriginal.sourceRegions | Where-Object { [string] $_.id -eq [string] $textBlock.sourceRegionId })[0]
    Assert-True ($null -ne $questionRegion) 'REAL005C5 target question must expose question source region'

    $answerOriginal = Clone-JsonLike $detailOriginal.customFields.answer
    if ($null -eq $answerOriginal) {
        $answerOriginal = [pscustomobject]@{ value = ''; sourceFile = $targetSourceFile }
    }
    $solutionOriginal = Clone-JsonLike $detailOriginal.customFields.solution
    if ($null -eq $solutionOriginal) {
        $solutionOriginal = [pscustomobject]@{ text = 'REAL005C5 原始解析占位'; source = 'real005c5_seed'; reviewStatus = 'draft' }
    }

    $assetsBefore = @($detailOriginal.assets)
    $assetCountBefore = $assetsBefore.Count
    $assetIdsBefore = @($assetsBefore | ForEach-Object { [string] $_.id })

    $reviewedBy = 'real005c5-smoke'
    $restoreReviewedBy = 'real005c5-restore'
    $reason = 'repo-side RG016 edit recrop audit smoke'
    $restoreReason = 'restore REAL005C5 smoke state'

    $associateBody = [ordered]@{
        sourceRegionId = [string] $questionRegion.id
        assetType = 'image'
        purpose = 'question_figure'
        metadata = [ordered]@{
            sourceWorkflowKey = 'real005c5_edit_recrop_audit_smoke'
            reviewStatus = 'pending_review'
            note = 'temporary figure association for RG016 smoke'
        }
        reviewedBy = $reviewedBy
        reason = $reason
    } | ConvertTo-Json -Depth 10
    $associatedAsset = Invoke-RestMethod -Method Post -Uri "$apiUrl/questions/$targetQuestionId/assets" -ContentType 'application/json' -Body $associateBody -TimeoutSec 10
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$associatedAsset.auditId)) 'REAL005C5 asset association audit missing'

    $recropBody = [ordered]@{
        x = [decimal]$questionRegion.x + 1
        y = [decimal]$questionRegion.y + 1
        width = [decimal]$questionRegion.width - 1
        height = [decimal]$questionRegion.height
        coordinateUnit = [string]$questionRegion.coordinateUnit
        screenshotRelativePath = [string]$questionRegion.screenshotRelativePath
        regionType = 'question_stem_revised'
        reviewedBy = $reviewedBy
        reason = $reason
    } | ConvertTo-Json -Depth 10
    $regionRevision = Invoke-RestMethod -Method Patch -Uri "$apiUrl/source-regions/$($questionRegion.id)" -ContentType 'application/json' -Body $recropBody -TimeoutSec 10
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$regionRevision.auditId)) 'REAL005C5 source-region revision audit missing'

    $textContentEdited = Clone-JsonLike $textBlock.content
    $textContentEdited.text = ([string]$textContentEdited.text) + ' [REAL005C5]'

    $formulaContentEdited = Clone-JsonLike $formulaBlock.content
    $formulaContentEdited.textCandidate = 'RG016 公式候选已审计修改'
    $formulaContentEdited.confidence = 0.88
    $formulaContentEdited.fallbackImageSourceRegionId = [string]$questionRegion.id
    $formulaContentEdited.fallbackImageUrl = "/source-regions/$($questionRegion.id)/screenshot"

    $tableContentEdited = Clone-JsonLike $tableBlock.content
    $tableContentEdited.caption = ([string]$tableContentEdited.caption) + ' RG016'
    $tableContentEdited.sourceRegionId = [string]$questionRegion.id
    if ($tableContentEdited.rows.Count -gt 0 -and $tableContentEdited.rows[0].Count -gt 0) {
        $tableContentEdited.rows[0][0] = ([string]$tableContentEdited.rows[0][0]) + ' [RG016]'
    }

    $answerEdited = Clone-JsonLike $answerOriginal
    $answerEdited.value = if ([string]::IsNullOrWhiteSpace([string]$answerEdited.value)) { 'RG016 临时答案' } else { ([string]$answerEdited.value) + ' [RG016]' }
    $solutionEdited = Clone-JsonLike $solutionOriginal
    $solutionEdited.text = ([string]$solutionEdited.text) + ' [REAL005C5]'

    $expectedRestoredKnowledgeId = if ($null -eq $detailOriginal.primaryKnowledge) { '' } else { [string]$detailOriginal.primaryKnowledge.id }
    $forwardKnowledgeId = if ([string]::IsNullOrWhiteSpace([string]$detailOriginal.primaryKnowledge.id)) { $knowledgeA } else { if ([string]$detailOriginal.primaryKnowledge.id -eq $knowledgeA) { $knowledgeB } else { $knowledgeA } }

    $questionPatchBody = [ordered]@{
        primaryKnowledgeId = $forwardKnowledgeId
        blocks = @(
            (New-QuestionBlockPatch -Block $textBlock -ContentOverride $textContentEdited -SourceRegionIdOverride ([string]$questionRegion.id)),
            (New-QuestionBlockPatch -Block $formulaBlock -ContentOverride $formulaContentEdited -SourceRegionIdOverride ([string]$questionRegion.id)),
            (New-QuestionBlockPatch -Block $tableBlock -ContentOverride $tableContentEdited -SourceRegionIdOverride ([string]$questionRegion.id))
        )
        answer = $answerEdited
        solution = $solutionEdited
        reviewedBy = $reviewedBy
        reason = $reason
    } | ConvertTo-Json -Depth 25
    $questionRevision = Invoke-RestMethod -Method Patch -Uri "$apiUrl/questions/$targetQuestionId" -ContentType 'application/json' -Body $questionPatchBody -TimeoutSec 10
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$questionRevision.auditId)) 'REAL005C5 question revision audit missing'

    $detailEdited = Invoke-RestMethod -Uri "$apiUrl/questions/$targetQuestionId" -TimeoutSec 10
    $sourcesEdited = Invoke-RestMethod -Uri "$apiUrl/questions/$targetQuestionId/sources" -TimeoutSec 10
    $editedTextBlock = Get-QuestionBlock -Detail $detailEdited -BlockType 'text'
    $editedFormulaBlock = Get-QuestionBlock -Detail $detailEdited -BlockType 'formula'
    $editedTableBlock = Get-QuestionBlock -Detail $detailEdited -BlockType 'table'
    $editedRegion = @($sourcesEdited.sourceRegions | Where-Object { [string] $_.id -eq [string] $questionRegion.id })[0]

    Assert-True ([string]$editedTextBlock.content.text -like '*REAL005C5*') 'REAL005C5 edited stem missing'
    Assert-True ([string]$editedFormulaBlock.content.textCandidate -like '*RG016*') 'REAL005C5 edited formula missing'
    Assert-True ([string]$editedTableBlock.content.caption -like '*RG016') 'REAL005C5 edited table missing'
    Assert-True ([string]$detailEdited.customFields.answer.value -like '*RG016*') 'REAL005C5 edited answer missing'
    Assert-True ([string]$detailEdited.customFields.solution.text -like '*REAL005C5*') 'REAL005C5 edited solution missing'
    Assert-True ([string]$editedRegion.regionType -eq 'question_stem_revised') 'REAL005C5 recrop region type missing'
    Assert-True (@($detailEdited.assets).Count -eq ($assetCountBefore + 1)) 'REAL005C5 figure association missing'

    $knowledgeStateAfterEdit = ConvertTo-RowObjects `
        -Rows (Invoke-QueryRows @"
select
  qi.primary_knowledge_id::text as primary_knowledge_id,
  count(*) filter (where km.is_primary = true)::text as primary_mapping_count,
  coalesce(max(case when km.is_primary then km.knowledge_node_id::text end), '') as primary_mapping_knowledge_id
from question_items qi
left join knowledge_mappings km on km.question_item_id = qi.id
where qi.id = '$targetQuestionId'
group by qi.primary_knowledge_id;
"@) `
        -Columns @('primaryKnowledgeId','primaryMappingCount','primaryMappingKnowledgeId')
    Assert-True ($knowledgeStateAfterEdit.Count -eq 1) 'REAL005C5 knowledge state probe missing after edit'
    Assert-True ([string]$knowledgeStateAfterEdit[0].primaryKnowledgeId -eq $forwardKnowledgeId) 'REAL005C5 edited primary knowledge missing in question_items'
    Assert-True ([string]$knowledgeStateAfterEdit[0].primaryMappingKnowledgeId -eq $forwardKnowledgeId) 'REAL005C5 edited primary knowledge mapping missing'
    Assert-True ([int]$knowledgeStateAfterEdit[0].primaryMappingCount -ge 1) 'REAL005C5 primary mapping count missing after edit'

    $unlinkResponse = Invoke-RestMethod -Method Delete -Uri "$apiUrl/questions/$targetQuestionId/assets/$($associatedAsset.asset.id)?reviewedBy=$restoreReviewedBy&reason=$([uri]::EscapeDataString($restoreReason))" -TimeoutSec 10
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$unlinkResponse.auditId)) 'REAL005C5 asset unlink audit missing'

    $restoreRecropBody = [ordered]@{
        x = [decimal]$questionRegion.x
        y = [decimal]$questionRegion.y
        width = [decimal]$questionRegion.width
        height = [decimal]$questionRegion.height
        coordinateUnit = [string]$questionRegion.coordinateUnit
        screenshotRelativePath = [string]$questionRegion.screenshotRelativePath
        regionType = [string]$questionRegion.regionType
        reviewedBy = $restoreReviewedBy
        reason = $restoreReason
    } | ConvertTo-Json -Depth 10
    $regionRestore = Invoke-RestMethod -Method Patch -Uri "$apiUrl/source-regions/$($questionRegion.id)" -ContentType 'application/json' -Body $restoreRecropBody -TimeoutSec 10
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$regionRestore.auditId)) 'REAL005C5 region restore audit missing'

    & pwsh -NoProfile -ExecutionPolicy Bypass -File 'tools/run-real005b-reviewed-question-materialize.ps1' -Apply | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'REAL005C5 failed to rerun reviewed-question materialize for state restore'
    }

    $restoreQuestionPatchBody = [ordered]@{
        blocks = @(
            (New-QuestionBlockPatch -Block $textBlock -ContentOverride (Clone-JsonLike $textBlock.content) -SourceRegionIdOverride ([string]$questionRegion.id)),
            (New-QuestionBlockPatch -Block $formulaBlock -ContentOverride (Clone-JsonLike $formulaBlock.content) -SourceRegionIdOverride ([string]$questionRegion.id)),
            (New-QuestionBlockPatch -Block $tableBlock -ContentOverride (Clone-JsonLike $tableBlock.content) -SourceRegionIdOverride ([string]$questionRegion.id))
        )
        answer = (Clone-JsonLike $answerOriginal)
        solution = (Clone-JsonLike $solutionOriginal)
        reviewedBy = $restoreReviewedBy
        reason = $restoreReason
    }
    if ([string]::IsNullOrWhiteSpace($expectedRestoredKnowledgeId)) {
        $restoreQuestionPatchBody['clearPrimaryKnowledge'] = $true
    }
    else {
        $restoreQuestionPatchBody['primaryKnowledgeId'] = $expectedRestoredKnowledgeId
    }
    $restoreQuestionPatchBodyJson = $restoreQuestionPatchBody | ConvertTo-Json -Depth 25
    $restoreQuestionRevision = Invoke-RestMethod -Method Patch -Uri "$apiUrl/questions/$targetQuestionId" -ContentType 'application/json' -Body $restoreQuestionPatchBodyJson -TimeoutSec 10
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$restoreQuestionRevision.auditId)) 'REAL005C5 restore question revision audit missing'

    $detailRestored = Invoke-RestMethod -Uri "$apiUrl/questions/$targetQuestionId" -TimeoutSec 10
    $sourcesRestored = Invoke-RestMethod -Uri "$apiUrl/questions/$targetQuestionId/sources" -TimeoutSec 10
    $restoredTextBlock = Get-QuestionBlock -Detail $detailRestored -BlockType 'text'
    $restoredFormulaBlock = Get-QuestionBlock -Detail $detailRestored -BlockType 'formula'
    $restoredTableBlock = Get-QuestionBlock -Detail $detailRestored -BlockType 'table'
    $restoredRegion = @($sourcesRestored.sourceRegions | Where-Object { [string] $_.id -eq [string] $questionRegion.id })[0]

    Assert-True ([string]$restoredTextBlock.content.text -eq [string]$textBlock.content.text) 'REAL005C5 text restore drift'
    Assert-True ([string]$restoredFormulaBlock.content.textCandidate -eq [string]$formulaBlock.content.textCandidate) 'REAL005C5 formula restore drift'
    Assert-True ([string]$restoredTableBlock.content.caption -eq [string]$tableBlock.content.caption) 'REAL005C5 table restore drift'
    Assert-True ([string]$detailRestored.customFields.answer.value -eq [string]$answerOriginal.value) 'REAL005C5 answer restore drift'
    Assert-True ([string]$detailRestored.customFields.solution.text -eq [string]$solutionOriginal.text) 'REAL005C5 solution restore drift'
    Assert-True (@($detailRestored.assets).Count -eq $assetCountBefore) 'REAL005C5 asset restore drift'
    Assert-True ([string]$restoredRegion.regionType -eq [string]$questionRegion.regionType) 'REAL005C5 region type restore drift'
    Assert-True ([decimal]$restoredRegion.x -eq [decimal]$questionRegion.x -and [decimal]$restoredRegion.y -eq [decimal]$questionRegion.y) 'REAL005C5 bbox restore drift'

    $knowledgeStateAfterRestore = ConvertTo-RowObjects `
        -Rows (Invoke-QueryRows @"
select
  coalesce(qi.primary_knowledge_id::text, '') as primary_knowledge_id,
  count(*) filter (where km.is_primary = true)::text as primary_mapping_count,
  coalesce(max(case when km.is_primary then km.knowledge_node_id::text end), '') as primary_mapping_knowledge_id
from question_items qi
left join knowledge_mappings km on km.question_item_id = qi.id
where qi.id = '$targetQuestionId'
group by qi.primary_knowledge_id;
"@) `
        -Columns @('primaryKnowledgeId','primaryMappingCount','primaryMappingKnowledgeId')
    Assert-True ($knowledgeStateAfterRestore.Count -eq 1) 'REAL005C5 knowledge state probe missing after restore'
    Assert-True ([string]$knowledgeStateAfterRestore[0].primaryKnowledgeId -eq $expectedRestoredKnowledgeId) 'REAL005C5 primary knowledge restore drift in question_items'

    $questionRevisionAudits = Invoke-RestMethod -Uri "$apiUrl/review-queue?status=resolved&reviewType=question_revision&limit=200" -TimeoutSec 10
    $sourceRegionAudits = Invoke-RestMethod -Uri "$apiUrl/review-queue?status=resolved&reviewType=source_region_revision&limit=200" -TimeoutSec 10
    $assetAudits = Invoke-RestMethod -Uri "$apiUrl/review-queue?status=resolved&reviewType=question_asset_revision&limit=200" -TimeoutSec 10

    $questionAuditItems = @($questionRevisionAudits.items | Where-Object { [string]$_.payload.questionItemId -eq $targetQuestionId -and @($reviewedBy, $restoreReviewedBy) -contains [string]$_.payload.reviewAudit.reviewedBy })
    $sourceAuditItems = @($sourceRegionAudits.items | Where-Object { [string]$_.payload.sourceRegionId -eq [string]$questionRegion.id -and @($reviewedBy, $restoreReviewedBy) -contains [string]$_.payload.reviewAudit.reviewedBy })
    $assetAuditItems = @($assetAudits.items | Where-Object { [string]$_.payload.questionItemId -eq $targetQuestionId -and @($reviewedBy, $restoreReviewedBy) -contains [string]$_.payload.reviewAudit.reviewedBy })
    Assert-True ($questionAuditItems.Count -ge 2) 'REAL005C5 question revision audits not queryable'
    Assert-True ($sourceAuditItems.Count -ge 2) 'REAL005C5 source-region audits not queryable'
    Assert-True ($assetAuditItems.Count -ge 2) 'REAL005C5 asset audits not queryable'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'REAL005C5_EDIT_RECROP_AUDIT_SMOKE'
        criterionId = 'RG016'
        rg016Status = 'pass'
        checkedAt = (Get-Date).ToString('s')
        requestedApiPort = $requestedApiPort
        resolvedApiPort = $ApiPort
        portFallbackApplied = ($requestedApiPort -ne $ApiPort)
        apiUrl = $apiUrl
        workflowKey = $workflowKey
        activeWrite = $true
        externalAiCalls = 0
        realStudentDataUsed = $false
        stateRestored = $true
        targetQuestion = [ordered]@{
            questionItemId = $targetQuestionId
            questionNo = $targetQuestionNo
            sourceFile = $targetSourceFile
        }
        auditedEdits = [ordered]@{
            questionRevisionAuditId = [string]$questionRevision.auditId
            sourceRegionRevisionAuditId = [string]$regionRevision.auditId
            assetAssociateAuditId = [string]$associatedAsset.auditId
            assetUnlinkAuditId = [string]$unlinkResponse.auditId
            editedPrimaryKnowledgeId = $forwardKnowledgeId
            editedText = [string]$editedTextBlock.content.text
            editedAnswer = [string]$detailEdited.customFields.answer.value
            editedSolution = [string]$detailEdited.customFields.solution.text
            editedFormulaTextCandidate = [string]$editedFormulaBlock.content.textCandidate
            editedTableCaption = [string]$editedTableBlock.content.caption
            recropRegionType = [string]$editedRegion.regionType
        }
        restoreAudits = [ordered]@{
            sourceRegionRestoreAuditId = [string]$regionRestore.auditId
            materializeRestoreReport = 'docs/evidence/20260617-real005b-reviewed-question-materialize.json'
            questionRestoreAuditId = [string]$restoreQuestionRevision.auditId
            knowledgeCleanup = if ([string]::IsNullOrWhiteSpace($expectedRestoredKnowledgeId)) { 'clearPrimaryKnowledge=true via PATCH /questions/{id}' } else { "primaryKnowledgeId reset to $expectedRestoredKnowledgeId via PATCH /questions/{id}" }
        }
        auditQueryCoverage = [ordered]@{
            questionRevisionCount = $questionAuditItems.Count
            sourceRegionRevisionCount = $sourceAuditItems.Count
            assetRevisionCount = $assetAuditItems.Count
        }
        boundary = 'Repo-side RG016 smoke only. It proves one reviewed 2016-2025 real question can pass through audited text/answer/solution/primary-knowledge/formula/table edits, source-region recrop, and figure asset associate-unlink paths. Business state is restored by audited recrop restore plus repo-side reviewed-question rematerialization and targeted mapping cleanup. REAL005 remains not_closed until REAL005D outward closeout wording is also refreshed truthfully.'
        summaryChinese = 'REAL005C5 repo-side 证据已生成：一条真实 reviewed 真题已经验证题干、答案、解析、主知识点标签、公式、表格、来源框重裁、题图关联/解除都能产生 audit；脚本结束前已通过来源框恢复、reviewed question 重物化和定向 mapping 清理把业务状态恢复原样。'
    }

    $fullReportPath = Resolve-RepoPath $ReportPath
    $fullMarkdownPath = Resolve-RepoPath $MarkdownReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $fullReportPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $fullReportPath -Encoding UTF8
    @(
        '# REAL005C5 Edit Recrop Audit Smoke',
        '',
        "- status: $($report.status)",
        "- rg016_status: $($report.rg016Status)",
        "- state_restored: $($report.stateRestored)",
        "- target_question: $targetQuestionId",
        '',
        '## Boundary',
        $report.boundary
    ) | Set-Content -LiteralPath $fullMarkdownPath -Encoding UTF8

    $report | ConvertTo-Json -Depth 12
}
finally {
    if ($null -ne $process) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    $env:KQG_CONNECTION_STRING = $previousConnectionString
    $env:KqgPaths__DataRoot = $previousDataRoot
    $env:KqgPaths__FileStoreRoot = $previousFileStoreRoot
    $env:KqgPaths__BackupRoot = $previousBackupRoot
    $env:KqgPaths__LogsRoot = $previousLogsRoot
    $env:KqgPaths__CacheRoot = $previousCacheRoot
    $env:ASPNETCORE_ENVIRONMENT = $previousEnvironment
    $env:PythonWorker__DocumentWorkerScript = $previousDocumentWorkerScript
    Pop-Location
}

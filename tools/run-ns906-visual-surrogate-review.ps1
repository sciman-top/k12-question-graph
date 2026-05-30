param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [int] $SourceSampleLimit = 8,
    [string] $ReportPath = 'docs/evidence/20260528-ns906-visual-surrogate-review-report.json',
    [string] $NonSiteE2EReportPath = 'docs/evidence/20260528-non-site-e2e-rehearsal-report.json',
    [string] $LayoutReportPath = 'docs/evidence/20260516-real007-guangzhou-2015-layout-quality-report.json',
    [string] $ProductionFlowReportPath = 'docs/evidence/20260518-real012-production-flow-quality-report.json',
    [string] $ArtifactReportPath = 'docs/evidence/20260518-real012-word-pdf-artifact-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for NS906 visual surrogate review'
}

function Read-JsonEvidence([string] $RelativePath) {
    $fullPath = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw "NS906 evidence missing: $RelativePath"
    }
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Resolve-RepoPath([string] $Path) {
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    return Join-Path $repoRoot $Path
}

function Invoke-ScalarSql([string] $Sql) {
    $psql = Join-Path $PgBin 'psql.exe'
    $previousPgPassword = $env:PGPASSWORD
    $env:PGPASSWORD = $DatabasePassword
    try {
        $value = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c $Sql
        if ($LASTEXITCODE -ne 0) {
            throw "NS906 SQL failed: $Sql"
        }
        return (($value | Select-Object -First 1) ?? '').Trim()
    }
    finally {
        $env:PGPASSWORD = $previousPgPassword
    }
}

function Test-DocxArtifact([string] $Path) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $fullPath = Resolve-RepoPath $Path
    $exists = Test-Path -LiteralPath $fullPath
    if (-not $exists) {
        return [ordered]@{ exists = $false; hasDocumentXml = $false; mediaCount = 0; sizeBytes = 0 }
    }

    $archive = [System.IO.Compression.ZipFile]::OpenRead($fullPath)
    try {
        $entryNames = @($archive.Entries | ForEach-Object { $_.FullName })
        return [ordered]@{
            exists = $true
            hasDocumentXml = $entryNames -contains 'word/document.xml'
            mediaCount = @($entryNames | Where-Object { $_ -like 'word/media/*' }).Count
            sizeBytes = (Get-Item -LiteralPath $fullPath).Length
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Test-PdfArtifact([string] $Path) {
    $fullPath = Resolve-RepoPath $Path
    $exists = Test-Path -LiteralPath $fullPath
    if (-not $exists) {
        return [ordered]@{ exists = $false; hasPdfHeader = $false; hasEof = $false; sizeBytes = 0 }
    }

    $bytes = [System.IO.File]::ReadAllBytes($fullPath)
    $header = [System.Text.Encoding]::ASCII.GetString($bytes, 0, [Math]::Min(5, $bytes.Length))
    $tailLength = [Math]::Min(32, $bytes.Length)
    $tail = [System.Text.Encoding]::ASCII.GetString($bytes, $bytes.Length - $tailLength, $tailLength)
    return [ordered]@{
        exists = $true
        hasPdfHeader = $header.StartsWith('%PDF-')
        hasEof = $tail.TrimEnd().EndsWith('%%EOF')
        sizeBytes = $bytes.Length
    }
}

function Test-ImageSample([string] $RelativePath, [int] $Grid = 32) {
    Add-Type -AssemblyName System.Drawing
    $normalized = $RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar
    $fullPath = Join-Path $FileStoreRoot $normalized
    if (-not (Test-Path -LiteralPath $fullPath)) {
        return [ordered]@{
            path = $RelativePath
            exists = $false
            width = 0
            height = 0
            nonBlankRatio = 0
            pass = $false
        }
    }

    $bitmap = [System.Drawing.Bitmap]::new($fullPath)
    try {
        $nonBlank = 0
        $total = 0
        for ($ix = 0; $ix -lt $Grid; $ix++) {
            for ($iy = 0; $iy -lt $Grid; $iy++) {
                $x = [int][Math]::Round($ix * ($bitmap.Width - 1) / ($Grid - 1))
                $y = [int][Math]::Round($iy * ($bitmap.Height - 1) / ($Grid - 1))
                $pixel = $bitmap.GetPixel($x, $y)
                $total += 1
                if ($pixel.A -gt 0 -and -not ($pixel.R -gt 245 -and $pixel.G -gt 245 -and $pixel.B -gt 245)) {
                    $nonBlank += 1
                }
            }
        }
        $ratio = if ($total -eq 0) { 0 } else { [Math]::Round($nonBlank / $total, 4) }
        return [ordered]@{
            path = $RelativePath
            exists = $true
            width = $bitmap.Width
            height = $bitmap.Height
            nonBlankRatio = $ratio
            pass = ($bitmap.Width -ge 40 -and $bitmap.Height -ge 20 -and $ratio -ge 0.005)
        }
    }
    finally {
        $bitmap.Dispose()
    }
}

function Add-Blocker([System.Collections.Generic.List[string]] $Blockers, [string] $Message) {
    if (-not $Blockers.Contains($Message)) {
        $Blockers.Add($Message)
    }
}

$blockers = [System.Collections.Generic.List[string]]::new()
$nonSite = Read-JsonEvidence $NonSiteE2EReportPath
$layout = Read-JsonEvidence $LayoutReportPath
$production = Read-JsonEvidence $ProductionFlowReportPath
$artifact = Read-JsonEvidence $ArtifactReportPath

if ($nonSite.status -ne 'pass') { Add-Blocker $blockers 'non_site_e2e_report_not_pass' }
if ($layout.status -ne 'pass') { Add-Blocker $blockers 'layout_quality_report_not_pass' }
if ($production.status -ne 'pass') { Add-Blocker $blockers 'production_flow_report_not_pass' }
if ($artifact.status -ne 'pass') { Add-Blocker $blockers 'artifact_report_not_pass' }

$requiredWorkflowSteps = @(
    'admission',
    'import_cut_review_save',
    'tagging',
    'review_save',
    'paper',
    'export',
    'score',
    'score_mapping',
    'analysis',
    'backup_restore'
)
$actualWorkflowSteps = @($nonSite.workflowSteps | ForEach-Object { [string]$_.workflowStep })
$missingWorkflowSteps = @($requiredWorkflowSteps | Where-Object { $actualWorkflowSteps -notcontains $_ })
if ($missingWorkflowSteps.Count -gt 0) {
    Add-Blocker $blockers "workflow_steps_missing:$($missingWorkflowSteps -join ',')"
}

if ([int]$layout.missingScreenshotCount -ne 0) { Add-Blocker $blockers 'source_region_screenshot_missing' }
if ([int]$layout.placeholderLikeScreenshotCount -ne 0) { Add-Blocker $blockers 'source_region_placeholder_screenshot' }
if ([int]$layout.noiseOverlapCount -ne 0) { Add-Blocker $blockers 'source_region_noise_overlap' }
if (@($layout.questionNosCovered).Count -lt 24) { Add-Blocker $blockers 'visual_question_coverage_below_24' }

$sampleSql = @"
with linked as (
  select
    sr.id::text as id,
    sr.screenshot_relative_path,
    sr.page_number,
    sr.x,
    sr.y,
    sr.width,
    sr.height,
    (qi.custom_fields->>'questionNo')::int as question_no
  from source_regions sr
  join question_blocks qb on qb.source_region_id = sr.id
  join question_items qi on qi.id = qb.question_item_id
  where qi.custom_fields->>'sourceWorkflowKey' in ('guangzhou_2015_real_ingest_v1','guangzhou_2015_visual_region_v1')
  union
  select
    sr.id::text,
    sr.screenshot_relative_path,
    sr.page_number,
    sr.x,
    sr.y,
    sr.width,
    sr.height,
    (qi.custom_fields->>'questionNo')::int
  from source_regions sr
  join question_assets qa on qa.source_region_id = sr.id
  join question_items qi on qi.id = qa.question_item_id
  where qi.custom_fields->>'sourceWorkflowKey' in ('guangzhou_2015_real_ingest_v1','guangzhou_2015_visual_region_v1')
)
select coalesce(json_agg(row_to_json(t))::text, '[]')
from (
  select distinct *
  from linked
  where screenshot_relative_path is not null
  order by question_no, page_number
  limit $SourceSampleLimit
) t;
"@

$sourceSamples = @(Invoke-ScalarSql $sampleSql | ConvertFrom-Json)
if ($sourceSamples.Count -lt [Math]::Min(3, $SourceSampleLimit)) {
    Add-Blocker $blockers 'source_visual_sample_too_small'
}

$imageProbes = @($sourceSamples | ForEach-Object {
    $probe = Test-ImageSample -RelativePath ([string]$_.screenshot_relative_path)
    [ordered]@{
        regionId = [string]$_.id
        questionNo = [int]$_.question_no
        pageNumber = [int]$_.page_number
        bbox = [ordered]@{
            x = [decimal]$_.x
            y = [decimal]$_.y
            width = [decimal]$_.width
            height = [decimal]$_.height
        }
        screenshot = $probe
    }
})
foreach ($probe in $imageProbes) {
    if (-not [bool]$probe.screenshot.pass) {
        Add-Blocker $blockers "source_visual_sample_failed:$($probe.regionId)"
    }
}

$artifactProbes = [ordered]@{}
foreach ($variantName in @('student','teacher','answer')) {
    $variant = $artifact.variants.$variantName
    if ($null -eq $variant) {
        Add-Blocker $blockers "artifact_variant_missing:$variantName"
        continue
    }
    $docxProbe = Test-DocxArtifact -Path ([string]$variant.docxPath)
    $pdfProbe = Test-PdfArtifact -Path ([string]$variant.pdfPath)
    $artifactProbes[$variantName] = [ordered]@{
        docx = $docxProbe
        pdf = $pdfProbe
        existingReportChecks = $artifact.checks.$variantName
    }
    if (-not [bool]$docxProbe.exists -or -not [bool]$docxProbe.hasDocumentXml) {
        Add-Blocker $blockers "docx_unreadable:$variantName"
    }
    if (-not [bool]$pdfProbe.exists -or -not [bool]$pdfProbe.hasPdfHeader -or -not [bool]$pdfProbe.hasEof) {
        Add-Blocker $blockers "pdf_unreadable:$variantName"
    }
}

if ($production.exportPreflight.status -ne 'ready_for_review') {
    Add-Blocker $blockers 'export_preflight_not_ready_for_review'
}
if ($production.analysis.status -ne 'ready') {
    Add-Blocker $blockers 'analysis_report_not_ready'
}
if ([bool]$production.analysis.allowAiDraftText -ne $false -or [bool]$production.analysis.writesProductionHistory -ne $false) {
    Add-Blocker $blockers 'analysis_ai_or_history_boundary_broken'
}
if ($production.qualityReport.closureStatus -ne 'not_closed' -or $production.real005ClosureStatus -ne 'not_closed') {
    Add-Blocker $blockers 'visual_surrogate_overclosed_live_boundary'
}

$report = [ordered]@{
    status = if ($blockers.Count -eq 0) { 'pass' } else { 'fail' }
    taskId = 'NS906'
    checkedAt = (Get-Date).ToString('s')
    mode = 'deterministic_visual_surrogate_review'
    productionEligible = $false
    realStudentDataUsed = $false
    externalAiCalls = 0
    aiVisionBoundary = [ordered]@{
        currentMode = 'machine vision and artifact checks without external model calls'
        canReplaceEarlyManualLook = $true
        cannotReplace = @('真实教师偏好', '学校隔离机', '打印机', '权限域', '真实网络', '最终发布裁决')
        futureOptionalMode = 'multimodal AI sample review may be added after provider budget/privacy admission'
    }
    inputs = [ordered]@{
        nonSiteE2EReport = $NonSiteE2EReportPath
        layoutReport = $LayoutReportPath
        productionFlowReport = $ProductionFlowReportPath
        artifactReport = $ArtifactReportPath
        fileStoreRoot = $FileStoreRoot
    }
    workflowCoverage = [ordered]@{
        required = $requiredWorkflowSteps
        actual = $actualWorkflowSteps
        missing = $missingWorkflowSteps
    }
    sourceVisualReview = [ordered]@{
        layoutStatus = [string]$layout.status
        linkedSourceRegionCount = [int]$layout.linkedSourceRegionCount
        questionNosCovered = $layout.questionNosCovered
        missingScreenshotCount = [int]$layout.missingScreenshotCount
        placeholderLikeScreenshotCount = [int]$layout.placeholderLikeScreenshotCount
        noiseOverlapCount = [int]$layout.noiseOverlapCount
        sampledImageCount = $imageProbes.Count
        sampledImages = $imageProbes
    }
    exportArtifactReview = [ordered]@{
        artifactStatus = [string]$artifact.status
        preflightStatus = [string]$artifact.preflightStatus
        variants = $artifactProbes
    }
    analysisReview = [ordered]@{
        productionFlowStatus = [string]$production.status
        exportPreflightStatus = [string]$production.exportPreflight.status
        analysisStatus = [string]$production.analysis.status
        weakKnowledgePointCount = [int]$production.analysis.weakKnowledgePointCount
        allowAiDraftText = [bool]$production.analysis.allowAiDraftText
        writesProductionHistory = [bool]$production.analysis.writesProductionHistory
        qualityClosureStatus = [string]$production.qualityReport.closureStatus
        real005ClosureStatus = [string]$production.real005ClosureStatus
    }
    blockers = $blockers
    rollback = 'git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns906-visual-surrogate-review.ps1 docs/evidence/20260528-ns906-visual-surrogate-review-report.json'
    conclusion = if ($blockers.Count -eq 0) {
        'NS906 proves a deterministic visual surrogate can replace early manual spot checks for source screenshots, export artifacts, and analysis boundaries while keeping live/site closure not_closed.'
    } else {
        'NS906 found visual surrogate blockers; keep the workflow below runtime_verified until blockers are resolved.'
    }
}

$reportFullPath = Join-Path $repoRoot $ReportPath
New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
$report | ConvertTo-Json -Depth 16
if ($blockers.Count -gt 0) {
    throw "NS906 visual surrogate review failed: $($blockers -join ', ')"
}

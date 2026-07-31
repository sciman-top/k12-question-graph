param(
    [string] $ReportPath = 'docs\evidence\cek026-curriculum-evidence-review-ui.json',
    [int] $ApiPort = 0,
    [string] $BrowserEvidencePath = '',
    [int] $BrowserEvidenceMaxAgeMinutes = 120,
    [switch] $RequireBrowserEvidence
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$panelPath = Join-Path $repoRoot 'apps\web\src\ui\CurriculumEvidenceReviewPanel.tsx'
$testPath = Join-Path $repoRoot 'apps\web\src\ui\CurriculumEvidenceReviewPanel.test.tsx'
$adminPath = Join-Path $repoRoot 'apps\web\src\ui\AdminGovernancePanels.tsx'
$clientPath = Join-Path $repoRoot 'apps\web\src\api\client.ts'
$contractsPath = Join-Path $repoRoot 'apps\web\src\api\contracts.ts'
$cssPath = Join-Path $repoRoot 'apps\web\src\App.css'
$vitePath = Join-Path $repoRoot 'apps\web\vite.config.ts'
$resolvedReportPath = Join-Path $repoRoot $ReportPath

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

$panel = Get-Content -LiteralPath $panelPath -Raw
$tests = Get-Content -LiteralPath $testPath -Raw
$admin = Get-Content -LiteralPath $adminPath -Raw
$client = Get-Content -LiteralPath $clientPath -Raw
$contracts = Get-Content -LiteralPath $contractsPath -Raw
$css = Get-Content -LiteralPath $cssPath -Raw
$vite = Get-Content -LiteralPath $vitePath -Raw

foreach ($marker in @(
    'data-contract="cek026-curriculum-evidence-review"',
    '高影响映射',
    '低置信度',
    '课标要求',
    '考查目标',
    '地区画像',
    '审核理由',
    "'approve'",
    "'return'",
    "'keep_pending'",
    'undoCurriculumEvidenceDecision',
    'retrospective_crosswalk',
    '后设对齐',
    'source_cited',
    '同期推断',
    'collectSourceAnchors([item.summary, item.evidence])',
    '/page-screenshot',
    'primaryKnowledge',
    '题目估计难度',
    '年报实测难度',
    "'change_mapping'",
    'getCurriculumEvidenceReplacementOptions',
    '审核列表暂时无法加载，请重试。'
)) {
    Assert-Condition ($panel.Contains($marker)) "missing CEK-26 panel marker: $marker"
}

foreach ($marker in @(
    'does not submit a decision without a review reason',
    'submits a reasoned decision and can undo it',
    'keeps an unsaved reason when refreshing the query fails',
    'distinct estimated and observed difficulty',
    'uses the replacement allowlist for a mapping change'
)) {
    Assert-Condition ($tests.Contains($marker)) "missing CEK-26 interaction test: $marker"
}

Assert-Condition ($admin.Contains('<CurriculumEvidenceReviewPanel />')) 'CEK-26 panel is not mounted in admin governance'

foreach ($marker in @(
    '/knowledge-evidence/reviews?',
    '/knowledge-evidence/reviews/decisions',
    '/replacement-options',
    'normalizeCurriculumEvidenceReplacementOptionsResponse',
    '/undo',
    'encodeURIComponent(decisionId)'
)) {
    Assert-Condition ($client.Contains($marker)) "missing CEK-26 client marker: $marker"
}

foreach ($marker in @(
    'CurriculumEvidenceReviewItemContract',
    'CurriculumEvidenceReplacementOptionsContract',
    'normalizeCurriculumEvidenceReviewListResponse',
    "reviewStatus: readStringField(item, 'reviewStatus') ?? 'pending_review'",
    'productionEligible: readBooleanField(item, ''productionEligible'')'
)) {
    Assert-Condition ($contracts.Contains($marker)) "missing CEK-26 fail-closed contract marker: $marker"
}

foreach ($marker in @(
    '.curriculum-evidence-review',
    '.curriculum-review-row',
    '.curriculum-review-pagination',
    '.curriculum-review-sources',
    '.curriculum-mapping-editor',
    'grid-template-columns: minmax(0, 1fr)',
    'grid-template-columns: minmax(0, 1fr) minmax(280px, 0.7fr)',
    '@media (max-width: 860px)',
    'grid-template-columns: minmax(0, 1fr)',
    'flex: 0 0 auto',
    'min-width: 104px'
)) {
    Assert-Condition ($css.Contains($marker)) "missing CEK-26 responsive style marker: $marker"
}

$browserVerification = [ordered]@{
    status = 'not_requested'
    evidencePath = $null
    checkedAt = $null
    desktop = $null
    mobile = $null
    interactions = $null
    consoleErrorCount = $null
    failedRequestCount = $null
}
if ($BrowserEvidencePath) {
    $candidateBrowserEvidencePath = if ([System.IO.Path]::IsPathRooted($BrowserEvidencePath)) {
        $BrowserEvidencePath
    } else {
        Join-Path $repoRoot $BrowserEvidencePath
    }
    $resolvedBrowserEvidencePath = (Resolve-Path -LiteralPath $candidateBrowserEvidencePath).Path
    $browserEvidence = Get-Content -LiteralPath $resolvedBrowserEvidencePath -Raw | ConvertFrom-Json
    Assert-Condition ($browserEvidence.status -eq 'pass') 'CEK-26 browser evidence status must be pass'

    $browserCheckedAt = [DateTimeOffset] $browserEvidence.checkedAt
    $browserEvidenceAge = [DateTimeOffset]::UtcNow - $browserCheckedAt.ToUniversalTime()
    Assert-Condition ($browserEvidenceAge.TotalMinutes -ge -5) 'CEK-26 browser evidence timestamp is too far in the future'
    Assert-Condition ($browserEvidenceAge.TotalMinutes -le $BrowserEvidenceMaxAgeMinutes) 'CEK-26 browser evidence is stale'

    Assert-Condition ($browserEvidence.desktop.pageOverflow -eq $false) 'CEK-26 desktop browser evidence has page overflow'
    Assert-Condition ($browserEvidence.desktop.panelOverflow -eq $false) 'CEK-26 desktop browser evidence has panel overflow'
    Assert-Condition ([int] $browserEvidence.desktop.clippedSegmentLabelCount -eq 0) 'CEK-26 desktop browser evidence has clipped segmented labels'
    Assert-Condition ($browserEvidence.mobile.pageOverflow -eq $false) 'CEK-26 mobile browser evidence has page overflow'
    Assert-Condition ($browserEvidence.mobile.panelOverflow -eq $false) 'CEK-26 mobile browser evidence has panel overflow'
    Assert-Condition ([int] $browserEvidence.mobile.clippedSegmentLabelCount -eq 0) 'CEK-26 mobile browser evidence has clipped segmented labels'
    Assert-Condition ($browserEvidence.interactions.emptyReasonBlocked -eq $true) 'CEK-26 browser evidence did not prove empty-reason blocking'
    Assert-Condition ($browserEvidence.interactions.unsavedReasonPreserved -eq $true) 'CEK-26 browser evidence did not prove unsaved-reason preservation'
    Assert-Condition ($browserEvidence.interactions.replacementOptionsLoaded -eq $true) 'CEK-26 browser evidence did not prove replacement option loading'
    Assert-Condition ([int] $browserEvidence.consoleErrorCount -eq 0) 'CEK-26 browser evidence contains console errors'
    Assert-Condition ([int] $browserEvidence.failedRequestCount -eq 0) 'CEK-26 browser evidence contains failed requests'

    $browserVerification = [ordered]@{
        status = 'fresh_browser_evidence'
        evidencePath = [System.IO.Path]::GetRelativePath($repoRoot, $resolvedBrowserEvidencePath).Replace('\', '/')
        checkedAt = $browserCheckedAt.ToUniversalTime().ToString('o')
        desktop = $browserEvidence.desktop
        mobile = $browserEvidence.mobile
        interactions = $browserEvidence.interactions
        consoleErrorCount = [int] $browserEvidence.consoleErrorCount
        failedRequestCount = [int] $browserEvidence.failedRequestCount
    }
} elseif ($RequireBrowserEvidence) {
    throw 'CEK-26 fresh browser evidence is required but BrowserEvidencePath was not provided'
}

Assert-Condition ($vite.Contains("'/knowledge-evidence': localApiProxy")) 'CEK-26 Vite knowledge-evidence proxy is missing'
Assert-Condition ($vite.Contains('VITE_KQG_API_PROXY_TARGET')) 'CEK-26 configurable API proxy target is missing'

foreach ($forbidden in @(
    'importKey',
    'migration',
    'rollback',
    'active switch',
    'switchActive',
    'applyActive'
)) {
    Assert-Condition (-not $panel.Contains($forbidden)) "CEK-26 teacher panel exposes an admin-only field or action: $forbidden"
}

$liveApiProbe = [ordered]@{
    status = 'not_requested'
    apiPort = $null
    complexMappingTotal = $null
    replacementOptionCount = $null
    productionEligible = $false
}
if ($ApiPort -gt 0) {
    $baseUrl = "http://127.0.0.1:$ApiPort"
    $reviews = Invoke-RestMethod -Uri "$baseUrl/knowledge-evidence/reviews?groupId=complex_mappings&page=1&pageSize=1" -TimeoutSec 20
    Assert-Condition (@($reviews.items).Count -eq 1) 'CEK-26 live API probe returned no complex mapping candidate'
    Assert-Condition ($reviews.productionEligible -eq $false) 'CEK-26 review list must remain productionEligible=false'
    $candidateId = $reviews.items[0].candidateId
    $options = Invoke-RestMethod -Uri "$baseUrl/knowledge-evidence/reviews/$candidateId/replacement-options" -TimeoutSec 30
    Assert-Condition ($options.productionEligible -eq $false) 'CEK-26 replacement options must remain productionEligible=false'
    Assert-Condition (@($options.items).Count -gt 0) 'CEK-26 live API probe returned no replacement options'
    $liveApiProbe = [ordered]@{
        status = 'pass'
        apiPort = $ApiPort
        complexMappingTotal = [int]$reviews.totalCount
        replacementOptionCount = @($options.items).Count
        productionEligible = $false
    }
}

$report = [ordered]@{
    status = 'pass'
    task = 'CEK-26'
    mode = 'ui_contract'
    checkedAt = (Get-Date).ToUniversalTime().ToString('o')
    reviewGroups = @(
        'complex_mappings',
        'low_confidence_mappings',
        'curriculum_requirements',
        'assessment_targets',
        'regional_profiles'
    )
    teacherActions = @('approve', 'return', 'change_mapping', 'keep_pending', 'undo')
    reasonRequired = $true
    pagination = $true
    networkRetryState = $true
    retrospectiveCrosswalkDisclosed = $true
    sourcePageLinks = $true
    knowledgeRoles = @('primary', 'secondary')
    difficultySourcesDistinguished = @('question_estimated', 'annual_report_observed')
    interactionTests = 5
    replacementOptionsAllowlisted = $true
    responsiveBreakpoint = '860px'
    failClosedDefaults = $true
    adminOnlyTechnicalFieldsHidden = $true
    activeApplyAllowed = $false
    productionEligible = $false
    browserVerification = $browserVerification
    liveApiProbe = $liveApiProbe
    boundary = 'This contract proves the CEK-26 source, client, fail-closed normalization, and responsive UI markers. It does not approve candidates, switch C002 active assets, prove identity authentication, or replace live browser and teacher acceptance.'
    evidence = [ordered]@{
        panel = 'apps/web/src/ui/CurriculumEvidenceReviewPanel.tsx'
        tests = 'apps/web/src/ui/CurriculumEvidenceReviewPanel.test.tsx'
        adminMount = 'apps/web/src/ui/AdminGovernancePanels.tsx'
        client = 'apps/web/src/api/client.ts'
        contracts = 'apps/web/src/api/contracts.ts'
        style = 'apps/web/src/App.css'
        proxy = 'apps/web/vite.config.ts'
        report = $ReportPath.Replace('\', '/')
    }
    rollback = [ordered]@{
        code = 'revert only the CEK-26 web, test, contract, and plan slice'
        data = 'no database, review decision, active asset, or production state is changed by this contract'
    }
}

New-Item -ItemType Directory -Path (Split-Path -Parent $resolvedReportPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedReportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8

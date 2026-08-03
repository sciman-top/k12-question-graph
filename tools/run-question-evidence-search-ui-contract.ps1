param(
    [string] $ReportPath = 'docs\evidence\cek030-question-evidence-search-ui.json',
    [int] $ApiPort = 0,
    [string] $BrowserEvidencePath = '',
    [int] $BrowserEvidenceMaxAgeMinutes = 120,
    [switch] $RequireBrowserEvidence
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$panelPath = Join-Path $repoRoot 'apps\web\src\ui\PaperWorkbenchPanels.tsx'
$dataPath = Join-Path $repoRoot 'apps\web\src\ui\workbenchData.tsx'
$testPath = Join-Path $repoRoot 'apps\web\src\ui\workbenchData.test.ts'
$appPath = Join-Path $repoRoot 'apps\web\src\App.tsx'
$cssPath = Join-Path $repoRoot 'apps\web\src\App.css'
$resolvedReportPath = Join-Path $repoRoot $ReportPath

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

$panel = Get-Content -LiteralPath $panelPath -Raw
$data = Get-Content -LiteralPath $dataPath -Raw
$tests = Get-Content -LiteralPath $testPath -Raw
$app = Get-Content -LiteralPath $appPath -Raw
$css = Get-Content -LiteralPath $cssPath -Raw

foreach ($marker in @(
    'data-flow="question-evidence-search"',
    'data-contract="cek030-evidence-cards"',
    '证据题库',
    '正式题库',
    '已审核预览',
    '候选预览',
    '预览结果不会进入正式题篮',
    '课标要求',
    '考查目标',
    '广州画像',
    '实测：',
    '估计：',
    '课标原页',
    '年报原页',
    '/source-documents/',
    '/page-screenshot',
    '加入题篮',
    '仅预览',
    '返回题篮',
    'data-state="question-evidence-loading"',
    'data-state="question-evidence-error"',
    'data-state="question-evidence-empty"',
    'data-action="clear-evidence-filters"',
    'data-action="question-evidence-search-refresh"'
)) {
    Assert-Condition ($panel.Contains($marker)) "missing CEK-30 panel marker: $marker"
}

foreach ($marker in @(
    'requirementId',
    'ability',
    'cognitiveDemand',
    'methodOrExperiment',
    'context',
    'representation',
    'profileId',
    'observedDifficultyMin',
    "previewMode: mode === 'candidate' || mode === 'reviewed'"
)) {
    Assert-Condition ($data.Contains($marker)) "missing CEK-30 filter marker: $marker"
}

foreach ($marker in @(
    'keeps evidence modes isolated and makes previews explicit',
    'offers every teacher-facing evidence dimension without mixing difficulty sources',
    'estimatedDifficultyMin'
)) {
    Assert-Condition ($tests.Contains($marker)) "missing CEK-30 data test marker: $marker"
}

foreach ($marker in @(
    'useQuestionEvidenceSearchQuery(questionEvidenceSearchParams)',
    'questionEvidenceParamsFor(filter, questionEvidenceMode)',
    'questionEvidenceParamsFor(activeEvidenceFilter, mode)',
    "questionEvidenceMode !== 'active' || !card.productionEligible",
    'selectQuestionEvidenceCard',
    'returnToQuestionBasket',
    'onClearEvidenceFilters={clearEvidenceFilters}'
)) {
    Assert-Condition ($app.Contains($marker)) "missing CEK-30 app marker: $marker"
}

foreach ($marker in @(
    '.evidence-search-controls',
    '.question-evidence-main',
    '.question-evidence-grid',
    '.question-evidence-title',
    '@media (max-width: 900px)',
    '@media (max-width: 560px)',
    'overflow-wrap: anywhere',
    'overflow-x: auto'
)) {
    Assert-Condition ($css.Contains($marker)) "missing CEK-30 responsive style marker: $marker"
}

foreach ($forbidden in @(
    'storage path',
    'migration key',
    'model route',
    'active switch'
)) {
    Assert-Condition (-not $panel.Contains($forbidden)) "CEK-30 exposes an admin-only term: $forbidden"
}

$liveApiProbe = [ordered]@{
    status = 'not_requested'
    apiPort = $null
    activeTotal = $null
    candidateTotal = $null
    candidatePreview = $null
    productionEligible = $false
}
if ($ApiPort -gt 0) {
    $baseUrl = "http://127.0.0.1:$ApiPort"
    $active = Invoke-RestMethod -Uri "$baseUrl/knowledge-evidence/questions?evidenceMode=active&pageSize=1" -TimeoutSec 30
    Assert-Condition ($active.evidenceMode -eq 'active') 'CEK-30 active search returned the wrong evidence mode'
    Assert-Condition ($active.previewMode -eq $false) 'CEK-30 active search must not be preview mode'
    Assert-Condition ($active.productionEligible -eq $true) 'CEK-30 active search boundary must be production eligible'

    $candidate = Invoke-RestMethod -Uri "$baseUrl/knowledge-evidence/questions?evidenceMode=candidate&previewMode=true&pageSize=1" -TimeoutSec 30
    Assert-Condition ($candidate.evidenceMode -eq 'candidate') 'CEK-30 candidate search returned the wrong evidence mode'
    Assert-Condition ($candidate.previewMode -eq $true) 'CEK-30 candidate search must be explicit preview mode'
    Assert-Condition ($candidate.productionEligible -eq $false) 'CEK-30 candidate search must remain productionEligible=false'
    Assert-Condition ([int] $candidate.total -gt 0) 'CEK-30 candidate preview returned no real evidence questions'
    Assert-Condition (@($candidate.items).Count -eq 1) 'CEK-30 candidate preview did not return the requested card'

    $liveApiProbe = [ordered]@{
        status = 'pass'
        apiPort = $ApiPort
        activeTotal = [int] $active.total
        candidateTotal = [int] $candidate.total
        candidatePreview = $true
        productionEligible = $false
    }
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
    Assert-Condition ($browserEvidence.status -eq 'pass') 'CEK-30 browser evidence status must be pass'

    $browserCheckedAt = [DateTimeOffset] $browserEvidence.checkedAt
    $browserEvidenceAge = [DateTimeOffset]::UtcNow - $browserCheckedAt.ToUniversalTime()
    Assert-Condition ($browserEvidenceAge.TotalMinutes -ge -5) 'CEK-30 browser evidence timestamp is too far in the future'
    Assert-Condition ($browserEvidenceAge.TotalMinutes -le $BrowserEvidenceMaxAgeMinutes) 'CEK-30 browser evidence is stale'

    foreach ($viewportName in @('desktop', 'mobile')) {
        $viewport = $browserEvidence.$viewportName
        Assert-Condition ($viewport.pageOverflow -eq $false) "CEK-30 $viewportName browser evidence has page overflow"
        Assert-Condition ($viewport.panelOverflow -eq $false) "CEK-30 $viewportName browser evidence has panel overflow"
        Assert-Condition ([int] $viewport.clippedControlLabelCount -eq 0) "CEK-30 $viewportName browser evidence has clipped control labels"
        Assert-Condition ([int] $viewport.clippedCardTextCount -eq 0) "CEK-30 $viewportName browser evidence has clipped card text"
    }
    Assert-Condition ($browserEvidence.interactions.candidatePreviewSeparated -eq $true) 'CEK-30 browser evidence did not prove candidate preview separation'
    Assert-Condition ($browserEvidence.interactions.candidateBasketDisabled -eq $true) 'CEK-30 browser evidence did not prove candidate basket blocking'
    Assert-Condition ($browserEvidence.interactions.filterApplied -eq $true) 'CEK-30 browser evidence did not prove filter application'
    Assert-Condition ($browserEvidence.interactions.clearRestored -eq $true) 'CEK-30 browser evidence did not prove filter clearing'
    Assert-Condition ($browserEvidence.interactions.sourceLinksPresent -eq $true) 'CEK-30 browser evidence did not prove source links'
    Assert-Condition ($browserEvidence.interactions.sourceLinksHttp200 -eq $true) 'CEK-30 browser evidence did not prove source links return HTTP 200'
    $requiredSourceKinds = @('question', 'answer', 'curriculum', 'annual_report')
    foreach ($sourceKind in $requiredSourceKinds) {
        $sourceResult = @($browserEvidence.sourceLinkResults | Where-Object { $_.kind -eq $sourceKind }) | Select-Object -First 1
        Assert-Condition ($null -ne $sourceResult) "CEK-30 browser evidence lacks source result: $sourceKind"
        Assert-Condition ([int] $sourceResult.status -eq 200) "CEK-30 source link did not return HTTP 200: $sourceKind"
        Assert-Condition ([string] $sourceResult.contentType -like 'image/*') "CEK-30 source link did not return an image: $sourceKind"
    }
    Assert-Condition ($browserEvidence.interactions.returnToBasketReachable -eq $true) 'CEK-30 browser evidence did not prove the return-to-basket path'
    Assert-Condition ([int] $browserEvidence.consoleErrorCount -eq 0) 'CEK-30 browser evidence contains console errors'
    Assert-Condition ([int] $browserEvidence.failedRequestCount -eq 0) 'CEK-30 browser evidence contains failed requests'

    $browserVerification = [ordered]@{
        status = 'fresh_browser_evidence'
        evidencePath = [System.IO.Path]::GetRelativePath($repoRoot, $resolvedBrowserEvidencePath).Replace('\', '/')
        checkedAt = $browserCheckedAt.ToUniversalTime().ToString('o')
        desktop = $browserEvidence.desktop
        mobile = $browserEvidence.mobile
        interactions = $browserEvidence.interactions
        sourceLinkResults = $browserEvidence.sourceLinkResults
        consoleErrorCount = [int] $browserEvidence.consoleErrorCount
        failedRequestCount = [int] $browserEvidence.failedRequestCount
    }
} elseif ($RequireBrowserEvidence) {
    throw 'CEK-30 fresh browser evidence is required but BrowserEvidencePath was not provided'
}

$report = [ordered]@{
    status = 'pass'
    task = 'CEK-30'
    mode = 'ui_contract'
    checkedAt = (Get-Date).ToUniversalTime().ToString('o')
    evidenceModes = @('active', 'reviewed', 'candidate')
    teacherFilters = @('requirement', 'ability', 'cognitive', 'method', 'context', 'representation', 'profile', 'observed_difficulty')
    difficultySourcesDistinguished = @('observed', 'estimated')
    previewResultsSeparated = $true
    candidateBasketAllowed = $false
    clearRetryReturnPaths = $true
    sourcePageLinks = @('question', 'answer', 'curriculum', 'annual_report')
    activeApplyAllowed = $false
    liveApiProbe = $liveApiProbe
    browserVerification = $browserVerification
    boundary = 'CEK-30 proves the teacher-facing evidence search UI, explicit preview separation, source links, and return paths. It does not review candidates, activate C002R, submit a paper, or close REAL005.'
    evidence = [ordered]@{
        panel = 'apps/web/src/ui/PaperWorkbenchPanels.tsx'
        data = 'apps/web/src/ui/workbenchData.tsx'
        tests = 'apps/web/src/ui/workbenchData.test.ts'
        app = 'apps/web/src/App.tsx'
        style = 'apps/web/src/App.css'
        report = $ReportPath.Replace('\', '/')
    }
    rollback = [ordered]@{
        code = 'revert only the CEK-30 panel, data, app, style, test, contract, and plan slice'
        data = 'the UI contract and browser verification do not write review decisions, active assets, papers, or production state'
    }
}

$reportDirectory = Split-Path -Parent $resolvedReportPath
New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
$report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $resolvedReportPath -Encoding utf8
$report | ConvertTo-Json -Depth 20

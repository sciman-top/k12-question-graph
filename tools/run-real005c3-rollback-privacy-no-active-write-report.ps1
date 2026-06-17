param(
    [string] $Real005C1ReportPath = '',
    [string] $Real005C2ReportPath = '',
    [string] $NoActiveWriteGuardPath = 'docs/evidence/20260529-ns204-no-active-write-guard-report.json',
    [string] $JsonReportPath = '',
    [string] $MarkdownReportPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runDate = Get-Date -Format 'yyyyMMdd'

function Resolve-RepoPath([string] $Path) {
    Join-Path $repoRoot $Path
}

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
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

if ([string]::IsNullOrWhiteSpace($JsonReportPath)) {
    $JsonReportPath = ('docs/evidence/{0}-real005c3-rollback-privacy-no-active-write-report.json' -f $runDate)
}

if ([string]::IsNullOrWhiteSpace($MarkdownReportPath)) {
    $MarkdownReportPath = ('docs/evidence/{0}-real005c3-rollback-privacy-no-active-write-report.md' -f $runDate)
}

$Real005C1ReportPath = Resolve-LatestEvidencePath -Filter '*-real005c1-real-question-search-paper-export-smoke.json' -PreferredPath $Real005C1ReportPath
$Real005C2ReportPath = Resolve-LatestEvidencePath -Filter '*-real005c2-real-question-analysis-reference-smoke.json' -PreferredPath $Real005C2ReportPath

Assert-True (-not [string]::IsNullOrWhiteSpace($Real005C1ReportPath)) 'missing REAL005C1 smoke report path'
Assert-True (-not [string]::IsNullOrWhiteSpace($Real005C2ReportPath)) 'missing REAL005C2 smoke report path'

$real005C1 = Try-ReadJson $Real005C1ReportPath
$real005C2 = Try-ReadJson $Real005C2ReportPath
$ns204 = Try-ReadJson $NoActiveWriteGuardPath

Assert-True ($null -ne $real005C1) "missing REAL005C1 report: $Real005C1ReportPath"
Assert-True ($null -ne $real005C2) "missing REAL005C2 report: $Real005C2ReportPath"
Assert-True ($null -ne $ns204) "missing NS204 guard report: $NoActiveWriteGuardPath"

Assert-True ([string] $real005C1.status -eq 'pass') 'REAL005C1 report must pass'
Assert-True ([string] $real005C1.rg010Status -eq 'pass') 'REAL005C1 must expose RG010 pass'
Assert-True ([bool] $real005C1.activeWrite) 'REAL005C1 must record activeWrite=true'
Assert-True ([int] $real005C1.externalAiCalls -eq 0) 'REAL005C1 must keep externalAiCalls=0'
Assert-True (-not [bool] $real005C1.realStudentDataUsed) 'REAL005C1 must keep realStudentDataUsed=false'
Assert-True (-not [bool] $real005C1.productionEligible) 'REAL005C1 must stay non-production'
Assert-True (-not [string]::IsNullOrWhiteSpace([string] $real005C1.rollbackSql)) 'REAL005C1 rollbackSql is required'
Assert-True ([string] $real005C1.successPreflight.status -eq 'ready_for_review') 'REAL005C1 success preflight must be ready_for_review'
Assert-True ([string] $real005C1.anomalyPreflight.status -eq 'blocked') 'REAL005C1 anomaly preflight must stay blocked'
Assert-True ([int] $real005C1.anomalyPreflight.derivedIssueCounts.solution_missing -ge 1) 'REAL005C1 anomaly must retain solution_missing blocker'

Assert-True ([string] $real005C2.status -eq 'pass') 'REAL005C2 report must pass'
Assert-True ([string] $real005C2.rg011Status -eq 'pass') 'REAL005C2 must expose RG011 pass'
Assert-True ([bool] $real005C2.activeWrite) 'REAL005C2 must record activeWrite=true'
Assert-True ([int] $real005C2.externalAiCalls -eq 0) 'REAL005C2 must keep externalAiCalls=0'
Assert-True (-not [bool] $real005C2.realStudentDataUsed) 'REAL005C2 must keep realStudentDataUsed=false'
Assert-True (-not [bool] $real005C2.productionEligible) 'REAL005C2 must stay non-production'
Assert-True (-not [string]::IsNullOrWhiteSpace([string] $real005C2.rollbackSql)) 'REAL005C2 rollbackSql is required'
Assert-True ([string] $real005C2.successExport.status -eq 'ready') 'REAL005C2 commentary export must be ready'
Assert-True (-not [bool] $real005C2.successExport.writesProductionHistory) 'REAL005C2 commentary export must not write production history'
Assert-True (-not [bool] $real005C2.successExport.allowAiDraftText) 'REAL005C2 commentary export must keep allowAiDraftText=false'
Assert-True (@($real005C2.blockedExport.blockingIssueCodes) -contains 'knowledge_mapping_missing') 'REAL005C2 blocked export must retain knowledge_mapping_missing'

Assert-True ([string] $ns204.status -eq 'pass') 'NS204 no-active-write guard must pass'
$ns204Acceptance = $ns204.acceptance
Assert-True ([bool] $ns204Acceptance.aiCandidatesStayPendingReview) 'NS204 must keep aiCandidatesStayPendingReview'
Assert-True ([bool] $ns204Acceptance.dynamicAssetActiveSwitchBlocked) 'NS204 must keep dynamicAssetActiveSwitchBlocked'
Assert-True ([bool] $ns204Acceptance.scoreAnalysisDraftOnly) 'NS204 must keep scoreAnalysisDraftOnly'
Assert-True ([bool] $ns204Acceptance.productionHistoryWriteBlocked) 'NS204 must keep productionHistoryWriteBlocked'
Assert-True ([bool] $ns204Acceptance.liveClosureNotClaimed) 'NS204 must keep liveClosureNotClaimed'
Assert-True ([string] $ns204.e2e.real005ClosureStatus -eq 'not_closed') 'NS204 must keep REAL005 closure status not_closed'

$rollbackTargets = [ordered]@{
    real005c1 = [ordered]@{
        questionRollback = [int] @($real005C1.promotedSuccessSamples).Count + 1
        basketRollback = 2
        rollbackContainsKnowledgeNodeDelete = ([string] $real005C1.rollbackSql).Contains('delete from knowledge_nodes')
        rollbackContainsReviewQueueDelete = ([string] $real005C1.rollbackSql).Contains('delete from review_queue_items')
    }
    real005c2 = [ordered]@{
        questionRollback = [int] @($real005C2.promotedSuccessSamples).Count + 1
        scoreImportRollback = ([string] $real005C2.rollbackSql).Contains('delete from score_import_batches')
        assessmentRollback = ([string] $real005C2.rollbackSql).Contains('delete from assessments')
        rollbackContainsKnowledgeNodeDelete = ([string] $real005C2.rollbackSql).Contains('delete from knowledge_nodes')
        rollbackContainsReviewQueueDelete = ([string] $real005C2.rollbackSql).Contains('delete from review_queue_items')
    }
}

$report = [ordered]@{
    status = 'pass'
    taskId = 'REAL005C3_ROLLBACK_PRIVACY_NO_ACTIVE_WRITE'
    criterionId = 'RG012'
    rg012Status = 'pass'
    checkedAt = (Get-Date).ToString('s')
    evidence = [ordered]@{
        real005c1Report = $Real005C1ReportPath
        real005c2Report = $Real005C2ReportPath
        ns204Report = $NoActiveWriteGuardPath
    }
    batchBoundaries = [ordered]@{
        real005c1 = [ordered]@{
            activeWrite = [bool] $real005C1.activeWrite
            externalAiCalls = [int] $real005C1.externalAiCalls
            realStudentDataUsed = [bool] $real005C1.realStudentDataUsed
            productionEligible = [bool] $real005C1.productionEligible
            anomalyStatus = [string] $real005C1.anomalyPreflight.status
            anomalySolutionMissing = [int] $real005C1.anomalyPreflight.derivedIssueCounts.solution_missing
        }
        real005c2 = [ordered]@{
            activeWrite = [bool] $real005C2.activeWrite
            externalAiCalls = [int] $real005C2.externalAiCalls
            realStudentDataUsed = [bool] $real005C2.realStudentDataUsed
            productionEligible = [bool] $real005C2.productionEligible
            writesProductionHistory = [bool] $real005C2.successExport.writesProductionHistory
            blockedKnowledgeMappingMissing = (@($real005C2.blockedExport.blockingIssueCodes) -contains 'knowledge_mapping_missing')
        }
    }
    rollbackTargets = $rollbackTargets
    noActiveWriteGuard = [ordered]@{
        reportPath = $NoActiveWriteGuardPath
        aiCandidatesStayPendingReview = [bool] $ns204Acceptance.aiCandidatesStayPendingReview
        dynamicAssetActiveSwitchBlocked = [bool] $ns204Acceptance.dynamicAssetActiveSwitchBlocked
        scoreAnalysisDraftOnly = [bool] $ns204Acceptance.scoreAnalysisDraftOnly
        productionHistoryWriteBlocked = [bool] $ns204Acceptance.productionHistoryWriteBlocked
        liveClosureNotClaimed = [bool] $ns204Acceptance.liveClosureNotClaimed
        real005ClosureStatus = [string] $ns204.e2e.real005ClosureStatus
    }
    boundary = 'Repo-side RG012 report only: it proves REAL005C1 and REAL005C2 both leave explicit rollbackSql, stay synthetic/privacy-safe, keep external AI disabled, and remain under the no-active-write boundary. REAL005 still stays not_closed until RG013-RG016 also pass.'
    summaryChinese = 'REAL005C1 与 REAL005C2 的写库批次现在都有 repo-side RG012 证据：rollbackSql 明确、realStudentDataUsed=false、externalAiCalls=0、productionEligible=false，并继续受 NS204 no-active-write 守卫约束。'
}

$jsonFullPath = Resolve-RepoPath $JsonReportPath
$markdownFullPath = Resolve-RepoPath $MarkdownReportPath
New-Item -ItemType Directory -Path (Split-Path -Parent $jsonFullPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonFullPath -Encoding UTF8
@(
    '# REAL005C3 Rollback Privacy No-Active-Write Report',
    '',
    "- status: $($report.status)",
    "- criterion_id: $($report.criterionId)",
    "- rg012_status: $($report.rg012Status)",
    ('- real005c1_report: `{0}`' -f $Real005C1ReportPath),
    ('- real005c2_report: `{0}`' -f $Real005C2ReportPath),
    ('- ns204_report: `{0}`' -f $NoActiveWriteGuardPath),
    '',
    '## Boundary',
    $report.boundary
) | Set-Content -LiteralPath $markdownFullPath -Encoding UTF8

$report | ConvertTo-Json -Depth 12

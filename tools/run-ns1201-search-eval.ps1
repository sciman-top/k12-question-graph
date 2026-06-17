param(
    [string] $ReportPath = '',
    [string] $NonSitePlanPath = 'tasks/non-site-implementation-plan.csv',
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $R001ReportPath = '',
    [string] $R001DecisionPath = 'docs/decisions/ADR-010-search-semantic-retrieval-admission.md',
    [string] $R001ChecklistPath = 'docs/templates/r001-search-semantic-retrieval-eval-checklist.md',
    [string] $R001PreflightEvidencePath = 'docs/evidence/20260505-r001-search-semantic-retrieval-eval-preflight.md',
    [string] $CompletionDashboardPath = 'tasks/completion-state-dashboard.csv',
    [string] $HostCapabilityPath = 'docs/evidence/o002-host-capability-diagnostic-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runDate = Get-Date -Format 'yyyyMMdd'

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = ('docs/evidence/{0}-ns1201-search-eval.json' -f $runDate)
}

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Resolve-InRepoPath([string] $RelativePath) {
    return Join-Path $repoRoot ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
}

function Read-Json([string] $Path) {
    $fullPath = Resolve-InRepoPath $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing json report: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}
function Resolve-LatestEvidencePath([string] $Filter) {
    $evidenceRoot = Resolve-InRepoPath 'docs/evidence'
    Assert-Condition (Test-Path -LiteralPath $evidenceRoot) 'missing docs/evidence directory'
    $latest = @(Get-ChildItem -LiteralPath $evidenceRoot -Filter $Filter -File | Sort-Object Name -Descending | Select-Object -First 1)
    Assert-Condition ($latest.Count -eq 1) "missing evidence matching filter: $Filter"
    return [System.IO.Path]::GetRelativePath($repoRoot, $latest[0].FullName).Replace('\', '/')
}

if ([string]::IsNullOrWhiteSpace($R001ReportPath)) {
    $R001ReportPath = Resolve-LatestEvidencePath '*-r001-search-semantic-retrieval-admission-report.json'
}

function Get-RequiredRow([object[]] $Rows, [string] $Id, [string] $Column = 'id') {
    $matches = @($Rows | Where-Object { [string]$_.$Column -eq $Id })
    Assert-Condition ($matches.Count -eq 1) "expected exactly one $Column=$Id row"
    return $matches[0]
}

function Assert-TextContains([string] $Text, [string[]] $Needles, [string] $Label) {
    foreach ($needle in $Needles) {
        Assert-Condition ($Text.Contains($needle)) "$Label missing text: $needle"
    }
}

function Find-CodePatternHits([string[]] $RelativeRoots, [string[]] $Patterns) {
    $hits = @()
    foreach ($relativeRoot in $RelativeRoots) {
        $fullRoot = Resolve-InRepoPath $relativeRoot
        if (-not (Test-Path -LiteralPath $fullRoot)) { continue }

        $files = @(Get-ChildItem -LiteralPath $fullRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $_.FullName -notmatch '\\(bin|obj|node_modules)\\'
        })
        foreach ($file in $files) {
            foreach ($pattern in $Patterns) {
                $matches = @(Select-String -LiteralPath $file.FullName -Pattern $pattern -CaseSensitive:$false -ErrorAction SilentlyContinue)
                foreach ($match in $matches) {
                    $hits += [ordered]@{
                        path = $file.FullName.Substring($repoRoot.Length + 1)
                        line = $match.LineNumber
                        pattern = $pattern
                    }
                }
            }
        }
    }

    return @($hits)
}

Push-Location $repoRoot
try {
    $planFullPath = Resolve-InRepoPath $NonSitePlanPath
    $backlogFullPath = Resolve-InRepoPath $BacklogPath
    $decisionFullPath = Resolve-InRepoPath $R001DecisionPath
    $checklistFullPath = Resolve-InRepoPath $R001ChecklistPath
    $preflightEvidenceFullPath = Resolve-InRepoPath $R001PreflightEvidencePath
    $completionDashboardFullPath = Resolve-InRepoPath $CompletionDashboardPath

    foreach ($requiredPath in @($planFullPath, $backlogFullPath, $decisionFullPath, $checklistFullPath, $preflightEvidenceFullPath, $completionDashboardFullPath)) {
        Assert-Condition (Test-Path -LiteralPath $requiredPath) "missing required file: $requiredPath"
    }

    $planRows = @(Import-Csv -LiteralPath $planFullPath -Encoding UTF8)
    $backlogRows = @(Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8)
    $dashboardRows = @(Import-Csv -LiteralPath $completionDashboardFullPath -Encoding UTF8)

    $ns1005 = Get-RequiredRow $planRows 'NS1005'
    $ns1201 = Get-RequiredRow $planRows 'NS1201'
    Assert-Condition ($ns1005.status -eq 'blocked_by_onsite') 'NS1201 must inherit NS1005 release-decision blocked_by_onsite boundary'
    Assert-Condition ($ns1201.depends_on -eq 'NS1005') 'NS1201 must continue to depend on NS1005'
    Assert-Condition ($ns1201.status -in @('planned','runtime_verified')) "NS1201 has unsupported status: $($ns1201.status)"
    Assert-Condition ($ns1201.acceptance -match 'PostgreSQL FTS' -and $ns1201.acceptance -match 'pgvector' -and $ns1201.acceptance -match '外部搜索') 'NS1201 acceptance must keep PostgreSQL-first admission boundary'

    $p006 = Get-RequiredRow $backlogRows 'P006'
    $r001 = Get-RequiredRow $backlogRows 'R001'
    Assert-Condition ($p006.status -eq '待办') 'NS1201 must not skip P006 release decision'
    Assert-Condition ($r001.status -eq '待办') 'NS1201 must not close R001 without real FTS benchmark evidence'
    Assert-Condition ($r001.depends_on -eq 'P006') 'R001 must continue to depend on P006'

    $r001Report = Read-Json $R001ReportPath
    $hostCapability = Read-Json $HostCapabilityPath

    Assert-Condition ($r001Report.status -eq 'pass') 'NS1201 requires R001 admission report to pass'
    Assert-Condition (-not [bool]$r001Report.closeTaskAllowed) 'R001 closeTaskAllowed must remain false'
    Assert-Condition ($r001Report.currentDecision -eq 'keep_R001_todo_postgresql_first_fail_closed') 'R001 decision must remain PostgreSQL-first fail-closed'
    Assert-Condition ($r001Report.currentBaseline.searchProfile -eq 'postgresql_fts_pg_trgm_first_pgvector_only_after_eval') 'R001 baseline must keep pgvector after eval'
    Assert-Condition ($r001Report.currentBaseline.filtersUseActiveAssetsByDefault -eq $true) 'question search must use active assets by default'
    Assert-Condition ($r001Report.currentBaseline.candidateAssetsExcludedByDefault -eq $true) 'question search must exclude candidate assets by default'
    Assert-Condition ($r001Report.currentBaseline.real005ClosureStatus -eq 'not_closed') 'REAL005 must remain not_closed through R001 baseline'

    $matrixByKind = @{}
    foreach ($entry in @($r001Report.admissionMatrix)) {
        $matrixByKind[[string]$entry.searchKind] = $entry
    }
    foreach ($kind in @('postgresql_fts_pg_trgm', 'pgvector_semantic_search', 'external_search_engine')) {
        Assert-Condition ($matrixByKind.ContainsKey($kind)) "R001 admission matrix missing: $kind"
    }
    Assert-Condition ($matrixByKind['postgresql_fts_pg_trgm'].currentDecision -eq 'current_default') 'PostgreSQL FTS/pg_trgm must remain current default'
    Assert-Condition ($matrixByKind['pgvector_semantic_search'].currentDecision -eq 'blocked_until_benchmark') 'pgvector must remain blocked until benchmark'
    Assert-Condition ($matrixByKind['external_search_engine'].currentDecision -eq 'blocked') 'external search must remain blocked'

    $decisionText = Get-Content -LiteralPath $decisionFullPath -Raw
    Assert-TextContains $decisionText @(
        'ADR-010',
        'fail-closed',
        'PostgreSQL FTS',
        'pg_trgm',
        'pgvector migration',
        'rollback/disable switch'
    ) 'ADR-010'

    $checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
    Assert-TextContains $checklistText @(
        'PostgreSQL FTS',
        'pgvector',
        'latency p50/p95',
        'miss case',
        'rollback',
        'fail-closed'
    ) 'R001 checklist'

    $preflightText = Get-Content -LiteralPath $preflightEvidenceFullPath -Raw
    Assert-TextContains $preflightText @(
        'R001',
        'platform_na',
        'gate_na',
        '语义检索',
        'fail-closed'
    ) 'R001 preflight evidence'

    $questionSearchArea = Get-RequiredRow $dashboardRows 'question-search' 'area_id'
    $advancedPlatformArea = Get-RequiredRow $dashboardRows 'advanced-platform' 'area_id'
    Assert-Condition ($questionSearchArea.current_state -eq 'teacher_validated') 'question-search dashboard state must remain teacher_validated'
    Assert-Condition ($questionSearchArea.blocking_gap -match 'P001') 'question-search must retain P001 field access/performance boundary'
    Assert-Condition ($advancedPlatformArea.usable_today -eq '不可使用') 'advanced-platform must remain unavailable before real bottleneck evidence'
    Assert-Condition ($hostCapability.recommendedProfiles.searchProfile.status -eq 'postgresql_first') 'host capability search profile must stay PostgreSQL-first'

    $codePatternHits = Find-CodePatternHits @('apps/api', 'apps/web/src') @(
        'pgvector',
        'CREATE\s+EXTENSION\s+.*vector',
        'embedding',
        'semantic',
        'ElasticSearch',
        'OpenSearch',
        'Meilisearch',
        'Typesense'
    )
    Assert-Condition ($codePatternHits.Count -eq 0) 'NS1201 found product code that appears to enable semantic/vector/external search'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS1201'
        checkedAt = (Get-Date).ToString('s')
        mode = 'search_semantic_retrieval_admission_boundary'
        productionEligible = $false
        nonSiteValidated = $false
        releaseReady = $false
        externalAiCalls = 0
        realStudentDataUsed = $false
        containsStudentPii = $false
        writesProductionHistory = $false
        activeAssetMutation = $false
        dependency = [ordered]@{
            ns1005 = $NonSitePlanPath
            r001Report = $R001ReportPath
            r001Decision = $R001DecisionPath
            r001Checklist = $R001ChecklistPath
            r001PreflightEvidence = $R001PreflightEvidencePath
            completionDashboard = $CompletionDashboardPath
            hostCapability = $HostCapabilityPath
        }
        backlog = [ordered]@{
            p006Status = [string]$p006.status
            r001Status = [string]$r001.status
            r001CloseTaskAllowed = $false
            ns1005Status = [string]$ns1005.status
            ns1201StatusAtCheck = [string]$ns1201.status
            ns1201DependsOn = [string]$ns1201.depends_on
        }
        currentBaseline = [ordered]@{
            searchProfile = [string]$r001Report.currentBaseline.searchProfile
            activeKnowledgeStatus = [string]$r001Report.currentBaseline.activeKnowledgeStatus
            activeKnowledgeVersion = [int]$r001Report.currentBaseline.activeKnowledgeVersion
            filtersUseActiveAssetsByDefault = [bool]$r001Report.currentBaseline.filtersUseActiveAssetsByDefault
            candidateAssetsExcludedByDefault = [bool]$r001Report.currentBaseline.candidateAssetsExcludedByDefault
            real012SearchTotal = [int]$r001Report.currentBaseline.real012SearchTotal
            real005ClosureStatus = [string]$r001Report.currentBaseline.real005ClosureStatus
        }
        admissionDecision = [ordered]@{
            postgresqlFtsPgTrgm = [string]$matrixByKind['postgresql_fts_pg_trgm'].currentDecision
            pgvectorSemanticSearch = [string]$matrixByKind['pgvector_semantic_search'].currentDecision
            externalSearchEngine = [string]$matrixByKind['external_search_engine'].currentDecision
            currentDecision = [string]$r001Report.currentDecision
        }
        codeScan = [ordered]@{
            searchedRoots = @('apps/api', 'apps/web/src')
            blockedPatterns = @('pgvector', 'CREATE EXTENSION vector', 'embedding', 'semantic', 'ElasticSearch', 'OpenSearch', 'Meilisearch', 'Typesense')
            hitCount = [int]$codePatternHits.Count
            noPgvectorMigration = $true
            noEmbeddingTableOrRoute = $true
            noExternalSearchDependency = $true
            noTeacherVisibleSemanticRoute = $true
        }
        acceptance = [ordered]@{
            r001AdmissionReportPassed = $true
            adr010FailClosedAccepted = $true
            postgresqlFtsPgTrgmKeptAsDefault = $true
            pgvectorBlockedUntilBenchmark = $true
            externalSearchBlocked = $true
            p006RemainsTodo = $true
            ns1005RemainsBlockedByOnsite = $true
            r001RemainsTodo = $true
            noPgvectorMigration = $true
            noEmbeddingGeneration = $true
            noExternalSearchSetup = $true
            noQueryRouteMutation = $true
            noProductionWrite = $true
        }
        nextRequiredEvidence = @(
            'P006 release decision record',
            'field teacher-query benchmark',
            'FTS miss-case corpus',
            'latency p50/p95 baseline',
            'teacher search-time improvement target',
            'pgvector extension and embedding privacy/cost/cache/delete plan',
            'index rebuild and rollback/disable switch evidence'
        )
        verification = [ordered]@{
            build = 'gate_na: admission boundary script only; no product code build required'
            test = 'tools/run-r001-search-semantic-retrieval-eval-preflight-contract.ps1 + tools/run-ns1201-search-eval.ps1'
            contractInvariant = 'NS1201 keeps PostgreSQL FTS/pg_trgm first, leaves R001/P006/NS1005 blocked, and verifies no pgvector/embedding/external-search product route was enabled'
            hotspot = 'gate_na: real search benchmark requires post-NS1005 release/field evidence and teacher query corpus'
        }
        teacherEfficiencyBoundary = 'ordinary teacher search flow is unchanged; NS1201 only prevents premature semantic-search infrastructure until real FTS insufficiency evidence exists'
        boundary = 'NS1201 verifies the search/semantic retrieval upgrade admission boundary only. It does not run a field benchmark, does not close R001, does not enable pgvector, does not generate embeddings, does not configure an external search engine, and does not change teacher-facing search routes.'
        rollback = "git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1 tools/README.md; git clean -f -- tools/run-ns1201-search-eval.ps1 $ReportPath"
        next = 'NS1202 can continue queue/worker scale admission boundary; real search upgrade remains blocked until P006/NS1005 and benchmark evidence exist.'
    }

    $jsonText = $report | ConvertTo-Json -Depth 12
    $reportFullPath = Resolve-InRepoPath $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $jsonText | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $jsonText
}
finally {
    Pop-Location
}

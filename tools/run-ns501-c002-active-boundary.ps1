param(
    [string] $ReportPath = 'docs/evidence/20260530-ns501-c002-active-boundary.json',
    [string] $K001ReportPath = 'docs/evidence/20260530-ns501-k001-source-report.json',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $ConnectionString = $env:KQG_CONNECTION_STRING
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Read-Json([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing report: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

Push-Location $repoRoot
try {
    $ns204 = Read-Json 'docs/evidence/20260529-ns204-no-active-write-guard-report.json'
    $ns406 = Read-Json 'docs/evidence/20260530-ns406-question-edit-audit-report.json'
    $c002r = Read-Json 'docs/evidence/c002r-versioned-revision-report.json'

    Assert-Condition ($ns204.status -eq 'pass') 'NS501 dependency NS204 report did not pass'
    Assert-Condition ($ns406.status -eq 'pass') 'NS501 dependency NS406 report did not pass'
    Assert-Condition ([bool]$ns204.acceptance.dynamicAssetActiveSwitchBlocked) 'NS501 requires active switch blocked evidence'
    Assert-Condition ([string]$ns204.e2e.real005ClosureStatus -eq 'not_closed') 'NS501 must preserve REAL005 not_closed boundary'
    Assert-Condition ([bool]$ns406.acceptance.questionRevisionAudited) 'NS501 requires NS406 question revision audit evidence'
    Assert-Condition ($c002r.status -eq 'pass') 'NS501 dependency C002R report did not pass'
    Assert-Condition ([string]$c002r.mode -eq 'dry_run') 'NS501 requires C002R dry_run mode'
    Assert-Condition ($c002r.teacherCanApplyActive -eq $false) 'NS501 must keep teacher active switch blocked'

    $k001Args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', 'tools/run-k001-active-c002-production-query-contract.ps1',
        '-DatabaseName', $DatabaseName,
        '-DatabaseUser', $DatabaseUser,
        '-DatabaseHost', $DatabaseHost,
        '-DatabasePort', $DatabasePort,
        '-DatabasePassword', $DatabasePassword,
        '-ReportPath', $K001ReportPath
    )
    if (-not [string]::IsNullOrWhiteSpace($ConnectionString)) {
        $k001Args += @('-ConnectionString', $ConnectionString)
    }

    $k001Output = & pwsh @k001Args 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "K001 active C002 dependency failed: $k001Output"

    $k001 = Read-Json $K001ReportPath
    Assert-Condition ($k001.status -eq 'pass') 'K001 source report did not pass'
    Assert-Condition ([string]$k001.activeKnowledgeVersion -eq 'junior-physics-guangzhou-source-derived-v1') 'NS501 active C002 version mismatch'
    Assert-Condition ([int]$k001.counts.activeAssets -eq 452) 'NS501 active asset count mismatch'
    Assert-Condition ([int]$k001.counts.candidateAssets -eq 0) 'NS501 candidate assets should be excluded from active default'
    Assert-Condition ([int]$k001.counts.pendingMappings -eq 0) 'NS501 active default must not contain pending mappings'
    Assert-Condition ([int]$k001.counts.appliedMigrations -ge 1) 'NS501 applied migration missing'
    Assert-Condition ([int]$k001.counts.sourceDocuments -eq 33) 'NS501 source document count mismatch'
    Assert-Condition ([bool]$k001.querySurfaces.questionSearch.filtersUseActiveAssetsByDefault) 'NS501 question search must use active assets by default'
    Assert-Condition ([bool]$k001.querySurfaces.questionSearch.candidateAssetsExcludedByDefault) 'NS501 question search must exclude candidates by default'
    Assert-Condition ([bool]$k001.querySurfaces.paperAssemblyConstraints.replacementAndBlueprintKeepVersionRef) 'NS501 paper assembly must keep version reference'
    Assert-Condition ([bool]$k001.querySurfaces.paperAssemblyConstraints.mappingImpactRequiredForFutureRevision) 'NS501 future revision must require mapping impact'
    Assert-Condition ([bool]$k001.querySurfaces.knowledgeMasteryAnalysis.historyWritesRemainGuarded) 'NS501 analysis history writes must remain guarded'
    Assert-Condition ($k001.realStudentDataUsed -eq $false) 'NS501 must not use real student data'
    Assert-Condition ([int]$k001.externalAiCalls -eq 0) 'NS501 must not call external AI'
    Assert-Condition ([bool]$k001.compatibility.doesNotMutateActiveAssets) 'NS501 must not mutate active assets'
    Assert-Condition ([bool]$k001.compatibility.doesNotWriteProductionHistory) 'NS501 must not write production history'

    $program = Get-Content -LiteralPath 'apps/api/Program.cs' -Raw
    foreach ($marker in @(
        'ActiveKnowledgeVersion',
        'PrimaryKnowledgeId',
        'KnowledgeMappingSources.Manual'
    )) {
        Assert-Condition ($program.Contains($marker)) "NS501 API marker missing: $marker"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS501'
        checkedAt = (Get-Date).ToString('s')
        mode = 'k001_active_c002_reference_boundary_plus_no_active_write_guard'
        productionEligible = $false
        queryReferenceProductionEligible = [bool]$k001.productionEligible
        dependency = [ordered]@{
            ns204 = 'docs/evidence/20260529-ns204-no-active-write-guard-report.json'
            ns406 = 'docs/evidence/20260530-ns406-question-edit-audit-report.json'
            c002r = 'docs/evidence/c002r-versioned-revision-report.json'
            k001 = $K001ReportPath
        }
        activeC002 = [ordered]@{
            activeKnowledgeVersion = [string]$k001.activeKnowledgeVersion
            importKey = [string]$k001.importKey
            materialBatchKey = [string]$k001.materialBatchKey
            activeAssets = [int]$k001.counts.activeAssets
            approvedMappings = [int]$k001.counts.approvedMappings
            appliedMigrations = [int]$k001.counts.appliedMigrations
            sourceDocuments = [int]$k001.counts.sourceDocuments
        }
        surfaces = [ordered]@{
            questionSearchDefault = [string]$k001.querySurfaces.questionSearch.defaultKnowledgeSource
            paperAssemblyDefault = [string]$k001.querySurfaces.paperAssemblyConstraints.defaultKnowledgeSource
            knowledgeMasteryDefault = [string]$k001.querySurfaces.knowledgeMasteryAnalysis.defaultKnowledgeSource
            filtersUseActiveAssetsByDefault = [bool]$k001.querySurfaces.questionSearch.filtersUseActiveAssetsByDefault
            candidateAssetsExcludedByDefault = [bool]$k001.querySurfaces.questionSearch.candidateAssetsExcludedByDefault
            replacementAndBlueprintKeepVersionRef = [bool]$k001.querySurfaces.paperAssemblyConstraints.replacementAndBlueprintKeepVersionRef
            historyWritesRemainGuarded = [bool]$k001.querySurfaces.knowledgeMasteryAnalysis.historyWritesRemainGuarded
        }
        revisionBoundary = [ordered]@{
            c002rMode = [string]$c002r.mode
            teacherCanApplyActive = [bool]$c002r.teacherCanApplyActive
            mappingTypes = @($c002r.mappingTypes)
            impactTypes = @($c002r.impactTypes)
            futureRevisionRequired = [string]$k001.compatibility.futureC002RRevisionRequired
            noActiveWriteGuardPassed = [bool]$ns204.acceptance.dynamicAssetActiveSwitchBlocked
        }
        acceptance = [ordered]@{
            questionSearchUsesActiveC002 = $true
            paperAssemblyUsesActiveC002 = $true
            knowledgeMasteryUsesActiveC002 = $true
            activeVersionReferencePreserved = $true
            candidateAssetsExcludedByDefault = $true
            futureRevisionRequiresCandidateReviewRollback = $true
            activeSwitchNotPerformed = $true
            productionHistoryNotWritten = $true
            externalAiCallsZero = $true
            realStudentDataNotUsed = $true
            real005StillNotClosed = $true
        }
        boundary = 'NS501 proves active C002 v1 is the default reference for question search, paper assembly constraints, and knowledge mastery analysis while future revisions remain candidate/review/rollback guarded. It is read-only, performs no active switch, writes no production history, uses no real student data, and does not close REAL005.'
        next = 'NS502 can continue AI schema/eval so AI suggestions stay candidate/pending_review with no active write.'
        rollback = "git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns501-c002-active-boundary.ps1 docs/evidence/20260530-ns501-c002-active-boundary.json docs/evidence/20260530-ns501-k001-source-report.json"
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}

param(
    [string] $ReportPath = 'docs/evidence/20260529-ns204-no-active-write-guard-report.json'
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
    Assert-Condition (Test-Path -LiteralPath $fullPath) "NS204 required evidence missing: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Read-Text([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "NS204 required text file missing: $Path"
    return Get-Content -LiteralPath $fullPath -Raw
}

Push-Location $repoRoot
try {
    $aiReadinessSample = Read-Json 'configs/ai-evals/c002q0-outer-ai-readiness.sample.json'
    $aiDryRunSample = Read-Json 'configs/ai-evals/c002q-ai-extract-dry-run.sample.json'
    $aiReadinessReport = Read-Json 'docs/evidence/c002q0-outer-ai-readiness-report.json'
    $aiDryRunReport = Read-Json 'docs/evidence/c002q-ai-extract-dry-run-report.json'
    $c002r = Read-Json 'docs/evidence/c002r-versioned-revision-report.json'
    $k005 = Read-Json 'docs/evidence/k005-c002-second-revision-drill-report.json'
    $s011a = Read-Json 'docs/evidence/20260508-s011a-score-import-api-smoke-report.json'
    $s011b = Read-Json 'docs/evidence/20260508-s011b-item-score-mapping-ui-api-report.json'
    $s011c = Read-Json 'docs/evidence/20260508-s011c-commentary-report-export-report.json'
    $s012b = Read-Json 'docs/evidence/20260509-s012b-non-site-e2e-rehearsal-report.json'
    $real012 = Read-Json 'docs/evidence/20260518-real012-production-flow-quality-report.json'
    $router = Read-Text 'apps/api/Ai/AiModelRouter.cs'
    $adminPanels = Read-Text 'apps/web/src/ui/AdminGovernancePanels.tsx'

    Assert-Condition ($aiReadinessSample.allowProjectRuntimeRealModelCalls -eq $false) 'AI readiness sample must disable project runtime real model calls'
    Assert-Condition ($aiReadinessSample.noActiveWrite -eq $true) 'AI readiness sample must require noActiveWrite'
    Assert-Condition ($aiReadinessSample.productionEligible -eq $false) 'AI readiness sample must not be production eligible'
    Assert-Condition ([string]$aiReadinessSample.reviewStatus -eq 'pending_review') 'AI readiness sample must stay pending_review'

    Assert-Condition ($aiDryRunSample.allowRealModelCalls -eq $false) 'AI dry-run sample must disable real model calls'
    Assert-Condition ([int]$aiDryRunSample.externalAiCalls -eq 0) 'AI dry-run sample must make zero external calls'
    Assert-Condition ($aiDryRunSample.noActiveWrite -eq $true) 'AI dry-run sample must require noActiveWrite'
    Assert-Condition ($aiDryRunSample.productionEligible -eq $false) 'AI dry-run sample must not be production eligible'
    Assert-Condition ([string]$aiDryRunSample.reviewStatus -eq 'pending_review') 'AI dry-run sample must stay pending_review'

    Assert-Condition ($aiReadinessReport.noActiveWrite -eq $true) 'AI readiness report must preserve noActiveWrite'
    Assert-Condition ($aiReadinessReport.productionEligible -eq $false) 'AI readiness report must not be production eligible'
    Assert-Condition ([int]$aiReadinessReport.externalAiCallsInReadiness -eq 0) 'AI readiness report must make zero external calls'
    Assert-Condition ($aiDryRunReport.noActiveWrite -eq $true) 'AI dry-run report must preserve noActiveWrite'
    Assert-Condition ($aiDryRunReport.productionEligible -eq $false) 'AI dry-run report must not be production eligible'
    Assert-Condition ([int]$aiDryRunReport.externalAiCalls -eq 0) 'AI dry-run report must make zero external calls'

    Assert-Condition ([string]$c002r.mode -eq 'dry_run') 'C002R revision report must remain dry_run'
    Assert-Condition ($c002r.teacherCanApplyActive -eq $false) 'teacher must not apply active switch from C002R'
    Assert-Condition ([string]$k005.mode -eq 'dry_run') 'K005 second revision drill must remain dry_run'
    Assert-Condition ($k005.noActiveWrite -eq $true) 'K005 must not write active data'
    Assert-Condition ($k005.oldActivePreserved -eq $true) 'K005 must preserve old active version'
    Assert-Condition ($k005.noProductionHistoryRewrite -eq $true) 'K005 must not rewrite production history'

    foreach ($report in @($s011a, $s011b, $s011c)) {
        Assert-Condition ($report.productionEligible -ne $true) "score/analysis smoke must not be productionEligible=true: $($report.taskId)"
        Assert-Condition ($report.auditTrail -contains 'no_ai_runtime_dependency') "score/analysis smoke must avoid AI runtime dependency: $($report.taskId)"
    }
    Assert-Condition ($s011a.auditTrail -contains 'wrote_draft_test_score_records') 'score import must write only draft/test score records'
    Assert-Condition ($s011a.auditTrail -contains 'blocked_pii') 'score import must block PII before database write'
    Assert-Condition ($s011b.auditTrail -contains 'no_real_student_data') 'item score mapping preview must avoid real student data'
    Assert-Condition ($s011b.auditTrail -contains 'no_production_history_write') 'item score mapping preview must avoid production history writes'
    Assert-Condition ($s011c.auditTrail -contains 'no_real_student_data') 'commentary export must avoid real student data'
    Assert-Condition ($s011c.auditTrail -contains 'no_production_history_write') 'commentary export must avoid production history writes'

    Assert-Condition ($s012b.productionEligible -eq $false) 'S012B non-site E2E rehearsal must not be production eligible'
    Assert-Condition ($s012b.realStudentDataUsed -eq $false) 'S012B must not use real student data'
    Assert-Condition ($s012b.conclusion -match 'not a live teacher/site validation') 'S012B must keep live/site validation boundary explicit'

    Assert-Condition ($real012.real005ClosureStatus -eq 'not_closed') 'REAL012 must keep REAL005 not_closed'
    Assert-Condition ($real012.analysis.allowAiDraftText -eq $false) 'REAL012 analysis must not enable AI draft text'
    Assert-Condition ($real012.analysis.writesProductionHistory -eq $false) 'REAL012 analysis must not write production history'

    foreach ($marker in @(
        'real_model_calls_disabled',
        'formal_active_domain_asset_required',
        'ProductionEligible: blockers.Count == 0 && !IsLlmHandler(handler)'
    )) {
        Assert-Condition ($router.Contains($marker)) "AI router missing no-active-write fail-closed marker: $marker"
    }

    foreach ($marker in @(
        'data-contract="candidate-pending-review-only"',
        'data-contract="no-direct-active-switch"',
        'data-contract="no-active-write"',
        'data-contract="admin-readonly-actions"'
    )) {
        Assert-Condition ($adminPanels.Contains($marker)) "admin UI missing no-active-write marker: $marker"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS204'
        checkedAt = (Get-Date).ToString('s')
        mode = 'evidence_and_static_no_active_write_guard'
        productionEligible = $false
        ai = [ordered]@{
            readinessNoActiveWrite = [bool]$aiReadinessReport.noActiveWrite
            dryRunNoActiveWrite = [bool]$aiDryRunReport.noActiveWrite
            externalAiCalls = [int]$aiDryRunReport.externalAiCalls
            reviewStatus = [string]$aiDryRunSample.reviewStatus
        }
        dynamicAssets = [ordered]@{
            c002rMode = [string]$c002r.mode
            teacherCanApplyActive = [bool]$c002r.teacherCanApplyActive
            k005NoActiveWrite = [bool]$k005.noActiveWrite
            oldActivePreserved = [bool]$k005.oldActivePreserved
        }
        scoreAnalysis = [ordered]@{
            s011aProductionEligible = [bool]$s011a.productionEligible
            s011bProductionEligible = [bool]$s011b.productionEligible
            s011cProductionEligible = [bool]$s011c.productionEligible
            commentaryWritesProductionHistory = $false
        }
        e2e = [ordered]@{
            s012bProductionEligible = [bool]$s012b.productionEligible
            s012bRealStudentDataUsed = [bool]$s012b.realStudentDataUsed
            real005ClosureStatus = [string]$real012.real005ClosureStatus
        }
        acceptance = [ordered]@{
            aiCandidatesStayPendingReview = $true
            externalAiDefaultOff = $true
            dynamicAssetActiveSwitchBlocked = $true
            scoreAnalysisDraftOnly = $true
            productionHistoryWriteBlocked = $true
            liveClosureNotClaimed = $true
        }
        boundary = 'NS204 proves non-site AI/import/dynamic-asset/analysis flows remain draft, candidate, pending_review, noActiveWrite, or not_closed; it does not enable production active switches.'
        next = 'NS301 can continue SourceDocument evidence layer and upload metadata smoke.'
        rollback = 'git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns204-no-active-write-guard.ps1 docs/evidence/20260529-ns204-no-active-write-guard-report.json'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 6
}
finally {
    Pop-Location
}

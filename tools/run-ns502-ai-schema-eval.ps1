param(
    [string] $ReportPath = 'docs/evidence/20260530-ns502-ai-schema-eval-report.json',
    [string] $C002OReportPath = 'docs/evidence/20260530-ns502-c002o-candidate-extraction-eval-report.json',
    [string] $C002QReportPath = 'docs/evidence/20260530-ns502-c002q-ai-extract-dry-run-report.json'
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

function Assert-PendingReviewItems([object[]] $Items, [string] $SectionName) {
    Assert-Condition (@($Items).Count -ge 1) "NS502 section has no candidates: $SectionName"
    foreach ($item in @($Items)) {
        Assert-Condition ([string]$item.review_status -eq 'pending_review') "NS502 $SectionName item must stay pending_review"
        Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$item.candidate_id)) "NS502 $SectionName item missing candidate_id"
    }
}

Push-Location $repoRoot
try {
    $ns501 = Read-Json 'docs/evidence/20260530-ns501-c002-active-boundary.json'
    Assert-Condition ($ns501.status -eq 'pass') 'NS502 dependency NS501 report did not pass'
    Assert-Condition ([bool]$ns501.acceptance.futureRevisionRequiresCandidateReviewRollback) 'NS502 requires NS501 candidate/review/rollback boundary'

    $c002oOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File 'tools/run-c002o-candidate-extraction-eval.ps1' `
        -Output $C002OReportPath 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "C002O candidate extraction eval dependency failed: $c002oOutput"

    $c002qOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File 'tools/run-c002q-ai-extract-dry-run.ps1' `
        -Output $C002QReportPath 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "C002Q AI extract dry-run dependency failed: $c002qOutput"

    $s007aOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File 'tools/run-s007a-ai-suggestion-schema-hardening.ps1' 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "S007A AI suggestion schema dependency failed: $s007aOutput"

    $c002o = Read-Json $C002OReportPath
    $c002q = Read-Json $C002QReportPath
    $s007a = Read-Json 'docs/evidence/20260506-s007a-ai-suggestion-schema-hardening-report.json'
    $s011c = Read-Json 'docs/evidence/20260508-s011c-commentary-report-export-report.json'

    Assert-Condition ($c002o.status -eq 'pass' -and $c002o.task -eq 'C002O') 'C002O source report did not pass'
    Assert-Condition ([string]$c002o.mode -eq 'draft_test') 'NS502 C002O must stay draft_test'
    Assert-Condition ($c002o.allowRealModelCalls -eq $false) 'NS502 C002O must not allow real model calls'
    Assert-Condition ($c002o.productionEligible -eq $false) 'NS502 C002O must not be production eligible'
    Assert-Condition (@($c002o.cases).Count -ge 1) 'NS502 C002O cases missing'
    foreach ($case in @($c002o.cases)) {
        Assert-Condition ([string]$case.reviewStatus -eq 'pending_review') 'NS502 C002O case must stay pending_review'
        Assert-Condition ([int]$case.knowledgePoints -ge 1) 'NS502 C002O must cover knowledge point candidates'
        Assert-Condition ([int]$case.curriculumStandardItems -ge 1) 'NS502 C002O must cover curriculum candidates'
        Assert-Condition ([int]$case.textbookChapters -ge 1) 'NS502 C002O must cover textbook chapter candidates'
        Assert-Condition ([int]$case.examPoints -ge 1) 'NS502 C002O must cover exam point candidates'
        Assert-Condition ([int]$case.trendSummaries -ge 1) 'NS502 C002O must cover commentary/trend draft candidates'
        Assert-Condition ([int]$case.mappingSuggestions -ge 1) 'NS502 C002O must cover mapping suggestions'
    }

    Assert-Condition ($c002q.status -eq 'pass' -and $c002q.task -eq 'C002Q') 'C002Q source report did not pass'
    Assert-Condition ([string]$c002q.mode -eq 'draft_test') 'NS502 C002Q must stay draft_test'
    Assert-Condition ($c002q.allowRealModelCalls -eq $false) 'NS502 C002Q must not allow real model calls'
    Assert-Condition ([int]$c002q.externalAiCalls -eq 0) 'NS502 C002Q must not call external AI'
    Assert-Condition ($c002q.productionEligible -eq $false) 'NS502 C002Q must not be production eligible'
    Assert-Condition ([string]$c002q.reviewStatus -eq 'pending_review') 'NS502 C002Q root review status must stay pending_review'
    Assert-Condition ([bool]$c002q.noActiveWrite) 'NS502 C002Q must keep noActiveWrite'
    Assert-Condition ($c002q.overwritesExistingC002K -eq $false) 'NS502 C002Q must not overwrite existing C002K'
    Assert-Condition ($c002q.requiresHumanReview -eq $true) 'NS502 C002Q must require human review'
    Assert-Condition ([string]$c002q.candidateOutput.mode -eq 'draft_test') 'NS502 candidate output must stay draft_test'
    Assert-Condition ($c002q.candidateOutput.production_eligible -eq $false) 'NS502 candidate output must not be production eligible'
    Assert-Condition ([string]$c002q.candidateOutput.review_status -eq 'pending_review') 'NS502 candidate output review status mismatch'

    Assert-PendingReviewItems @($c002q.candidateOutput.knowledge_points) 'knowledge_points'
    Assert-PendingReviewItems @($c002q.candidateOutput.curriculum_standard_items) 'curriculum_standard_items'
    Assert-PendingReviewItems @($c002q.candidateOutput.textbook_chapters) 'textbook_chapters'
    Assert-PendingReviewItems @($c002q.candidateOutput.exam_points) 'exam_points'
    Assert-PendingReviewItems @($c002q.candidateOutput.trend_summaries) 'trend_summaries'
    Assert-Condition (@($c002q.candidateOutput.mapping_suggestions).Count -ge 1) 'NS502 mapping suggestions missing'
    foreach ($mapping in @($c002q.candidateOutput.mapping_suggestions)) {
        Assert-Condition ([string]$mapping.review_status -eq 'pending_review') 'NS502 mapping suggestion must stay pending_review'
        Assert-Condition ([double]$mapping.confidence -ge 0 -and [double]$mapping.confidence -le 1) 'NS502 mapping confidence must be bounded'
    }

    Assert-Condition ($s007a.status -eq 'pass' -and $s007a.taskId -eq 'S007A') 'S007A source report did not pass'
    foreach ($suggestionType in @('knowledge_tagging', 'question_type', 'difficulty_estimation', 'answer_verification')) {
        Assert-Condition (@($s007a.suggestionTypes) -contains $suggestionType) "NS502 suggestion envelope missing type: $suggestionType"
    }
    foreach ($field in @('required', 'status', 'review_queue_id')) {
        Assert-Condition (@($s007a.requiredReview) -contains $field) "NS502 suggestion review field missing: $field"
    }

    Assert-Condition ([string]$s011c.artifactPath -like 'draft://commentary-reports/*') 'NS502 commentary draft export must stay draft artifact'
    Assert-Condition ([string]$s011c.conclusion -match 'does not write formal history') 'NS502 commentary draft must not write formal history'
    Assert-Condition ($s011c.auditTrail -contains 'no_ai_runtime_dependency') 'NS502 commentary draft must not depend on AI runtime'
    Assert-Condition ($s011c.auditTrail -contains 'no_production_history_write') 'NS502 commentary draft must not write production history'

    $candidateSchema = Get-Content -LiteralPath 'schemas/ai/c002_candidate_extraction.schema.json' -Raw | ConvertFrom-Json
    foreach ($section in @('knowledge_points', 'curriculum_standard_items', 'textbook_chapters', 'exam_points', 'trend_summaries', 'mapping_suggestions')) {
        Assert-Condition ($candidateSchema.required -contains $section) "NS502 candidate extraction schema missing section: $section"
    }
    $answerSchema = Get-Content -LiteralPath 'schemas/ai/answer_verification.schema.json' -Raw | ConvertFrom-Json
    foreach ($field in @('question_id', 'extracted_answer', 'independent_answer', 'consistency', 'risk_level', 'issues', 'confidence', 'review_required')) {
        Assert-Condition ($answerSchema.required -contains $field) "NS502 answer verification schema missing field: $field"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS502'
        checkedAt = (Get-Date).ToString('s')
        mode = 'schema_eval_and_contract_dry_run_no_real_model'
        productionEligible = $false
        externalAiCalls = 0
        allowRealModelCalls = $false
        noActiveWrite = $true
        dependency = [ordered]@{
            ns501 = 'docs/evidence/20260530-ns501-c002-active-boundary.json'
            c002o = $C002OReportPath
            c002q = $C002QReportPath
            s007a = 'docs/evidence/20260506-s007a-ai-suggestion-schema-hardening-report.json'
            s011c = 'docs/evidence/20260508-s011c-commentary-report-export-report.json'
        }
        candidateOutput = [ordered]@{
            mode = [string]$c002q.candidateOutput.mode
            reviewStatus = [string]$c002q.candidateOutput.review_status
            productionEligible = [bool]$c002q.candidateOutput.production_eligible
            knowledgePoints = @($c002q.candidateOutput.knowledge_points).Count
            questionTypeCoveredBySchema = $true
            difficultyCoveredBySuggestionEnvelope = $true
            answerVerificationCoveredBySchema = $true
            commentaryDraftCoveredByTrendSummaryAndS011C = $true
            mappingSuggestions = @($c002q.candidateOutput.mapping_suggestions).Count
        }
        suggestionEnvelope = [ordered]@{
            suggestionTypes = @($s007a.suggestionTypes)
            requiredReview = @($s007a.requiredReview)
            requiredCost = @($s007a.requiredCost)
            requiredCache = @($s007a.requiredCache)
        }
        acceptance = [ordered]@{
            knowledgeCandidatesPendingReview = $true
            questionTypeSuggestionsReviewGated = $true
            difficultySuggestionsReviewGated = $true
            answerVerificationReviewGated = $true
            commentaryDraftNotAiRuntimeDependent = $true
            allOutputsCandidateOrPendingReview = $true
            externalAiCallsZero = $true
            localModelNotUsed = $true
            noActiveWrite = $true
        }
        boundary = 'NS502 proves AI-related schema/eval and candidate dry-run outputs remain draft_test, candidate/pending_review, productionEligible=false, noActiveWrite, and externalAiCalls=0. Commentary draft coverage is deterministic S011C plus trend summary candidate evidence, not a real AI-generated production report.'
        next = 'NS503 can continue ModelRouter budget, cache, token, and fail-closed routing contracts without enabling real model calls.'
        rollback = "git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns502-ai-schema-eval.ps1 docs/evidence/20260530-ns502-ai-schema-eval-report.json docs/evidence/20260530-ns502-c002o-candidate-extraction-eval-report.json docs/evidence/20260530-ns502-c002q-ai-extract-dry-run-report.json"
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}

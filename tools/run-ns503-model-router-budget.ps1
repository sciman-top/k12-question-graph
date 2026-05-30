param(
    [string] $ReportPath = 'docs/evidence/20260530-ns503-model-router-budget-report.json',
    [string] $D002SourceReportPath = 'docs/evidence/20260530-ns503-d002-ai-job-cost-source-report.json',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin'
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

function Read-Text([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing file: $Path"
    return Get-Content -LiteralPath $fullPath -Raw
}

function ConvertFrom-TrailingJson([string] $Text, [string] $Label) {
    $match = [regex]::Match($Text, '(?s)\{\s*"status"\s*:\s*"pass".*\}\s*$')
    Assert-Condition ($match.Success) "$Label did not end with a pass JSON object"
    return $match.Value | ConvertFrom-Json
}

Push-Location $repoRoot
try {
    $ns502 = Read-Json 'docs/evidence/20260530-ns502-ai-schema-eval-report.json'
    Assert-Condition ($ns502.status -eq 'pass') 'NS503 dependency NS502 report did not pass'
    Assert-Condition ([int]$ns502.externalAiCalls -eq 0) 'NS503 requires NS502 zero external AI calls'
    Assert-Condition ([bool]$ns502.acceptance.noActiveWrite) 'NS503 requires NS502 noActiveWrite'

    $c002pOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File 'tools/run-c002p-model-budget-guard.ps1' 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "C002P model budget dependency failed: $c002pOutput"
    $c002p = Read-Json 'docs/evidence/c002p-model-budget-guard-report.json'
    Assert-Condition ($c002p.status -eq 'pass' -and $c002p.task -eq 'C002P') 'C002P source report did not pass'
    Assert-Condition ([bool]$c002p.fullSourceExceedsDryRunLimits) 'NS503 full-source budget boundary missing'
    Assert-Condition ([bool]$c002p.fullExtractionRequiresHumanBudgetApproval) 'NS503 full extraction must require human budget approval'
    Assert-Condition ($c002p.realModelCallsDefault -eq $false) 'NS503 real model calls must remain disabled by default'
    Assert-Condition ([int]$c002p.sourceEvidence.cacheHitSourceCount -ge [int]$c002p.sourceEvidence.sourceCount) 'NS503 cache hit source count missing'
    Assert-Condition ([int]$c002p.sourceEvidence.estimatedInputTokens -gt [int]$c002p.dryRunLimits.max_estimated_input_tokens) 'NS503 full extraction token overrun evidence missing'
    Assert-Condition ([string]$c002p.highestRiskEscalation.model -eq 'gpt-5.5') 'NS503 highest-risk model escalation mismatch'
    Assert-Condition ([string]$c002p.highestRiskEscalation.reasoningEffort -eq 'xhigh') 'NS503 highest-risk reasoning mismatch'

    $d002Output = & pwsh -NoProfile -ExecutionPolicy Bypass -File 'tools/run-d002-ai-job-cost-contract.ps1' `
        -DatabaseName $DatabaseName `
        -DatabaseUser $DatabaseUser `
        -DatabaseHost $DatabaseHost `
        -DatabasePort $DatabasePort `
        -DatabasePassword $DatabasePassword `
        -PgBin $PgBin 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "D002 AI job cost dependency failed: $d002Output"
    $d002 = ConvertFrom-TrailingJson $d002Output 'D002 AI job cost dependency'
    Assert-Condition ($d002.status -eq 'pass') 'D002 source report did not pass'
    Assert-Condition ([string]$d002.idempotency -eq 'pass') 'NS503 D002 idempotency missing'
    Assert-Condition ([string]$d002.modelProvider -eq 'stub_llm') 'NS503 D002 must use stub_llm'
    Assert-Condition ([string]$d002.modelName -eq 'stub') 'NS503 D002 must use stub model'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$d002.promptVersion)) 'NS503 D002 promptVersion missing'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$d002.schemaVersion)) 'NS503 D002 schemaVersion missing'
    Assert-Condition ([int]$d002.inputTokens -gt 0) 'NS503 D002 input tokens missing'
    Assert-Condition ([int]$d002.outputTokens -gt 0) 'NS503 D002 output tokens missing'
    Assert-Condition ([int]$d002.cachedTokens -ge 0) 'NS503 D002 cached tokens missing'
    Assert-Condition ([decimal]$d002.actualCost -eq 0) 'NS503 stub job actual cost must be zero'
    Assert-Condition ([string]$d002.reviewStatus -eq 'pending_review') 'NS503 stub job must stay pending_review'

    $d002FullPath = Join-Path $repoRoot $D002SourceReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $d002FullPath) -Force | Out-Null
    $d002 | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $d002FullPath -Encoding UTF8

    $routing = Read-Text 'configs/model_routing.defaults.yaml'
    foreach ($marker in @(
        'cache_by_input_hash: true',
        'record_cached_tokens: true',
        'fail_closed_on_missing_token_estimate: true',
        'fail_closed_on_budget_overrun: true',
        'require_chunk_cache_before_external_ai: true',
        'require_budget_guard_before_external_ai: true',
        'require_human_budget_approval: true'
    )) {
        Assert-Condition ($routing.Contains($marker)) "NS503 routing config marker missing: $marker"
    }

    $router = Read-Text 'apps/api/Ai/AiModelRouter.cs'
    foreach ($marker in @(
        'structured_output_schema_missing',
        'real_model_calls_disabled',
        'ProductionEligible: blockers.Count == 0 && !IsLlmHandler(handler)',
        'CostTier: ResolveCostTier(handler, route.ModelTier)'
    )) {
        Assert-Condition ($router.Contains($marker)) "NS503 model router marker missing: $marker"
    }

    $program = Read-Text 'apps/api/Program.cs'
    foreach ($marker in @(
        'inputHash',
        'idempotencyKey',
        'InputTokens',
        'OutputTokens',
        'CachedTokens',
        'ActualCost'
    )) {
        Assert-Condition ($program.Contains($marker)) "NS503 API cost/cache marker missing: $marker"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS503'
        checkedAt = (Get-Date).ToString('s')
        mode = 'model_router_budget_cache_cost_fail_closed_contract'
        productionEligible = $false
        externalAiCalls = 0
        allowRealModelCalls = $false
        dependency = [ordered]@{
            ns502 = 'docs/evidence/20260530-ns502-ai-schema-eval-report.json'
            c002p = 'docs/evidence/c002p-model-budget-guard-report.json'
            d002 = $D002SourceReportPath
        }
        budget = [ordered]@{
            sourceCount = [int]$c002p.sourceEvidence.sourceCount
            chunkCount = [int]$c002p.sourceEvidence.chunkCount
            estimatedInputTokens = [int]$c002p.sourceEvidence.estimatedInputTokens
            dryRunInputTokenLimit = [int]$c002p.dryRunLimits.max_estimated_input_tokens
            fullSourceExceedsDryRunLimits = [bool]$c002p.fullSourceExceedsDryRunLimits
            fullExtractionRequiresHumanBudgetApproval = [bool]$c002p.fullExtractionRequiresHumanBudgetApproval
        }
        cache = [ordered]@{
            cacheHitSourceCount = [int]$c002p.sourceEvidence.cacheHitSourceCount
            cacheByInputHash = $true
            d002CachedTokens = [int]$d002.cachedTokens
        }
        aiJobCost = [ordered]@{
            jobId = [string]$d002.jobId
            modelProvider = [string]$d002.modelProvider
            modelName = [string]$d002.modelName
            promptVersion = [string]$d002.promptVersion
            schemaVersion = [string]$d002.schemaVersion
            inputTokens = [int]$d002.inputTokens
            outputTokens = [int]$d002.outputTokens
            actualCost = [decimal]$d002.actualCost
            reviewStatus = [string]$d002.reviewStatus
            idempotency = [string]$d002.idempotency
        }
        routing = [ordered]@{
            rolesChecked = @($c002p.rolesChecked)
            layersChecked = @($c002p.layersChecked)
            highestRiskModel = [string]$c002p.highestRiskEscalation.model
            highestRiskReasoningEffort = [string]$c002p.highestRiskEscalation.reasoningEffort
            realModelCallsDefault = [bool]$c002p.realModelCallsDefault
            failClosedOnMissingTokenEstimate = $true
            failClosedOnBudgetOverrun = $true
        }
        acceptance = [ordered]@{
            modelAndReasoningRecorded = $true
            tokenAndCostRecorded = $true
            cacheInputHashContractPresent = $true
            outputSchemaRecorded = $true
            budgetOverrunFailsClosed = $true
            realModelCallsStillDisabled = $true
            stubJobStaysPendingReview = $true
            noLocalModelUsed = $true
        }
        boundary = 'NS503 proves model routing budget/cache/cost/fail-closed contracts with C002P config evidence and a D002 stub AI job. It records token/cost/schema/prompt/idempotency without enabling real model calls, local model defaults, or external AI.'
        next = 'NS504 can continue AI suggestion review queue so teacher confirmation is required before writeback.'
        rollback = "git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns503-model-router-budget.ps1 docs/evidence/20260530-ns503-model-router-budget-report.json docs/evidence/20260530-ns503-d002-ai-job-cost-source-report.json"
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}

param(
    [string] $ReportPath = 'docs/evidence/20260529-ns106-feature-profile-guard-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Read-Text([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing required config: $Path"
    return Get-Content -LiteralPath $fullPath -Raw
}

function Assert-Contains([string] $Text, [string] $Needle, [string] $Message) {
    Assert-Condition ($Text.Contains($Needle)) $Message
}

Push-Location $repoRoot
try {
    $appSettings = Get-Content -LiteralPath 'apps/api/appsettings.json' -Raw | ConvertFrom-Json
    $installer = Read-Text 'configs/installer_init.defaults.yaml'
    $modelRouting = Read-Text 'configs/model_routing.defaults.yaml'
    $modelAdmission = Read-Text 'configs/model-admission.catalog.yaml'
    $ocrAdmission = Read-Text 'configs/ocr-engine-admission.catalog.yaml'
    $aiReadiness = Get-Content -LiteralPath 'configs/ai-evals/c002q0-outer-ai-readiness.sample.json' -Raw | ConvertFrom-Json
    $aiDryRun = Get-Content -LiteralPath 'configs/ai-evals/c002q-ai-extract-dry-run.sample.json' -Raw | ConvertFrom-Json
    $router = Read-Text 'apps/api/Ai/AiModelRouter.cs'

    Assert-Condition ($appSettings.AiRouting.AllowRealModelCalls -eq $false) 'appsettings must keep AiRouting.AllowRealModelCalls=false'
    Assert-Condition ($appSettings.AdminInternalGuard.AllowUnguardedDraftTest -eq $false) 'admin guard must not allow unguarded draft/test'
    Assert-Condition ([string]$appSettings.AdminInternalGuard.ApiKey -eq '') 'default admin API key must remain blank'

    foreach ($needle in @(
        'install_by_default: false',
        'download_models_by_default: false',
        'production_default_requires_eval: true',
        'no_active_write: true',
        'diagnostic_no_network: true',
        'production_change_requires_full_gate: true',
        'production_change_requires_backup_restore_evidence: true'
    )) {
        Assert-Contains $installer $needle "installer profile missing guard: $needle"
    }

    foreach ($needle in @(
        'allow_real_model_calls: false',
        'real_model_calls_enable_condition:',
        '- rule',
        '- local_ocr',
        '- local_document_parser',
        '- stub_llm',
        'require_human_budget_approval: true',
        'require_schema_eval_before_external_ai: true',
        'require_budget_guard_before_external_ai: true',
        'forbid_full_source_bulk_submission: true'
    )) {
        Assert-Contains $modelRouting $needle "model routing missing guard: $needle"
    }

    foreach ($needle in @(
        'defaultRouteChangeAllowed: false',
        'downloadAllowedByAutomation: false',
        'productionEligible: false',
        'allowedUse: eval_only'
    )) {
        Assert-Contains $modelAdmission $needle "model admission missing guard: $needle"
    }

    foreach ($needle in @(
        'defaultRouteChangeAllowed: false',
        'installAllowedByAutomation: false',
        'productionEligible: false',
        'allowedUse: local_eval_and_draft_test',
        'allowedUse: eval_only'
    )) {
        Assert-Contains $ocrAdmission $needle "OCR admission missing guard: $needle"
    }

    Assert-Condition ($aiReadiness.allowProjectRuntimeRealModelCalls -eq $false) 'outer AI readiness must disable project runtime real model calls'
    Assert-Condition ([int]$aiReadiness.externalAiCallsInReadiness -eq 0) 'outer AI readiness must make zero external AI calls'
    Assert-Condition ($aiReadiness.noActiveWrite -eq $true) 'outer AI readiness must require no active write'
    Assert-Condition ($aiReadiness.humanReviewRequired -eq $true) 'outer AI readiness must require human review'
    Assert-Condition ($aiReadiness.productionEligible -eq $false) 'outer AI readiness must not be production eligible'
    Assert-Condition ([string]$aiReadiness.reviewStatus -eq 'pending_review') 'outer AI readiness must remain pending_review'

    Assert-Condition ($aiDryRun.allowRealModelCalls -eq $false) 'AI extract dry-run must disable real model calls'
    Assert-Condition ([int]$aiDryRun.externalAiCalls -eq 0) 'AI extract dry-run must make zero external AI calls'
    Assert-Condition ($aiDryRun.noActiveWrite -eq $true) 'AI extract dry-run must require no active write'
    Assert-Condition ($aiDryRun.productionEligible -eq $false) 'AI extract dry-run must not be production eligible'
    Assert-Condition ([string]$aiDryRun.reviewStatus -eq 'pending_review') 'AI extract dry-run must remain pending_review'

    foreach ($needle in @(
        'real_model_calls_disabled',
        'formal_active_domain_asset_required',
        'structured_output_schema_missing',
        'ProductionEligible: blockers.Count == 0 && !IsLlmHandler(handler)',
        'return IsLlmHandler(handler) ? "stub_llm" : handler'
    )) {
        Assert-Contains $router $needle "AI router missing fail-closed guard: $needle"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS106'
        checkedAt = (Get-Date).ToString('s')
        mode = 'read_only_feature_profile_guard'
        productionEligible = $false
        noInstallPerformed = $true
        noNetworkRequired = $true
        appSettings = [ordered]@{
            allowRealModelCalls = [bool]$appSettings.AiRouting.AllowRealModelCalls
            adminApiKeyBlank = ([string]$appSettings.AdminInternalGuard.ApiKey -eq '')
            allowUnguardedDraftTest = [bool]$appSettings.AdminInternalGuard.AllowUnguardedDraftTest
        }
        localAiModels = [ordered]@{
            installByDefault = $false
            downloadModelsByDefault = $false
            productionDefaultRequiresEval = $true
            noActiveWrite = $true
        }
        externalAi = [ordered]@{
            readinessExternalAiCalls = [int]$aiReadiness.externalAiCallsInReadiness
            dryRunExternalAiCalls = [int]$aiDryRun.externalAiCalls
            projectRuntimeRealModelCalls = [bool]$aiReadiness.allowProjectRuntimeRealModelCalls
            allowRealModelCalls = [bool]$aiDryRun.allowRealModelCalls
        }
        admissionCatalogs = [ordered]@{
            modelDefaultRouteChangeAllowed = $false
            modelDownloadAllowedByAutomation = $false
            ocrDefaultRouteChangeAllowed = $false
            ocrInstallAllowedByAutomation = $false
        }
        acceptance = [ordered]@{
            externalAiDefaultOff = $true
            localModelInstallDownloadDefaultOff = $true
            cloudOrHeavyOcrRequiresAdmission = $true
            activeWriteBlockedByDefault = $true
            humanReviewRequiredForAiOutputs = $true
            adminAndProductionChangesRemainGuarded = $true
        }
        boundary = 'NS106 is a read-only config/profile guard. It does not enable cloud AI, local LLM, OCR route changes, active switches, or production defaults.'
        next = 'NS201 can continue role permission and high-risk audit baseline.'
        rollback = 'git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns106-feature-profile-guard.ps1 docs/evidence/20260529-ns106-feature-profile-guard-report.json'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 6
}
finally {
    Pop-Location
}

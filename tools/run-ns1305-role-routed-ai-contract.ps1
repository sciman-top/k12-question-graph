param(
    [string] $ProviderProfilesPath = 'configs\ai-provider-profiles.defaults.yaml',
    [string] $RoutingConfigPath = 'configs\model_routing.defaults.yaml',
    [string] $UiPath = 'apps/web/src/ui/AiRoutingControlPanel.tsx',
    [string] $AdminPanelsPath = 'apps/web/src/ui/AdminGovernancePanels.tsx',
    [string] $CssPath = 'apps/web/src/App.css',
    [string] $ReportPath = 'docs/evidence/20260607-ns1305-role-routed-ai.json'
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
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing json file: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Read-Text([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing text file: $Path"
    return Get-Content -LiteralPath $fullPath -Raw
}

function ConvertFrom-YamlWithPython([string] $Path) {
    $escapedPath = $Path.Replace('\', '\\')
    $rawJson = python -X utf8 -c "import json, pathlib, yaml; p=pathlib.Path(r'$escapedPath'); d=yaml.safe_load(p.read_text(encoding='utf-8')); print(json.dumps(d, ensure_ascii=False))"
    Assert-Condition ($LASTEXITCODE -eq 0) "failed to parse yaml: $Path"
    return $rawJson | ConvertFrom-Json
}

function ConvertFrom-TrailingJson([string] $Text, [string] $Label) {
    $match = [regex]::Match($Text, '(?s)\{\s*"status"\s*:\s*"pass".*\}\s*$')
    Assert-Condition ($match.Success) "$Label did not end with a pass JSON object"
    return $match.Value | ConvertFrom-Json
}

Push-Location $repoRoot
try {
    $ns1304 = Read-Json 'docs/evidence/20260607-ns1304-toolchain-profile.json'
    $ns204 = Read-Json 'docs/evidence/20260529-ns204-no-active-write-guard-report.json'
    $ns503 = Read-Json 'docs/evidence/20260530-ns503-model-router-budget-report.json'
    Assert-Condition ($ns1304.status -eq 'pass') 'NS1305 dependency NS1304 must pass'
    Assert-Condition ($ns204.status -eq 'pass') 'NS1305 dependency NS204 must pass'
    Assert-Condition ($ns503.status -eq 'pass') 'NS1305 dependency NS503 must pass'
    Assert-Condition ([bool]$ns204.acceptance.aiCandidatesStayPendingReview) 'NS1305 requires no-active-write pending_review boundary'
    Assert-Condition ([bool]$ns503.acceptance.budgetOverrunFailsClosed) 'NS1305 requires model budget fail-closed boundary'
    Assert-Condition ([bool]$ns503.acceptance.realModelCallsStillDisabled) 'NS1305 requires real model calls disabled by default'

    $d001Output = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'run-d001-model-router-contract.ps1') 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "NS1305 dependency D001 failed: $d001Output"
    $d001 = ConvertFrom-TrailingJson $d001Output 'D001 model router contract'
    Assert-Condition ($d001.draftKnowledgeProvider -eq 'stub_llm') 'NS1305 D001 must stay stub_llm in draft/test'

    $d003Output = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'run-d003-structured-output-eval.ps1') 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "NS1305 dependency D003 failed: $d003Output"
    $d003 = ConvertFrom-TrailingJson $d003Output 'D003 structured output eval'
    Assert-Condition ([bool]$d003.evalRepeatable) 'NS1305 requires repeatable structured output eval'

    $providerProfiles = ConvertFrom-YamlWithPython $ProviderProfilesPath
    $routingConfig = ConvertFrom-YamlWithPython $RoutingConfigPath

    Assert-Condition (([string]$providerProfiles.schemaVersion).Trim() -eq 'ai-provider-profiles.defaults.v0.1') 'unexpected provider profile schemaVersion'
    Assert-Condition (([string]$providerProfiles.mode).Trim() -eq 'draft_test') 'provider profiles must stay in draft_test mode'
    Assert-Condition (([string]$providerProfiles.schemaPath).Trim() -eq 'schemas/ai/provider_profiles.schema.json') 'provider profiles must declare schemaPath'
    Assert-Condition (@($providerProfiles.teacherSimpleModes).Count -ge 3) 'provider profiles must declare teacher simple modes'
    foreach ($modeId in @('offline_first', 'cloud_enhanced', 'local_enhanced')) {
        Assert-Condition (@($providerProfiles.teacherSimpleModes | Where-Object { ([string]$_.id).Trim() -eq $modeId }).Count -eq 1) "missing teacher simple mode: $modeId"
    }

    Assert-Condition (@($providerProfiles.providerProfiles).Count -ge 3) 'provider profiles must declare multiple provider profiles'
    foreach ($profile in @($providerProfiles.providerProfiles)) {
        Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$profile.id)) 'provider profile id is required'
        Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$profile.baseUrl)) "provider profile baseUrl missing: $($profile.id)"
        Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$profile.credentialRef)) "provider profile credentialRef missing: $($profile.id)"
        Assert-Condition ([int]$profile.maxConcurrency -ge 1) "provider profile maxConcurrency invalid: $($profile.id)"
        Assert-Condition ([int]$profile.monthlyBudgetCny -ge 0) "provider profile monthlyBudgetCny invalid: $($profile.id)"
        Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$profile.fallbackPolicy)) "provider profile fallbackPolicy missing: $($profile.id)"
        Assert-Condition (@($profile.roleScopes).Count -ge 1) "provider profile roleScopes missing: $($profile.id)"
        Assert-Condition (([string]$profile.secretRedaction).Trim() -eq 'always_masked') "provider profile secretRedaction must stay always_masked: $($profile.id)"
    }

    $cloudProfile = @($providerProfiles.providerProfiles | Where-Object { ([string]$_.id).Trim() -eq 'cloud_openai_candidate' }) | Select-Object -First 1
    Assert-Condition ($null -ne $cloudProfile) 'missing cloud_openai_candidate profile'
    Assert-Condition ((([string]$cloudProfile.credentialRef).Trim()) -like 'env:*') 'cloud profile must use env credential ref'
    Assert-Condition ([bool]$cloudProfile.disabledByDefault) 'cloud profile must stay disabled by default'

    $localProfile = @($providerProfiles.providerProfiles | Where-Object { ([string]$_.id).Trim() -eq 'local_llm_eval_gateway' }) | Select-Object -First 1
    Assert-Condition ($null -ne $localProfile) 'missing local_llm_eval_gateway profile'
    Assert-Condition ((([string]$localProfile.credentialRef).Trim()) -like 'env:*') 'local profile must use env credential ref'
    Assert-Condition ([bool]$localProfile.disabledByDefault) 'local profile must stay disabled by default'

    Assert-Condition ([bool]$providerProfiles.runtimeGuardrails.allowRealModelCallsDefault -eq $false) 'runtime guardrail must keep real model calls disabled by default'
    Assert-Condition ((([string]$providerProfiles.runtimeGuardrails.allOutputsDefaultReviewStatus).Trim()) -eq 'pending_review') 'runtime guardrail must keep pending_review default'
    Assert-Condition ((([string]$providerProfiles.runtimeGuardrails.allOutputsDefaultAssetStatus).Trim()) -eq 'candidate_or_draft') 'runtime guardrail must keep candidate/draft default'
    Assert-Condition ([bool]$providerProfiles.runtimeGuardrails.providerSecretValuesForbiddenInGit) 'runtime guardrail must forbid provider secrets in git'

    Assert-Condition ([bool]$routingConfig.outer_ai_validation.strategy_contract.model_names_are_current_mapping_only) 'routing config must keep model names as current mapping only'
    foreach ($roleName in @('bulk_prefilter_model', 'mechanical_cleanup_model', 'engineering_review_model', 'high_risk_review_model', 'highest_risk_decision_model')) {
        Assert-Condition ($null -ne $routingConfig.outer_ai_validation.role_to_model.$roleName) "routing config missing role_to_model entry: $roleName"
    }
    Assert-Condition ([bool]$routingConfig.cost_controls.cache_by_input_hash) 'routing config must keep cache_by_input_hash'
    Assert-Condition ([bool]$routingConfig.cost_controls.record_cached_tokens) 'routing config must keep record_cached_tokens'
    Assert-Condition ([bool]$routingConfig.local_first_contract.c002_budget_controls.require_budget_guard_before_external_ai) 'routing config must require budget guard before external AI'
    Assert-Condition ([bool]$routingConfig.local_first_contract.c002_budget_controls.full_extraction_limits.require_human_budget_approval) 'routing config must require human budget approval'
    Assert-Condition ([bool]$routingConfig.p0_p1_boundary.allow_real_model_calls -eq $false) 'routing config must keep real model calls disabled in P0/P1'

    $schemaPath = [string]$providerProfiles.schemaPath
    Assert-Condition (Test-Path -LiteralPath (Join-Path $repoRoot $schemaPath)) "missing provider profile schema: $schemaPath"

    $ui = Read-Text $UiPath
    $adminPanels = Read-Text $AdminPanelsPath
    $css = Read-Text $CssPath
    $router = Read-Text 'apps/api/Ai/AiModelRouter.cs'
    $appSettings = Read-Json 'apps/api/appsettings.json'

    foreach ($marker in @(
        'data-flow="ns1305-role-routed-ai"',
        'data-contract="admin-ai-routing-config"',
        'data-contract="teacher-simple-ai-modes"',
        'data-contract="provider-profiles-admin-only"',
        'data-contract="role-routed-policy"',
        'data-contract="admin-ai-actions"',
        'data-contract="ai-secret-redaction-no-active-write"'
    )) {
        Assert-Condition ($ui.Contains($marker)) "NS1305 UI marker missing: $marker"
    }

    foreach ($modeId in @('offline_first', 'cloud_enhanced', 'local_enhanced')) {
        Assert-Condition (
            $ui.Contains("data-mode=""$modeId""") -or
            $ui.Contains("id: '$modeId'") -or
            $ui.Contains("id: ""$modeId""")
        ) "NS1305 teacher mode marker missing: $modeId"
    }

    foreach ($actionName in @('open-provider-profile-catalog', 'open-role-routing-evidence', 'open-budget-cache-guard', 'open-secret-redaction-check')) {
        Assert-Condition (
            $ui.Contains("data-action=""$actionName""") -or
            $ui.Contains("action: '$actionName'")
        ) "NS1305 action marker missing: $actionName"
    }

    Assert-Condition ($adminPanels.Contains("from './AiRoutingControlPanel'")) 'NS1305 admin panels must import AiRoutingControlPanel'
    Assert-Condition ($adminPanels.Contains('<AiRoutingControlPanel />')) 'NS1305 admin panels must mount AiRoutingControlPanel'

    foreach ($cssMarker in @(
        '.ai-routing-panel',
        '.ai-routing-mode-grid',
        '.ai-provider-grid',
        '.ai-provider-card',
        '.ai-role-grid',
        '.ai-routing-actions'
    )) {
        Assert-Condition ($css.Contains($cssMarker)) "NS1305 CSS marker missing: $cssMarker"
    }

    Assert-Condition ($appSettings.AiRouting.AllowRealModelCalls -eq $false) 'appsettings must keep AllowRealModelCalls=false'
    foreach ($forbiddenModelName in @('gpt-', 'claude-', 'gemini-')) {
        Assert-Condition (-not $router.Contains($forbiddenModelName)) "business router must not hardcode model name: $forbiddenModelName"
    }
    Assert-Condition ($router.Contains('ModelTier')) 'business router must route by model tier or role abstraction'

    foreach ($forbiddenSecretPattern in @(
        '(?i)sk-[a-z0-9]{10,}',
        '(?i)api[_-]?key\s*[:=]\s*["''][^"'']{8,}',
        '(?i)password\s*[:=]\s*["''][^"'']+',
        '(?i)bearer\s+[a-z0-9._-]{10,}'
    )) {
        Assert-Condition (-not [regex]::IsMatch($ui, $forbiddenSecretPattern)) "NS1305 UI leaked secret-like value: $forbiddenSecretPattern"
        Assert-Condition (-not [regex]::IsMatch((Read-Text $ProviderProfilesPath), $forbiddenSecretPattern)) "NS1305 provider profile config leaked secret-like value: $forbiddenSecretPattern"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS1305'
        checkedAt = (Get-Date).ToString('s')
        mode = 'role_routed_ai_provider_profile_contract'
        productionEligible = $false
        dependency = [ordered]@{
            ns1304 = 'docs/evidence/20260607-ns1304-toolchain-profile.json'
            ns204 = 'docs/evidence/20260529-ns204-no-active-write-guard-report.json'
            ns503 = 'docs/evidence/20260530-ns503-model-router-budget-report.json'
            d001 = 'tools/run-d001-model-router-contract.ps1'
            d003 = 'tools/run-d003-structured-output-eval.ps1'
        }
        teacherSimpleModes = @($providerProfiles.teacherSimpleModes | ForEach-Object {
            [ordered]@{
                id = [string]$_.id
                label = [string]$_.label
                defaultProviderProfile = [string]$_.defaultProviderProfile
            }
        })
        providerProfiles = @($providerProfiles.providerProfiles | ForEach-Object {
            [ordered]@{
                id = [string]$_.id
                providerType = [string]$_.providerType
                credentialRef = [string]$_.credentialRef
                baseUrl = [string]$_.baseUrl
                maxConcurrency = [int]$_.maxConcurrency
                monthlyBudgetCny = [int]$_.monthlyBudgetCny
                fallbackPolicy = [string]$_.fallbackPolicy
                disabledByDefault = [bool]$_.disabledByDefault
            }
        })
        routing = [ordered]@{
            version = [string]$appSettings.AiRouting.Version
            promptVersion = [string]$appSettings.AiRouting.PromptVersion
            cacheByInputHash = [bool]$routingConfig.cost_controls.cache_by_input_hash
            recordCachedTokens = [bool]$routingConfig.cost_controls.record_cached_tokens
            allowRealModelCalls = [bool]$appSettings.AiRouting.AllowRealModelCalls
            roles = @($routingConfig.outer_ai_validation.role_to_model.PSObject.Properties.Name)
        }
        acceptance = [ordered]@{
            teacherSeesSimpleModesOnly = $true
            adminCanReviewMultipleProviderProfiles = $true
            apiKeyRefsAreRedacted = $true
            baseUrlConcurrencyBudgetFallbackVisible = $true
            businessCodeRoutesWithoutHardcodedModelNames = $true
            outputsStayCandidateDraftPendingReview = $true
            schemaEvalCostCacheNoActiveWriteBoundariesLinked = $true
            secretRedactionCheckPassed = $true
        }
        verification = [ordered]@{
            build = 'npm --prefix apps/web run build'
            test = 'npm --prefix apps/web run lint'
            contractInvariant = 'D001 + D003 + NS204 + NS503 + provider/routing UI contract + secret redaction check'
            hotspot = 'gate_na: no real cloud token enablement, no local model download, and no production default switch'
        }
        boundary = 'NS1305 proves the repository has an administrator-only role-routed AI configuration contract with simplified teacher modes, provider profile metadata, budget/cache/no-active-write links, and secret redaction. It does not enable real provider calls, does not store plaintext secrets, and does not switch production defaults.'
        rollback = "git restore apps/web/src/ui/AdminGovernancePanels.tsx apps/web/src/App.css docs/04_TechnologyStack.md tools/README.md tools/run-gates.ps1 tasks/non-site-implementation-plan.csv tasks/productization-roadmap.csv; git clean -f -- apps/web/src/ui/AiRoutingControlPanel.tsx configs/ai-provider-profiles.defaults.yaml schemas/ai/provider_profiles.schema.json $ReportPath tools/run-ns1305-role-routed-ai-contract.ps1"
        next = 'NS1306 stays on the same allowlisted tool boundary while NS1305 provides the administrator AI routing contract underneath.'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 10
}
finally {
    Pop-Location
}

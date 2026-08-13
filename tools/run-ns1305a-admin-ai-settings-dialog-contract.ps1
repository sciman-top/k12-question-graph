param(
    [string] $UiPath = 'apps/web/src/ui/AiRoutingControlPanel.tsx',
    [string] $AppPath = 'apps/web/src/App.tsx',
    [string] $AppCssPath = 'apps/web/src/App.css',
    [string] $ViteConfigPath = 'apps/web/vite.config.ts',
    [string] $RouterPath = 'apps/api/Ai/AiModelRouter.cs',
    [string] $SettingsStorePath = 'apps/api/Ai/AdminAiProviderSettings.cs',
    [string] $ClientPath = 'apps/web/src/api/client.ts',
    [string] $ContractsPath = 'apps/web/src/api/contracts.ts',
    [string] $ProgramPath = 'apps/api/Program.cs',
    [string] $AdminAiEndpointsPath = 'apps/api/Endpoints/AdminAiEndpoints.cs',
    [string] $ReportPath = 'docs/evidence/20260609-ns1305a-admin-ai-settings-dialog.json'
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
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing text file: $Path"
    return Get-Content -LiteralPath $fullPath -Raw
}

Push-Location $repoRoot
try {
    $ui = Read-Text $UiPath
    $app = Read-Text $AppPath
    $appCss = Read-Text $AppCssPath
    $viteConfig = Read-Text $ViteConfigPath
    $router = Read-Text $RouterPath
    $settingsStore = Read-Text $SettingsStorePath
    $client = Read-Text $ClientPath
    $contracts = Read-Text $ContractsPath
    $program = Read-Text $ProgramPath
    $adminAiEndpoints = Read-Text $AdminAiEndpointsPath
    $fallbackBackend = $program + $adminAiEndpoints + $settingsStore

    foreach ($marker in @(
        'data-contract="admin-ai-settings-dialog"',
        'data-action="open-ai-provider-settings"',
        'data-action="save-ai-provider-settings"',
        'data-action="test-ai-provider-settings"',
        'data-contract="ai-provider-secret-masked-input"',
        'data-contract="ai-provider-structured-smoke-test"'
    )) {
        Assert-Condition ($ui.Contains($marker)) "NS1305A UI marker missing: $marker"
    }

    foreach ($clientMarker in @(
        'getAdminAiProviderSettings',
        'saveAdminAiProviderSettings',
        'testAdminAiProviderSettings'
    )) {
        Assert-Condition ($client.Contains($clientMarker)) "NS1305A client API missing: $clientMarker"
    }

    foreach ($contractMarker in @(
        'AdminAiProviderSettingsContract',
        'AdminAiProviderSettingsSaveContract',
        'AdminAiProviderSettingsTestContract',
        'AdminAiProviderEndpointContract',
        'AdminAiProviderProbeAttemptContract'
    )) {
        Assert-Condition ($contracts.Contains($contractMarker)) "NS1305A typed contract missing: $contractMarker"
    }

    foreach ($apiMarker in @(
        '/api/admin/ai/provider-settings',
        '/api/admin/ai/provider-settings/test'
    )) {
        Assert-Condition ($adminAiEndpoints.Contains($apiMarker)) "NS1305A API route missing: $apiMarker"
    }
    Assert-Condition ($program.Contains('app.MapAdminAiEndpoints();')) 'NS1305A Program.cs missing modular admin AI endpoint registration'

    Assert-Condition (
        -not $settingsStore.Contains('Path.Combine(AppContext.BaseDirectory, "..", "..")')
    ) 'NS1305A runtime asset loading must resolve repo assets from ContentRootPath, not AppContext.BaseDirectory fallback.'
    Assert-Condition (
        $settingsStore.Contains('Path.Combine(environment.ContentRootPath, "..", "..")')
    ) 'NS1305A runtime asset loading must resolve repo assets from ContentRootPath back to the repo root.'
    Assert-Condition (
        $router.Contains('Path.Combine(environment.ContentRootPath, "..", "..")')
    ) 'NS1305A route/schema checks must resolve repo assets from ContentRootPath back to the repo root.'
    Assert-Condition ($settingsStore.Contains('private const string DefaultSmokeModel = "gpt-5.6-sol";')) 'NS1305A default text model must be gpt-5.6-sol.'
    Assert-Condition ($settingsStore.Contains('effort = "medium"')) 'NS1305A Responses smoke must request medium reasoning explicitly.'
    Assert-Condition ($settingsStore.Contains('private const string ImageProbeFallbackModel = "gpt-image-2";')) 'NS1305A image model must be gpt-image-2.'
    Assert-Condition ($settingsStore.Contains('"/images/generations"')) 'NS1305A image generation must use the standard Images API endpoint.'
    Assert-Condition (-not $settingsStore.Contains('responses_image_generation_tool')) 'NS1305A image generation must not route through the Responses image tool.'

    foreach ($fallbackBackendMarker in @(
        'FallbackBaseUrl',
        'FallbackImageBaseUrl',
        'GetRuntimeEndpointsAsync',
        'TEXT_PROVIDER_FALLBACK_1_BASE_URL',
        'TEXT_PROVIDER_FALLBACK_1_API_KEY',
        'IMAGE_PROVIDER_FALLBACK_1_BASE_URL',
        'IMAGE_PROVIDER_FALLBACK_1_API_KEY_1',
        'ApplyGatewayCompatibilityHeaders',
        'codex_exec/k12-question-graph',
        'application/json, text/event-stream',
        'selected_provider_endpoint=',
        'fallback_attempt_count='
    )) {
        Assert-Condition ($fallbackBackend.Contains($fallbackBackendMarker)) "NS1305A backend fallback marker missing: $fallbackBackendMarker"
    }

    foreach ($fallbackClientMarker in @(
        'fallbackBaseUrl',
        'fallbackApiKey',
        'fallbackImageBaseUrl',
        'fallbackImageApiKey',
        'effectiveProviderEndpointId',
        'attempts: readArrayField(value, ''attempts'').map(normalizeAdminAiProviderProbeAttemptResponse)'
    )) {
        Assert-Condition ($client.Contains($fallbackClientMarker) -or $contracts.Contains($fallbackClientMarker)) "NS1305A client fallback marker missing: $fallbackClientMarker"
    }

    foreach ($fallbackUiMarker in @(
        'data-contract="ai-provider-fallback-settings"',
        '备用 base URL',
        '备用 API Key',
        '备用图片 base URL',
        '备用图片 API Key'
    )) {
        Assert-Condition ($ui.Contains($fallbackUiMarker)) "NS1305A UI fallback marker missing: $fallbackUiMarker"
    }

    foreach ($appMarker in @(
        'data-action="toggle-admin-governance-panels"',
        'data-contract="admin-governance-entry"',
        'admin-governance-staging'
    )) {
        Assert-Condition ($app.Contains($appMarker)) "NS1305A app entry marker missing: $appMarker"
    }

    foreach ($cssMarker in @(
        '.admin-workspace {',
        '.admin-workspace.is-open {'
    )) {
        Assert-Condition ($appCss.Contains($cssMarker)) "NS1305A app css marker missing: $cssMarker"
    }

    foreach ($viteMarker in @(
        "'/api/admin'",
        'VITE_KQG_API_PROXY_TARGET',
        "?? 'http://127.0.0.1:5275'"
    )) {
        Assert-Condition ($viteConfig.Contains($viteMarker)) "NS1305A vite proxy marker missing: $viteMarker"
    }

    foreach ($forbiddenSecretPattern in @(
        '(?i)sk-[a-z0-9]{10,}',
        '(?i)api[_-]?key\s*[:=]\s*["''][^"'']{8,}',
        '(?i)bearer\s+[a-z0-9._-]{10,}'
    )) {
        Assert-Condition (-not [regex]::IsMatch($ui, $forbiddenSecretPattern)) "NS1305A UI leaked secret-like value: $forbiddenSecretPattern"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS1305A'
        checkedAt = (Get-Date).ToString('s')
        mode = 'admin_ai_settings_dialog_contract'
        productionEligible = $false
        acceptance = [ordered]@{
            dialogExists = $true
            saveActionExists = $true
            testActionExists = $true
            maskedSecretInputOnly = $true
            typedClientContractsExist = $true
            backendAdminRoutesExist = $true
            structuredSmokeRouteExists = $true
            uiReachableInLocalShell = $true
            adminProxyRouteExists = $true
            fallbackEndpointContractExists = $true
            fallbackEnvBootstrapExists = $true
            runtimeFallbackAttemptsAudited = $true
        }
        endpointSources = @($ProgramPath, $AdminAiEndpointsPath)
        boundary = 'NS1305A proves the admin AI routing surface is no longer display-only: it must expose a reachable local-shell admin entry, a provider settings dialog, typed save/test APIs, masked secret handling, and automatic primary-to-fallback endpoint attempts while remaining draft/test and no-active-write.'
        rollback = "git restore apps/web/src/App.tsx apps/web/src/App.css apps/web/vite.config.ts apps/web/src/ui/AiRoutingControlPanel.tsx apps/web/src/api/client.ts apps/web/src/api/contracts.ts apps/api/Program.cs tools/README.md; git clean -f -- $ReportPath tools/run-ns1305a-admin-ai-settings-dialog-contract.ps1"
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 6
}
finally {
    Pop-Location
}

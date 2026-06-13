param(
    [string] $UiPath = 'apps/web/src/ui/AiRoutingControlPanel.tsx',
    [string] $AppPath = 'apps/web/src/App.tsx',
    [string] $AppCssPath = 'apps/web/src/App.css',
    [string] $ViteConfigPath = 'apps/web/vite.config.ts',
    [string] $RouterPath = 'apps/api/Ai/AiModelRouter.cs',
    [string] $ClientPath = 'apps/web/src/api/client.ts',
    [string] $ContractsPath = 'apps/web/src/api/contracts.ts',
    [string] $ProgramPath = 'apps/api/Program.cs',
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
    $client = Read-Text $ClientPath
    $contracts = Read-Text $ContractsPath
    $program = Read-Text $ProgramPath

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
        'AdminAiProviderSettingsTestContract'
    )) {
        Assert-Condition ($contracts.Contains($contractMarker)) "NS1305A typed contract missing: $contractMarker"
    }

    foreach ($apiMarker in @(
        '/api/admin/ai/provider-settings',
        '/api/admin/ai/provider-settings/test'
    )) {
        Assert-Condition ($program.Contains($apiMarker)) "NS1305A API route missing: $apiMarker"
    }

    Assert-Condition (
        -not $program.Contains('Path.Combine(AppContext.BaseDirectory, "..", "..")')
    ) 'NS1305A runtime asset loading must resolve repo assets from ContentRootPath, not AppContext.BaseDirectory fallback.'
    Assert-Condition (
        $program.Contains('Path.Combine(environment.ContentRootPath, "..", "..")')
    ) 'NS1305A runtime asset loading must resolve repo assets from ContentRootPath back to the repo root.'
    Assert-Condition (
        $router.Contains('Path.Combine(environment.ContentRootPath, "..", "..")')
    ) 'NS1305A route/schema checks must resolve repo assets from ContentRootPath back to the repo root.'

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
        "target: 'http://127.0.0.1:5275'"
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
        }
        boundary = 'NS1305A proves the admin AI routing surface is no longer display-only: it must expose a reachable local-shell admin entry, a provider settings dialog, typed save/test APIs, and masked secret handling while remaining draft/test and no-active-write.'
        rollback = "git restore apps/web/src/App.tsx apps/web/src/App.css apps/web/vite.config.ts apps/web/src/ui/AiRoutingControlPanel.tsx apps/web/src/api/client.ts apps/web/src/api/contracts.ts apps/api/Program.cs tools/run-gates.ps1 tools/README.md; git clean -f -- $ReportPath tools/run-ns1305a-admin-ai-settings-dialog-contract.ps1"
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 6
}
finally {
    Pop-Location
}

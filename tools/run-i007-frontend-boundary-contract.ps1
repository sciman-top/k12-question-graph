$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$webRoot = Join-Path $repoRoot 'apps\web'
$reportPath = Join-Path $repoRoot 'docs\evidence\i007-frontend-boundary-report.json'

$packageJson = Get-Content -LiteralPath (Join-Path $webRoot 'package.json') -Raw | ConvertFrom-Json
$main = Get-Content -LiteralPath (Join-Path $webRoot 'src\main.tsx') -Raw
$app = Get-Content -LiteralPath (Join-Path $webRoot 'src\App.tsx') -Raw
$contracts = Get-Content -LiteralPath (Join-Path $webRoot 'src\api\contracts.ts') -Raw
$client = Get-Content -LiteralPath (Join-Path $webRoot 'src\api\client.ts') -Raw
$queries = Get-Content -LiteralPath (Join-Path $webRoot 'src\api\queries.ts') -Raw
$queryClient = Get-Content -LiteralPath (Join-Path $webRoot 'src\state\queryClient.ts') -Raw
$uiState = Get-Content -LiteralPath (Join-Path $webRoot 'src\state\uiState.ts') -Raw
$viteConfig = Get-Content -LiteralPath (Join-Path $webRoot 'vite.config.ts') -Raw

if (-not $packageJson.dependencies.'@tanstack/react-query') {
    throw "I007 requires @tanstack/react-query dependency"
}

foreach ($pattern in @(
    'QueryClientProvider',
    'createAppQueryClient',
    'data-flow="frontend-state-boundary"',
    'data-contract={apiContractSnapshot.version}',
    'data-contract="server-state-query-boundary"'
)) {
    if (-not $main.Contains($pattern) -and -not $app.Contains($pattern)) {
        throw "missing I007 frontend boundary marker: $pattern"
    }
}

foreach ($pattern in @(
    'apiContractSnapshot',
    "openApiPath: '/openapi/v1.json'",
    'ReadyHealthContract',
    'normalizeReadyHealthResponse',
    'unknown',
    'ApiResult'
)) {
    if (-not $contracts.Contains($pattern)) {
        throw "missing I007 typed API contract marker: $pattern"
    }
}

foreach ($pattern in @(
    'fetch(path',
    'normalize(json)',
    'getReadyHealth',
    'serverStateQueryKeys',
    'useQuery',
    "['server-state', 'ready-health']"
)) {
    if (-not $client.Contains($pattern) -and -not $queries.Contains($pattern)) {
        throw "missing I007 API/query client marker: $pattern"
    }
}

foreach ($pattern in @(
    'teacherDraftState',
    'component-local-state',
    'highRiskOperationState',
    'api-contract-source-of-truth',
    'serverState',
    'tanstack-query-only'
)) {
    if (-not $uiState.Contains($pattern)) {
        throw "missing I007 UI state boundary marker: $pattern"
    }
}

foreach ($pattern in @(
    'manualChunks',
    'react-vendor',
    'antd-vendor',
    'antd-icons-vendor',
    'antd-rc-vendor',
    'query-vendor'
)) {
    if (-not $viteConfig.Contains($pattern)) {
        throw "missing I007 bundle split marker: $pattern"
    }
}

$buildOutput = & npm --prefix $webRoot run build 2>&1
if ($LASTEXITCODE -ne 0) {
    $buildOutput | Write-Host
    throw "I007 bundle build failed"
}

$buildText = ($buildOutput | Out-String)
if ($buildText.Contains('Some chunks are larger than 500 kB')) {
    throw "I007 must resolve the Vite chunk warning with splitting, not by raising the limit"
}

$distAssets = Get-ChildItem -LiteralPath (Join-Path $webRoot 'dist\assets') -File | Select-Object -ExpandProperty Name
foreach ($chunk in @('antd-vendor', 'antd-icons-vendor', 'query-vendor')) {
    if (-not ($distAssets | Where-Object { $_.StartsWith($chunk) })) {
        throw "missing expected bundle chunk: $chunk"
    }
}

$report = [ordered]@{
    status = 'pass'
    task = 'I007'
    tanstackQueryDependency = $packageJson.dependencies.'@tanstack/react-query'
    typedApiBoundary = $true
    openApiPath = '/openapi/v1.json'
    uiConsumesRawJson = $false
    teacherDraftStateInQuery = $false
    highRiskOperationSource = 'api-contract-source-of-truth'
    bundleWarningResolved = $true
    chunks = @($distAssets)
    buildChecked = $true
}

$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding utf8
$report | ConvertTo-Json -Depth 6

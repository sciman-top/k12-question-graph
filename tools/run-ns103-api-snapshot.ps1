param(
    [string] $ReportPath = 'docs/evidence/20260528-ns103-api-snapshot.md',
    [string] $ApiProgramPath = 'apps/api/Program.cs',
    [string] $ContractsPath = 'apps/web/src/api/contracts.ts',
    [string] $ClientPath = 'apps/web/src/api/client.ts',
    [string] $Project = 'apps/api/K12QuestionGraph.Api.csproj'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Escape-Cell([string] $Value) {
    return ($Value -replace '\|', '\|' -replace "`r?`n", ' ').Trim()
}

function Format-CodeCell([string] $Value) {
    $escaped = (Escape-Cell $Value) -replace '`', ''
    if ([string]::IsNullOrWhiteSpace($escaped)) {
        return ''
    }

    return "``$escaped``"
}

Push-Location $repoRoot
try {
    foreach ($path in @($ApiProgramPath, $ContractsPath, $ClientPath)) {
        Assert-Condition (Test-Path -LiteralPath $path) "missing API snapshot input: $path"
    }

    $buildOutput = dotnet build $Project 2>&1
    Assert-Condition ($LASTEXITCODE -eq 0) 'dotnet build failed before API snapshot'

    $programLines = @(Get-Content -LiteralPath $ApiProgramPath)
    $programText = $programLines -join "`n"
    $contractsText = Get-Content -LiteralPath $ContractsPath -Raw
    $clientText = Get-Content -LiteralPath $ClientPath -Raw

    $endpoints = @()
    for ($i = 0; $i -lt $programLines.Count; $i++) {
        $line = $programLines[$i]
        if ($line -match 'app\.Map(Get|Post|Put|Delete|Patch)\("([^"]+)"') {
            $method = $Matches[1].ToUpperInvariant()
            $route = $Matches[2]
            $lookahead = ($programLines[$i..([Math]::Min($i + 12, $programLines.Count - 1))] -join "`n")
            $name = ''
            if ($lookahead -match '\.WithName\("([^"]+)"\)') {
                $name = $Matches[1]
            }
            $endpoints += [ordered]@{
                method = $method
                route = $route
                name = $name
                line = $i + 1
            }
        }
    }

    $clientFunctions = @()
    $functionMatches = [regex]::Matches($clientText, 'export\s+async\s+function\s+([A-Za-z0-9_]+)\(([\s\S]*?)\):\s*Promise<ApiResult<([^>]+)>>')
    foreach ($match in $functionMatches) {
        $start = $match.Index
        $next = $clientText.IndexOf('export async function ', $start + 1)
        if ($next -lt 0) { $next = $clientText.Length }
        $body = $clientText.Substring($start, $next - $start)
        $paths = @()
        foreach ($pathMatch in [regex]::Matches($body, '(requestJson|postJson)\((`[^`]+`|''[^'']+''|"[^"]+")')) {
            $paths += ($pathMatch.Groups[2].Value.Trim("`"'"))
        }
        $clientFunctions += [ordered]@{
            function = $match.Groups[1].Value
            contract = $match.Groups[3].Value
            paths = if ($paths.Count -eq 0) { '' } else { ($paths -join ', ') }
        }
    }

    $contractNames = @()
    foreach ($match in [regex]::Matches($contractsText, 'export\s+(interface|type)\s+([A-Za-z0-9_]+)')) {
        $contractNames += [ordered]@{
            kind = $match.Groups[1].Value
            name = $match.Groups[2].Value
        }
    }

    $errorCodes = @([regex]::Matches($programText, 'error\s*=\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $statusLiterals = @([regex]::Matches($programText + "`n" + $contractsText, '"([a-z][a-z0-9_]{2,})"|''([a-z][a-z0-9_]{2,})''') |
        ForEach-Object {
            if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value }
        } |
        Where-Object { $_ -match 'draft|pending|resolved|ready|archived|imported|failed|open|dismissed|production|synthetic|anonymized|invalid|excluded|succeeded|queued|running' } |
        Sort-Object -Unique)

    $requiredRoutes = @(
        '/health/ready',
        '/source-documents',
        '/imports',
        '/imports/{id:guid}',
        '/review-queue',
        '/review-workbench/actions',
        '/questions',
        '/paper-baskets',
        '/score-imports',
        '/paper-requests/parse',
        '/paper-blueprints'
    )
    $missingRequiredRoutes = @($requiredRoutes | Where-Object { $route = $_; -not ($endpoints | Where-Object { $_.route -eq $route }) })
    Assert-Condition ($missingRequiredRoutes.Count -eq 0) "API snapshot missing required teacher workflow routes: $($missingRequiredRoutes -join ', ')"
    Assert-Condition (($contractNames | Where-Object { $_.name -eq 'ApiResult' }).Count -gt 0) 'typed API snapshot missing ApiResult'
    Assert-Condition (($clientFunctions | Where-Object { $_.function -eq 'getReadyHealth' }).Count -gt 0) 'typed API snapshot missing getReadyHealth'
    Assert-Condition ($errorCodes.Count -gt 0) 'API snapshot must capture error codes'

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# NS103 · API contract snapshot')
    $lines.Add('')
    $lines.Add('日期：2026-05-28。')
    $lines.Add('')
    $lines.Add('## Result')
    $lines.Add('')
    $lines.Add('- 状态：`pass`。')
    $lines.Add("- API endpoint count: ``$($endpoints.Count)``。")
    $lines.Add("- typed client function count: ``$($clientFunctions.Count)``。")
    $lines.Add("- typed contract count: ``$($contractNames.Count)``。")
    $lines.Add("- error code count: ``$($errorCodes.Count)``。")
    $lines.Add('- 本快照是静态 typed API snapshot，不宣称 OpenAPI runtime 已验证；后续若拉起 API 服务并抓取 `/openapi/v1.json`，可把 NS103 升级为 `runtime_verified`。')
    $lines.Add('')
    $lines.Add('## API Endpoints')
    $lines.Add('')
    $lines.Add('| Method | Route | Name | Source |')
    $lines.Add('|---|---|---|---|')
    foreach ($endpoint in ($endpoints | Sort-Object route, method)) {
        $lines.Add(('| {0} | {1} | {2} | {3} |' -f $endpoint.method, (Format-CodeCell $endpoint.route), (Format-CodeCell ([string]$endpoint.name)), (Format-CodeCell "${ApiProgramPath}:$($endpoint.line)")))
    }
    $lines.Add('')
    $lines.Add('## Typed Client Functions')
    $lines.Add('')
    $lines.Add('| Function | Contract | Paths |')
    $lines.Add('|---|---|---|')
    foreach ($clientFunction in ($clientFunctions | Sort-Object function)) {
        $lines.Add(('| {0} | {1} | {2} |' -f (Format-CodeCell $clientFunction.function), (Format-CodeCell $clientFunction.contract), (Format-CodeCell ([string]$clientFunction.paths))))
    }
    $lines.Add('')
    $lines.Add('## DTO Contracts')
    $lines.Add('')
    $lines.Add('| Kind | Name |')
    $lines.Add('|---|---|')
    foreach ($contract in ($contractNames | Sort-Object name)) {
        $lines.Add(('| {0} | {1} |' -f (Format-CodeCell $contract.kind), (Format-CodeCell $contract.name)))
    }
    $lines.Add('')
    $lines.Add('## Error Codes')
    $lines.Add('')
    foreach ($code in $errorCodes) {
        $lines.Add(("- ``{0}``" -f $code))
    }
    $lines.Add('')
    $lines.Add('## Status Literals')
    $lines.Add('')
    foreach ($status in $statusLiterals) {
        $lines.Add(("- ``{0}``" -f $status))
    }
    $lines.Add('')
    $lines.Add('## Compatibility Notes')
    $lines.Add('')
    $lines.Add('- 普通教师 UI 继续消费 `apps/web/src/api/contracts.ts` 的 normalized typed contracts，不直接依赖裸 JSON shape。')
    $lines.Add('- `ApiResult<T>` 仍以 `network_error` / `invalid_response` 收口前端错误面，避免页面散落 HTTP 细节。')
    $lines.Add('- 本轮不新增、删除或重命名 API endpoint；只生成快照证据。')
    $lines.Add('- `MapOpenApi()` 仍只在 Development 环境暴露；runtime OpenAPI 抓取留给后续验证。')
    $lines.Add('')
    $lines.Add('## Verification')
    $lines.Add('')
    $lines.Add('```powershell')
    $lines.Add('dotnet build apps/api/K12QuestionGraph.Api.csproj')
    $lines.Add('pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-ns103-api-snapshot.ps1')
    $lines.Add('pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-non-site-implementation-plan-guard.ps1')
    $lines.Add('```')
    $lines.Add('')
    $lines.Add('## Rollback')
    $lines.Add('')
    $lines.Add('```powershell')
    $lines.Add('git restore tools/run-ns103-api-snapshot.ps1 tasks/non-site-implementation-plan.csv')
    $lines.Add('git clean -f -- docs/evidence/20260528-ns103-api-snapshot.md')
    $lines.Add('```')

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $lines | Set-Content -LiteralPath $reportFullPath -Encoding UTF8

    [ordered]@{
        status = 'pass'
        task = 'NS103 API contract snapshot'
        report = $ReportPath
        endpointCount = $endpoints.Count
        typedClientFunctionCount = $clientFunctions.Count
        typedContractCount = $contractNames.Count
        errorCodeCount = $errorCodes.Count
        missingRequiredRoutes = $missingRequiredRoutes
    } | ConvertTo-Json -Depth 5
}
finally {
    Pop-Location
}

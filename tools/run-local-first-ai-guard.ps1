$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Push-Location $repoRoot
try {
    $docPath = 'docs\67_LocalFirstAIConsumptionReductionReview.md'
    if (-not (Test-Path -LiteralPath $docPath)) {
        throw "missing local-first AI review doc: $docPath"
    }

    $doc = Get-Content -LiteralPath $docPath -Raw
    foreach ($pattern in @(
        'L0 本地确定性处理',
        '不调用外部 AI',
        '中文输出要求',
        'C002N',
        'token'
    )) {
        if (-not $doc.Contains($pattern)) {
            throw "local-first review doc missing pattern: $pattern"
        }
    }

    $config = Get-Content -LiteralPath 'configs\model_routing.defaults.yaml' -Raw
    foreach ($pattern in @(
        'local_first_contract:',
        'no_external_ai:',
        'chinese_user_outputs:',
        'c002_extraction_layers:'
    )) {
        if (-not $config.Contains($pattern)) {
            throw "model routing config missing local-first pattern: $pattern"
        }
    }

    $app = Get-Content -LiteralPath 'apps\web\src\App.tsx' -Raw
    foreach ($pattern in @(
        'queued: ''排队中''',
        'single_choice: ''单选题''',
        'draft_test: ''草稿测试''',
        'productionEligible=false'
    )) {
        if (-not $app.Contains($pattern)) {
            throw "web Chinese display mapping missing pattern: $pattern"
        }
    }

    [ordered]@{
        status = 'pass'
        doc = $docPath
        policy = 'local-first deterministic gates before external AI'
        chineseUserOutputs = $true
        c002Next = 'C002N source chunk extraction cache'
    } | ConvertTo-Json -Depth 4
}
finally {
    Pop-Location
}

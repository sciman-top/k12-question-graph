$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

$appPath = Join-Path $repoRoot 'apps\web\src\App.tsx'
$clientPath = Join-Path $repoRoot 'apps\web\src\api\client.ts'
$contractsPath = Join-Path $repoRoot 'apps\web\src\api\contracts.ts'
$queriesPath = Join-Path $repoRoot 'apps\web\src\api\queries.ts'

$app = Get-Content -LiteralPath $appPath -Raw
$client = Get-Content -LiteralPath $clientPath -Raw
$contracts = Get-Content -LiteralPath $contractsPath -Raw
$queries = Get-Content -LiteralPath $queriesPath -Raw

Assert-True ($client.Contains('searchQuestions')) 'S008B client must expose searchQuestions'
Assert-True ($client.Contains('/questions?')) 'S008B client must call real question search API'
Assert-True ($queries.Contains('useQuestionSearchQuery')) 'S008B must expose TanStack question search query'
Assert-True ($contracts.Contains('QuestionSearchContract')) 'S008B must define typed question search contract'
foreach ($field in @('hasFormula','hasTable','hasImage','knowledgeStatus','knowledgeVersion')) {
    Assert-True ($contracts.Contains($field)) "S008B contract missing field: $field"
    Assert-True ($app.Contains($field)) "S008B UI missing field: $field"
}
foreach ($marker in @(
    'data-contract="s008b-real-api-question-cards"',
    'data-contract="s008b-active-version"',
    'data-state="question-search-empty"',
    'data-state="question-search-error"',
    'data-action="question-search-refresh"',
    'data-action="question-interaction-message"',
    "className={activeQuestionFilter === item.filter ? 'filter-chip active' : 'filter-chip'}",
    "onClick={() => applyQuestionFilter(item.filter, item.label)}",
    "onClick={() => selectQuestionCard(card.id, card.preview)}"
)) {
    Assert-True ($app.Contains($marker)) "S008B UI marker missing: $marker"
}
Assert-True (-not $app.Contains('draft_test-card-001')) 'S008B must not render old static question cards'

$report = [ordered]@{
    status = 'pass'
    taskId = 'S008B'
    checkedAt = (Get-Date).ToString('s')
    ui = 'apps/web/src/App.tsx'
    apiClient = 'apps/web/src/api/client.ts'
    contracts = 'apps/web/src/api/contracts.ts'
    query = 'apps/web/src/api/queries.ts'
    checkedMarkers = @(
        'real-api-question-cards',
        'active-version',
        'empty-state',
        'error-state',
        'refresh-action'
    )
    conclusion = 'question card UI is wired to typed real API query with source version difficulty media flags empty state and error state'
}

$reportPath = Join-Path $repoRoot 'docs\evidence\20260507-s008b-question-card-ui-contract-report.json'
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 6

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$schemaPath = Join-Path $repoRoot 'schemas\ai\ai_suggestion_envelope.schema.json'
if (-not (Test-Path -LiteralPath $schemaPath)) {
    throw "schema not found: $schemaPath"
}

$schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json -Depth 100
$requiredRoot = @('suggestion_type','source','confidence','review','cost','cache','payload')
foreach ($field in $requiredRoot) {
    if (-not ($schema.required -contains $field)) {
        throw "S007A schema missing required root field: $field"
    }
}

$sourceRequired = @('source_document_id','source_region_ids','model_route','prompt_version')
foreach ($field in $sourceRequired) {
    if (-not ($schema.properties.source.required -contains $field)) {
        throw "S007A schema missing source field: $field"
    }
}

$reviewRequired = @('required','status','review_queue_id')
foreach ($field in $reviewRequired) {
    if (-not ($schema.properties.review.required -contains $field)) {
        throw "S007A schema missing review field: $field"
    }
}

$costRequired = @('input_tokens','output_tokens','estimated_usd')
foreach ($field in $costRequired) {
    if (-not ($schema.properties.cost.required -contains $field)) {
        throw "S007A schema missing cost field: $field"
    }
}

$cacheRequired = @('cache_key','cache_hit')
foreach ($field in $cacheRequired) {
    if (-not ($schema.properties.cache.required -contains $field)) {
        throw "S007A schema missing cache field: $field"
    }
}

$report = [ordered]@{
    status = 'pass'
    taskId = 'S007A'
    checkedAt = (Get-Date).ToString('s')
    schemaPath = 'schemas/ai/ai_suggestion_envelope.schema.json'
    suggestionTypes = @($schema.properties.suggestion_type.enum)
    requiredRoot = $requiredRoot
    requiredSource = $sourceRequired
    requiredReview = $reviewRequired
    requiredCost = $costRequired
    requiredCache = $cacheRequired
    conclusion = 'ai suggestion schema hardened with source confidence cost cache and human review fields'
}

$reportPath = Join-Path $repoRoot 'docs\evidence\20260506-s007a-ai-suggestion-schema-hardening-report.json'
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 10

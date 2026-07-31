param(
    [string] $TemplatePath = 'configs\knowledge\observed-exam-evidence-template.json',
    [string] $ReportPath = 'docs\evidence\cek017-observed-exam-evidence-contract.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Test-Schema([object] $Value, [string] $SchemaPath) {
    return (($Value | ConvertTo-Json -Depth 40) | Test-Json -SchemaFile $SchemaPath -ErrorAction SilentlyContinue)
}

function Write-Json([object] $Value, [string] $Path) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 30) + "`n"), [Text.UTF8Encoding]::new($false))
}

Push-Location $repoRoot
try {
    $template = Get-Content -Raw $TemplatePath | ConvertFrom-Json
    $performanceSchema = 'schemas\observed_performance_evidence.schema.json'
    $errorSchema = 'schemas\observed_error_evidence.schema.json'
    $recommendationSchema = 'schemas\teaching_recommendation.schema.json'

    Assert-True ($template.schema_version -eq 'observed-exam-evidence-package.v1') 'CEK-17 template version mismatch'
    Assert-True (@($template.observed_performance).Count -ge 1) 'CEK-17 performance fixture missing'
    Assert-True (@($template.observed_errors).Count -ge 1) 'CEK-17 error fixture missing'
    Assert-True (@($template.teaching_recommendations).Count -ge 1) 'CEK-17 recommendation fixture missing'

    foreach ($row in @($template.observed_performance)) {
        Assert-True (Test-Schema $row $performanceSchema) 'CEK-17 positive performance fixture failed schema validation'
    }
    foreach ($row in @($template.observed_errors)) {
        Assert-True (Test-Schema $row $errorSchema) 'CEK-17 positive error fixture failed schema validation'
    }
    foreach ($row in @($template.teaching_recommendations)) {
        Assert-True (Test-Schema $row $recommendationSchema) 'CEK-17 positive recommendation fixture failed schema validation'
    }

    $invalidDifficulty = $template.observed_performance[0] | ConvertTo-Json -Depth 40 | ConvertFrom-Json
    $invalidDifficulty.difficulty_observed.scale_direction = 'higher_is_harder'
    Assert-True (-not (Test-Schema $invalidDifficulty $performanceSchema)) 'CEK-17 accepted higher-is-harder observed difficulty'

    $invalidError = $template.observed_errors[0] | ConvertTo-Json -Depth 40 | ConvertFrom-Json
    $invalidError.generation_method = 'ai'
    Assert-True (-not (Test-Schema $invalidError $errorSchema)) 'CEK-17 accepted AI-generated verbatim observation'

    $invalidRecommendation = $template.teaching_recommendations[0] | ConvertTo-Json -Depth 40 | ConvertFrom-Json
    $invalidRecommendation.production_eligible = $true
    Assert-True (-not (Test-Schema $invalidRecommendation $recommendationSchema)) 'CEK-17 accepted production-eligible recommendation candidate'

    Assert-True ($template.governance.database_write -eq $false) 'CEK-17 template permits database writes'
    Assert-True ($template.governance.active_write -eq $false) 'CEK-17 template permits active writes'
    Assert-True ($template.governance.external_model_calls -eq 0) 'CEK-17 template records external model calls'

    $report = [ordered]@{
        schemaVersion = 'cek017-observed-exam-evidence-contract.v1'
        status = 'pass'
        checkedAt = [DateTimeOffset]::UtcNow.ToString('o')
        taskId = 'CEK-17'
        contracts = [ordered]@{
            observedPerformance = $performanceSchema
            observedError = $errorSchema
            teachingRecommendation = $recommendationSchema
        }
        positiveFixtures = 3
        negativeFixturesRejected = 3
        invariants = [ordered]@{
            missingValuesRemainNull = $true
            observedDifficultyDirection = 'higher_is_easier'
            estimatedDifficultyExcluded = $true
            evidenceKindsSeparated = $true
            candidateOnly = $true
            databaseWrite = $false
            activeWrite = $false
            externalModelCalls = 0
        }
        rollback = 'remove the three CEK-17 schemas, template, contract runner, and generated evidence report'
        completionBoundary = 'CEK-17 defines candidate evidence contracts only; it does not extract report facts, persist data, approve candidates, or change active assets.'
    }
    Write-Json $report $ReportPath
    $report | ConvertTo-Json -Depth 20
}
finally {
    Pop-Location
}

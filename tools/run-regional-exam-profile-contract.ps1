param(
    [string] $SchemaPath = 'schemas\regional_exam_point_profile.schema.json',
    [string] $ProfileTemplatePath = 'configs\knowledge\regional-exam-profile-template.json',
    [string] $LegacyCsvPath = 'configs\knowledge\c002-exam-point-template.csv',
    [string] $ReportPath = 'docs\evidence\cek021-regional-exam-profile-contract.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Resolve-RepoPath([string] $Path) {
    return (Resolve-Path -LiteralPath (Join-Path $repoRoot $Path)).Path
}

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Copy-Json([object] $Value) {
    return ($Value | ConvertTo-Json -Depth 50 | ConvertFrom-Json)
}

function Test-Profile([object] $Value, [string] $Schema) {
    return (($Value | ConvertTo-Json -Depth 50) | Test-Json -SchemaFile $Schema -ErrorAction SilentlyContinue)
}

function Assert-MetricEvidence([object] $Metric, [string] $Label, [int[]] $ComparableYears) {
    Assert-True (@($Metric.comparable_exam_years).Count -gt 0) "$Label comparable years are required"
    Assert-True (@($Metric.evidence_target_ids).Count -gt 0) "$Label evidence target IDs are required"
    Assert-True (@(Compare-Object @($Metric.comparable_exam_years) $ComparableYears).Count -eq 0) "$Label comparable years drift from profile year range"
}

$resolvedSchemaPath = Resolve-RepoPath $SchemaPath
$resolvedProfileTemplatePath = Resolve-RepoPath $ProfileTemplatePath
$resolvedLegacyCsvPath = Resolve-RepoPath $LegacyCsvPath
$resolvedReportPath = Join-Path $repoRoot $ReportPath
$profile = Get-Content -Raw -LiteralPath $resolvedProfileTemplatePath | ConvertFrom-Json

Assert-True (Test-Profile $profile $resolvedSchemaPath) 'CEK-21 positive profile template failed schema validation'
Assert-True ($profile.semantic_type -eq 'RegionalExamPointProfile') 'CEK-21 canonical semantic type mismatch'
Assert-True ($profile.storage_asset_type -eq 'exam_point') 'CEK-21 storage asset type must remain exam_point'
Assert-True ($profile.status -eq 'candidate') 'CEK-21 template must stay candidate'
Assert-True ($profile.review_status -eq 'pending_review') 'CEK-21 template must stay pending_review'
Assert-True ($profile.production_eligible -eq $false) 'CEK-21 template must not be production eligible'

$comparableYears = @($profile.year_range.comparable_exam_years | ForEach-Object { [int]$_ })
Assert-True ($comparableYears.Count -gt 0) 'CEK-21 comparable exam years are required'
Assert-True ($profile.year_range.start_year -le $comparableYears[0]) 'CEK-21 start year exceeds comparable range'
Assert-True ($profile.year_range.end_year -ge $comparableYears[-1]) 'CEK-21 end year precedes comparable range'
Assert-MetricEvidence $profile.frequency_weight 'frequency_weight' $comparableYears
Assert-MetricEvidence $profile.score_weight 'score_weight' $comparableYears
Assert-MetricEvidence $profile.difficulty_distribution 'difficulty_distribution' $comparableYears
Assert-MetricEvidence $profile.trend 'trend' $comparableYears
Assert-True ($profile.frequency_weight.denominator_comparable_exam_papers -gt 0) 'frequency denominator must be positive'
Assert-True ($profile.score_weight.denominator_total_exam_score -gt 0) 'score denominator must be positive'
Assert-True ($profile.difficulty_distribution.denominator_observed_items -gt 0) 'difficulty denominator must be positive'
Assert-True ($profile.trend.minimum_comparable_years -eq 3) 'trend minimum comparable years must stay at three'
if ($comparableYears.Count -lt 3) {
    Assert-True ($profile.trend.status -eq 'insufficient_evidence') 'fewer than three comparable years must be insufficient_evidence'
}

$negativeCases = [ordered]@{}
$missingDenominator = Copy-Json $profile
$missingDenominator.frequency_weight.PSObject.Properties.Remove('denominator_comparable_exam_papers')
$negativeCases.missingFrequencyDenominator = -not (Test-Profile $missingDenominator $resolvedSchemaPath)

$prematureTrend = Copy-Json $profile
$prematureTrend.year_range.comparable_exam_years = @(2023, 2024)
$prematureTrend.trend.comparable_exam_years = @(2023, 2024)
$prematureTrend.frequency_weight.comparable_exam_years = @(2023, 2024)
$prematureTrend.score_weight.comparable_exam_years = @(2023, 2024)
$prematureTrend.difficulty_distribution.comparable_exam_years = @(2023, 2024)
$prematureTrend.trend.status = 'rising'
$negativeCases.prematureTrend = -not (Test-Profile $prematureTrend $resolvedSchemaPath)

$sparseTrendWithinWiderProfile = Copy-Json $profile
$sparseTrendWithinWiderProfile.year_range.start_year = 2022
$sparseTrendWithinWiderProfile.year_range.end_year = 2024
$sparseTrendWithinWiderProfile.year_range.comparable_exam_years = @(2022, 2023, 2024)
$sparseTrendWithinWiderProfile.trend.comparable_exam_years = @(2024)
$sparseTrendWithinWiderProfile.trend.status = 'rising'
$negativeCases.sparseTrendWithinWiderProfile = -not (Test-Profile $sparseTrendWithinWiderProfile $resolvedSchemaPath)

$wrongStorageType = Copy-Json $profile
$wrongStorageType.storage_asset_type = 'regional_exam_point_profile'
$negativeCases.wrongStorageType = -not (Test-Profile $wrongStorageType $resolvedSchemaPath)

$candidateProductionWrite = Copy-Json $profile
$candidateProductionWrite.production_eligible = $true
$negativeCases.candidateProductionWrite = -not (Test-Profile $candidateProductionWrite $resolvedSchemaPath)

foreach ($case in $negativeCases.GetEnumerator()) {
    Assert-True ([bool]$case.Value) "CEK-21 negative case unexpectedly passed: $($case.Key)"
}

$threeYearTrend = Copy-Json $profile
$threeYearTrend.year_range.start_year = 2022
$threeYearTrend.year_range.end_year = 2024
$threeYearTrend.year_range.comparable_exam_years = @(2022, 2023, 2024)
foreach ($metricName in @('frequency_weight','score_weight','difficulty_distribution','trend')) {
    $threeYearTrend.$metricName.comparable_exam_years = @(2022, 2023, 2024)
}
$threeYearTrend.trend.status = 'stable'
Assert-True (Test-Profile $threeYearTrend $resolvedSchemaPath) 'CEK-21 three-year trend fixture must allow reviewed trend candidates'

$legacyColumns = @(
    'stable_id','parent_stable_id','title','subject','stage','region','year_range','exam_scope',
    'source_material_ids','evidence_locations','common_question_types','knowledge_stable_ids',
    'ability_dimensions','difficulty_band','frequency_weight','trend_status','review_status',
    'production_eligible','notes'
)
$requiredProfileColumns = @(
    'semantic_type','profile_schema_version','comparable_exam_years','frequency_numerator',
    'frequency_denominator','score_numerator','score_denominator','difficulty_observed_denominator',
    'evidence_target_ids','profile_template_path'
)
$headerColumns = @((Get-Content -LiteralPath $resolvedLegacyCsvPath -TotalCount 1).Split(','))
Assert-True ($headerColumns.Count -ge ($legacyColumns.Count + $requiredProfileColumns.Count)) 'CEK-21 CSV profile columns are incomplete'
Assert-True (@(Compare-Object $headerColumns[0..($legacyColumns.Count - 1)] $legacyColumns -SyncWindow 0).Count -eq 0) 'CEK-21 changed the legacy CSV column prefix'
foreach ($column in $requiredProfileColumns) {
    Assert-True ($headerColumns -contains $column) "CEK-21 CSV missing appended profile column: $column"
}

$csvRows = @(Import-Csv -LiteralPath $resolvedLegacyCsvPath -Encoding UTF8)
Assert-True ($csvRows.Count -gt 0) 'CEK-21 compatibility CSV requires sample rows'
foreach ($row in $csvRows) {
    Assert-True (-not [string]::IsNullOrWhiteSpace($row.stable_id)) 'legacy stable_id must remain populated'
    Assert-True (-not [string]::IsNullOrWhiteSpace($row.title)) 'legacy title must remain populated'
    Assert-True ($row.semantic_type -eq 'RegionalExamPointProfile') "CSV semantic type mismatch: $($row.stable_id)"
    Assert-True ($row.profile_schema_version -eq 'regional-exam-point-profile.v1') "CSV schema version mismatch: $($row.stable_id)"
    Assert-True ($row.review_status -eq 'pending_review') "CSV review status mismatch: $($row.stable_id)"
    Assert-True ($row.production_eligible -eq 'false') "CSV production eligibility mismatch: $($row.stable_id)"
    $years = @(([string]$row.comparable_exam_years).Split(';', [StringSplitOptions]::RemoveEmptyEntries))
    Assert-True ($years.Count -gt 0) "CSV comparable years missing: $($row.stable_id)"
    if ($years.Count -lt 3) {
        Assert-True ($row.trend_status -eq 'insufficient_evidence') "CSV premature trend: $($row.stable_id)"
    }
    $frequencyDenominator = [decimal]$row.frequency_denominator
    $scoreDenominator = [decimal]$row.score_denominator
    Assert-True ($frequencyDenominator -gt 0) "CSV frequency denominator invalid: $($row.stable_id)"
    Assert-True ($scoreDenominator -gt 0) "CSV score denominator invalid: $($row.stable_id)"
    Assert-True ([int]$row.difficulty_observed_denominator -gt 0) "CSV difficulty denominator invalid: $($row.stable_id)"
    Assert-True (-not [string]::IsNullOrWhiteSpace($row.evidence_target_ids)) "CSV evidence targets missing: $($row.stable_id)"
    $expectedFrequency = [Math]::Round(([decimal]$row.frequency_numerator / $frequencyDenominator), 4)
    Assert-True ([Math]::Abs(([decimal]$row.frequency_weight - $expectedFrequency)) -le 0.0001) "CSV frequency value does not match numerator/denominator: $($row.stable_id)"
}

$legacyProjection = @($csvRows | ForEach-Object {
    $projected = [ordered]@{}
    foreach ($column in $legacyColumns) { $projected[$column] = [string]$_.$column }
    [pscustomobject]$projected
})
Assert-True ($legacyProjection.Count -eq $csvRows.Count) 'CEK-21 legacy CSV projection lost rows'

$report = [ordered]@{
    schemaVersion = 'cek021-regional-exam-profile-contract.v1'
    status = 'pass'
    checkedAt = (Get-Date).ToUniversalTime().ToString('o')
    taskId = 'CEK-21'
    semanticType = 'RegionalExamPointProfile'
    storageAssetType = 'exam_point'
    schemaValidated = $true
    negativeCases = $negativeCases
    trend = [ordered]@{
        minimumComparableYears = 3
        singleYearStatus = [string]$profile.trend.status
        threeYearCandidateAccepted = $true
    }
    metricEvidence = [ordered]@{
        frequencyHasDenominator = $true
        scoreHasDenominator = $true
        difficultyHasDenominator = $true
        allMetricsHaveComparableYears = $true
        allMetricsHaveEvidenceTargetIds = $true
    }
    compatibility = [ordered]@{
        csvRows = $csvRows.Count
        legacyColumnCount = $legacyColumns.Count
        legacyPrefixPreserved = $true
        appendedProfileColumnCount = $requiredProfileColumns.Count
        legacyProjectionParsed = $true
    }
    governance = [ordered]@{
        status = 'candidate'
        reviewStatus = 'pending_review'
        productionEligible = $false
        databaseWrite = $false
        activeWrite = $false
    }
    referencesReviewed = @(
        'QUESTION_BANK_DOMAIN_ASSET_GOVERNANCE module route',
        'official-docs/EntityFramework.Docs read-only metadata boundary',
        'official-docs/npgsql-doc JSONB metadata boundary',
        'education-assessment lifecycle references from CEK-20'
    )
    adoptionDecision = 'Preserve exam_point storage/API compatibility and add a schema-governed RegionalExamPointProfile semantic layer; do not copy LMS models or infer trends from sparse years.'
    evidence = [ordered]@{
        schema = [IO.Path]::GetRelativePath($repoRoot, $resolvedSchemaPath).Replace('\', '/')
        template = [IO.Path]::GetRelativePath($repoRoot, $resolvedProfileTemplatePath).Replace('\', '/')
        csv = [IO.Path]::GetRelativePath($repoRoot, $resolvedLegacyCsvPath).Replace('\', '/')
        report = $ReportPath.Replace('\', '/')
    }
    rollback = 'Revert only the CEK-21 schema/template/CSV appended fields and guard; no database or active asset state is written.'
    completionBoundary = 'CEK-21 proves the RegionalExamPointProfile contract and legacy exam_point CSV compatibility only; no regional profile is aggregated, persisted, teacher-approved, production eligible, or active.'
}

New-Item -ItemType Directory -Path (Split-Path -Parent $resolvedReportPath) -Force | Out-Null
[IO.File]::WriteAllText($resolvedReportPath, (($report | ConvertTo-Json -Depth 12) + "`n"), [Text.UTF8Encoding]::new($false))
$report | ConvertTo-Json -Depth 12

param(
    [string] $ApiBaseUrl = 'http://127.0.0.1:5275',
    [string] $SourceRoot = 'D:\KQG_Data\source_materials\imported\guangzhou_physics_2015_2025\20260726-v2\raw',
    [string] $ConfigPath = 'configs\knowledge\guangzhou-profile-comparability.json',
    [string] $SchemaPath = 'schemas\regional_exam_point_profile.schema.json',
    [string] $ReportPath = 'docs\evidence\cek022-regional-exam-profile-aggregation.json',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabaseUser = 'postgres',
    [string] $DatabasePassword = $env:PGPASSWORD
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$psql = 'C:\Program Files\PostgreSQL\17\bin\psql.exe'

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Get-DatabaseFingerprint {
    $sql = @"
select json_build_object(
  'activeAssets', (select count(*) from domain_asset_versions where status='active'),
  'questionCount', (select count(*) from question_items where custom_fields->>'sourceWorkflowKey'='guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1'),
  'questionFingerprint', (
    select md5(string_agg(concat_ws('|',id::text,coalesce(difficulty_estimated::text,''),coalesce(difficulty_observed::text,''),status,coalesce(primary_knowledge_id::text,''),coalesce(custom_fields->>'productionEligible','')), E'\n' order by id))
    from question_items where custom_fields->>'sourceWorkflowKey'='guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1'
  )
);
"@
    $value = (& $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c $sql) | ConvertFrom-Json
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-22 database fingerprint query failed'
    return $value
}

. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword $DatabasePassword
Assert-True (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'database password required'
Assert-True (Test-Path -LiteralPath $psql -PathType Leaf) 'psql missing'
$env:PGPASSWORD = $DatabasePassword

Push-Location $repoRoot
try {
    $ready = Invoke-RestMethod -Uri "$ApiBaseUrl/health/ready" -TimeoutSec 10
    Assert-True ($ready.status -eq 'ok') 'CEK-22 API is not ready'

    $config = Get-Content -Raw $ConfigPath | ConvertFrom-Json
    $verifiedPaperHashes = [ordered]@{}
    foreach ($paper in @($config.papers)) {
        $paperName = if ([int]$paper.year -eq 2020) { '2020广州中考（含答案）.pdf' } else { "$($paper.year)广州中考.pdf" }
        $paperPath = Join-Path $SourceRoot $paperName
        Assert-True (Test-Path -LiteralPath $paperPath -PathType Leaf) "CEK-22 paper evidence missing: $paperName"
        $actualHash = (Get-FileHash -LiteralPath $paperPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-True ($actualHash -eq $paper.sha256) "CEK-22 paper hash mismatch: $paperName"
        $verifiedPaperHashes[[string]$paper.year] = $actualHash
    }

    python -m unittest tests.workers.test_regional_exam_profile_aggregation
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-22 unit tests failed'
    python -m py_compile tools\regional_exam_profile_aggregation.py tests\workers\test_regional_exam_profile_aggregation.py
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-22 Python compile failed'

    $before = Get-DatabaseFingerprint
    python tools\regional_exam_profile_aggregation.py `
        --config $ConfigPath --api-base-url $ApiBaseUrl --report $ReportPath | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-22 live aggregation failed'
    $after = Get-DatabaseFingerprint

    Assert-True ($before.activeAssets -eq $after.activeAssets) 'CEK-22 changed active asset count'
    Assert-True ($before.questionCount -eq $after.questionCount) 'CEK-22 changed question count'
    Assert-True ($before.questionFingerprint -eq $after.questionFingerprint) 'CEK-22 changed legacy question fields'

    $report = Get-Content -Raw $ReportPath | ConvertFrom-Json
    Assert-True ($report.status -eq 'pass') 'CEK-22 report did not pass'
    Assert-True ($report.input.assessmentTargetsReturned -eq 444) 'CEK-22 target count mismatch'
    Assert-True ($report.input.questionsReturned -eq 234) 'CEK-22 question count mismatch'
    Assert-True ($report.input.acceptedQuestions -eq 234) 'CEK-22 accepted question count mismatch'
    Assert-True ($report.input.corpusComplete) 'CEK-22 yearly question corpus is incomplete'
    Assert-True ($report.input.observedPerformanceReturned -eq 157) 'CEK-22 observed performance count mismatch'
    Assert-True ($report.aggregation.profileCandidates -gt 0) 'CEK-22 produced no profiles'
    Assert-True ($report.aggregation.fullWindowProfiles -gt 0) 'CEK-22 full-window profiles missing'
    Assert-True ($report.aggregation.recentComparableProfiles -gt 0) 'CEK-22 recent profiles missing'
    Assert-True ($report.aggregation.crossStateMixes -eq 0) 'CEK-22 mixed source states'
    Assert-True ($report.aggregation.traceablePaperAnswerReportProfiles -eq $report.aggregation.profileCandidates) 'CEK-22 profile traceability incomplete'
    Assert-True (($report.windows.recentComparable -join ',') -eq '2021,2022,2023,2024') 'CEK-22 recent comparable cohort mismatch'
    Assert-True (-not $report.windows.recentComparableComplete) 'CEK-22 hid the incomplete five-year comparable window'
    Assert-True ($report.scoreRegimes.'2015'.totalScore -eq 100) 'CEK-22 2015 score regime mismatch'
    Assert-True ($report.scoreRegimes.'2025'.totalScore -eq 90) 'CEK-22 2025 score regime mismatch'
    Assert-True (-not $report.governance.databaseWrite) 'CEK-22 database write guard failed'
    Assert-True (-not $report.governance.activeWrite) 'CEK-22 active write guard failed'
    Assert-True (-not $report.governance.productionEligible) 'CEK-22 production eligibility guard failed'

    foreach ($item in @($report.profiles)) {
        $valid = (($item.profile | ConvertTo-Json -Depth 40) | Test-Json -SchemaFile $SchemaPath -ErrorAction SilentlyContinue)
        Assert-True $valid "CEK-22 profile schema failed: $($item.profile.stable_id)"
        Assert-True ($item.profile.status -eq 'candidate') "CEK-22 non-candidate profile: $($item.profile.stable_id)"
        Assert-True ($item.profile.review_status -eq 'pending_review') "CEK-22 review guard failed: $($item.profile.stable_id)"
        Assert-True (-not $item.profile.production_eligible) "CEK-22 production profile leaked: $($item.profile.stable_id)"
    }

    $report | Add-Member -NotePropertyName runtimeVerification -NotePropertyValue ([ordered]@{
        apiReady = $true
        verifiedPaperHashes = $verifiedPaperHashes
        activeAssetCountBefore = $before.activeAssets
        activeAssetCountAfter = $after.activeAssets
        questionFingerprintBefore = $before.questionFingerprint
        questionFingerprintAfter = $after.questionFingerprint
        databaseUnchanged = $true
    })
    [IO.File]::WriteAllText(
        (Join-Path $repoRoot $ReportPath),
        (($report | ConvertTo-Json -Depth 50) + "`n"),
        [Text.UTF8Encoding]::new($false)
    )

    $report | ConvertTo-Json -Depth 10
}
finally {
    Pop-Location
}

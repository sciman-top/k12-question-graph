param(
    [Parameter(Mandatory)] [string] $BackupManifest,
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabaseUser = 'postgres',
    [string] $DatabasePassword = $env:PGPASSWORD,
    [int] $ApiPort = 5288,
    [string] $ReportPath = 'docs\evidence\cek023-regional-exam-profile-query-smoke.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$psql = 'C:\Program Files\PostgreSQL\17\bin\psql.exe'
$packagePath = 'docs\evidence\cek022-regional-exam-profile-aggregation.json'
$importKey = 'cek023_regional_exam_profile_candidate_v1'
$workflowKey = 'guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1'

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Write-Json([object] $Value, [string] $Path) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 50) + "`n"), [Text.UTF8Encoding]::new($false))
}

function Invoke-PsqlJson([string] $Sql) {
    $raw = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c $Sql
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-23 database query failed'
    $jsonLine = @($raw | Where-Object { $_ -match '^\s*\{' } | Select-Object -Last 1)
    Assert-True ($jsonLine.Count -eq 1) 'CEK-23 database query did not return one JSON object'
    return ($jsonLine[0] | ConvertFrom-Json)
}

function Get-DatabaseState {
    $sql = @"
with legacy_exam_point as (
  select value as stable_id
  from question_items q
  cross join lateral jsonb_array_elements_text(coalesce(q.custom_fields->'examPointCandidateIds','[]'::jsonb)) value
  order by value
  limit 1
)
select json_build_object(
  'profileAssets', (select count(*) from domain_asset_versions where source_evidence->>'importKey'='$importKey'),
  'profileMigrations', (select count(*) from domain_asset_migrations where migration_key='$importKey'),
  'profileReviewItems', (select count(*) from review_queue_items where review_type='regional_exam_profile' and payload->>'importKey'='$importKey'),
  'nonCandidateProfiles', (select count(*) from domain_asset_versions where source_evidence->>'importKey'='$importKey' and (
      asset_type<>'exam_point' or status<>'candidate' or metadata->>'semantic_type'<>'RegionalExamPointProfile'
      or metadata->>'storage_asset_type'<>'exam_point' or metadata->>'review_status'<>'pending_review'
      or coalesce((metadata->>'production_eligible')::boolean,true)
  )),
  'profileFingerprint', (
    select md5(string_agg(concat_ws('|',id::text,stable_id,version::text,status,
      effective_scope::text,source_evidence::text,metadata::text), E'\n' order by stable_id,version))
    from domain_asset_versions where source_evidence->>'importKey'='$importKey'
  ),
  'profileStableId', (select min(stable_id) from domain_asset_versions where source_evidence->>'importKey'='$importKey'),
  'activeAssets', (select count(*) from domain_asset_versions where status='active'),
  'activeAssetFingerprint', (
    select md5(string_agg(concat_ws('|',id::text,asset_type,stable_id,version::text,display_name,status,
      authority,effective_scope::text,source_evidence::text,metadata::text), E'\n' order by id))
    from domain_asset_versions where status='active'
  ),
  'questionCount', (select count(*) from question_items where custom_fields->>'sourceWorkflowKey'='$workflowKey'),
  'questionFingerprint', (
    select md5(string_agg(to_jsonb(q)::text, E'\n' order by id))
    from question_items q where q.custom_fields->>'sourceWorkflowKey'='$workflowKey'
  ),
  'legacyExamPointCandidateId', (select stable_id from legacy_exam_point),
  'legacyExpectedCount', (
    select count(*) from question_items
    where custom_fields->'examPointCandidateIds' ? (select stable_id from legacy_exam_point)
  )
);
"@
    return Invoke-PsqlJson $sql
}

function Test-RollbackCriteria {
    $sql = @"
begin;
delete from review_queue_items where review_type='regional_exam_profile' and payload->>'importKey'='$importKey';
delete from domain_asset_migrations where migration_key='$importKey';
delete from domain_asset_versions where status='candidate' and source_evidence->>'importKey'='$importKey';
select json_build_object(
  'profileAssets', (select count(*) from domain_asset_versions where source_evidence->>'importKey'='$importKey'),
  'profileMigrations', (select count(*) from domain_asset_migrations where migration_key='$importKey'),
  'profileReviewItems', (select count(*) from review_queue_items where review_type='regional_exam_profile' and payload->>'importKey'='$importKey')
);
rollback;
"@
    return Invoke-PsqlJson $sql
}

. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword $DatabasePassword
Assert-True (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'database password required'
Assert-True (Test-Path -LiteralPath $BackupManifest -PathType Leaf) 'backup manifest missing'
Assert-True (Test-Path -LiteralPath $psql -PathType Leaf) 'psql missing'
$existingListener = Get-NetTCPConnection -State Listen -LocalPort $ApiPort -ErrorAction SilentlyContinue
Assert-True ($null -eq $existingListener) "CEK-23 API port already in use: $ApiPort"

$env:PGPASSWORD = $DatabasePassword
$connection = "host=$DatabaseHost port=$DatabasePort dbname=$DatabaseName user=$DatabaseUser"
$report = [IO.Path]::GetFullPath((Join-Path $repoRoot $ReportPath))
$tmpRoot = Join-Path $repoRoot 'tmp\cek023'
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
$apiProcess = $null
$oldConnection = $env:ConnectionStrings__KqgDatabase
$oldEnvironment = $env:ASPNETCORE_ENVIRONMENT

Push-Location $repoRoot
try {
    $backup = pwsh -NoProfile -ExecutionPolicy Bypass -File tools\verify-backup.ps1 -ManifestPath $BackupManifest | ConvertFrom-Json
    Assert-True ($backup.status -eq 'ok') 'backup verification failed'

    python -m unittest tests.workers.test_regional_exam_profile_aggregation tests.workers.test_regional_exam_profile_import
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-23 Python tests failed'
    dotnet build apps/api/K12QuestionGraph.Api.csproj --no-restore | Write-Host
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-23 API build failed'
    dotnet test tests/api/K12QuestionGraph.Api.Tests/K12QuestionGraph.Api.Tests.csproj --filter FullyQualifiedName~RegionalExamProfileQueryTests --no-restore | Write-Host
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-23 API tests failed'

    $before = Get-DatabaseState
    python tools\import_c002_candidate_assets.py --regional-profile-package $packagePath `
        --connection-string $connection --report-path (Join-Path $tmpRoot 'import-dry-run.json') | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-23 dry-run import failed'
    $afterDryRun = Get-DatabaseState
    Assert-True (($afterDryRun | ConvertTo-Json -Compress) -eq ($before | ConvertTo-Json -Compress)) 'CEK-23 dry-run changed database state'

    foreach ($suffix in @('first', 'second')) {
        python tools\import_c002_candidate_assets.py --regional-profile-package $packagePath `
            --connection-string $connection --backup-manifest $BackupManifest --apply `
            --report-path (Join-Path $tmpRoot "import-$suffix.json") | Out-Null
        Assert-True ($LASTEXITCODE -eq 0) "CEK-23 profile import failed: $suffix"
    }
    $after = Get-DatabaseState
    Assert-True ($after.profileAssets -eq 24) 'CEK-23 profile asset count mismatch'
    Assert-True ($after.profileMigrations -eq 1) 'CEK-23 migration count mismatch'
    Assert-True ($after.profileReviewItems -eq 1) 'CEK-23 review item count mismatch'
    Assert-True ($after.nonCandidateProfiles -eq 0) 'CEK-23 candidate safety guard failed'
    Assert-True ($after.activeAssets -eq $before.activeAssets) 'CEK-23 active asset count changed'
    Assert-True ($after.activeAssetFingerprint -eq $before.activeAssetFingerprint) 'CEK-23 active asset content changed'
    Assert-True ($after.questionCount -eq 234) 'CEK-23 question corpus count changed'
    Assert-True ($after.questionFingerprint -eq $before.questionFingerprint) 'CEK-23 historical question fields changed'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$after.legacyExamPointCandidateId)) 'CEK-23 legacy exam point fixture missing'

    $env:ConnectionStrings__KqgDatabase = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
    $env:ASPNETCORE_ENVIRONMENT = 'Development'
    $outLog = Join-Path $tmpRoot 'api.out.log'
    $errLog = Join-Path $tmpRoot 'api.err.log'
    $apiProcess = Start-Process -FilePath 'dotnet' -ArgumentList @(
        'run', '--no-build', '--configuration', 'Debug',
        '--project', 'apps/api/K12QuestionGraph.Api.csproj', '--urls', "http://127.0.0.1:$ApiPort"
    ) -PassThru -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog
    $ready = $false
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        if ($apiProcess.HasExited) { break }
        try {
            $probe = Invoke-RestMethod -Uri "http://127.0.0.1:$ApiPort/health/ready" -TimeoutSec 2
            if ($probe.status -eq 'ok') { $ready = $true; break }
        } catch { Start-Sleep -Milliseconds 250 }
    }
    Assert-True $ready 'CEK-23 API did not become ready'

    $profileId = [uri]::EscapeDataString([string]$after.profileStableId)
    $detail = Invoke-RestMethod -Uri "http://127.0.0.1:$ApiPort/knowledge-evidence/regional-exam-profiles/$profileId" -TimeoutSec 20
    Assert-True ($detail.status -eq 'candidate') 'CEK-23 detail status mismatch'
    Assert-True ($detail.reviewStatus -eq 'pending_review') 'CEK-23 detail review status mismatch'
    Assert-True (-not $detail.productionEligible) 'CEK-23 detail production guard failed'
    Assert-True ($detail.importKey -eq $importKey) 'CEK-23 detail import key mismatch'
    Assert-True ($detail.profile.year_range.comparable_exam_years.Count -gt 0) 'CEK-23 detail year window missing'
    Assert-True ($detail.profile.frequency_weight.denominator_comparable_exam_papers -gt 0) 'CEK-23 frequency denominator missing'
    Assert-True ($detail.profile.score_weight.denominator_total_exam_score -gt 0) 'CEK-23 score denominator missing'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$detail.profile.standard_regime.regime_id)) 'CEK-23 standard regime missing'
    Assert-True ($detail.evidenceTargetIds.Count -gt 0) 'CEK-23 evidence targets missing'

    $legacyId = [uri]::EscapeDataString([string]$after.legacyExamPointCandidateId)
    $legacy = Invoke-RestMethod -Uri "http://127.0.0.1:$ApiPort/questions?examPointCandidateId=$legacyId&limit=50" -TimeoutSec 20
    Assert-True ($legacy.total -eq $after.legacyExpectedCount) 'CEK-23 legacy examPointCandidateId query regressed'

    $rollbackInsideTransaction = Test-RollbackCriteria
    Assert-True ($rollbackInsideTransaction.profileAssets -eq 0) 'CEK-23 rollback did not target profile assets'
    Assert-True ($rollbackInsideTransaction.profileMigrations -eq 0) 'CEK-23 rollback did not target migration'
    Assert-True ($rollbackInsideTransaction.profileReviewItems -eq 0) 'CEK-23 rollback did not target review item'
    $afterRollbackProbe = Get-DatabaseState
    Assert-True ($afterRollbackProbe.profileAssets -eq 24) 'CEK-23 rollback proof transaction was not rolled back'

    $first = Get-Content -Raw (Join-Path $tmpRoot 'import-first.json') | ConvertFrom-Json
    $second = Get-Content -Raw (Join-Path $tmpRoot 'import-second.json') | ConvertFrom-Json
    Assert-True ($first.packageSha256 -eq $second.packageSha256) 'CEK-23 package hash changed between applies'
    Assert-True ($first.after.profileFingerprint -eq $second.after.profileFingerprint) 'CEK-23 profile content changed between applies'
    $evidence = [ordered]@{
        schemaVersion = 'cek023-regional-exam-profile-query-smoke.v1'
        status = 'pass'
        checkedAt = [DateTimeOffset]::UtcNow.ToString('o')
        taskId = 'CEK-23'
        backup = [ordered]@{ manifest = $BackupManifest; verified = $true }
        import = [ordered]@{
            dryRunNoWrite = $true
            first = $first.status
            second = $second.status
            idempotent = $true
            packageSha256 = $second.packageSha256
            profileFingerprint = $second.after.profileFingerprint
            counts = $after
        }
        api = [ordered]@{
            ready = $true
            profileStableId = $after.profileStableId
            detailFieldsVerified = @('year_range','frequency_weight','score_weight','difficulty_distribution','standard_regime','evidenceTargetIds')
            legacyExamPointCandidateId = $after.legacyExamPointCandidateId
            legacyQueryCount = $legacy.total
        }
        compatibility = [ordered]@{
            activeAssetCountBefore = $before.activeAssets
            activeAssetCountAfter = $after.activeAssets
            activeAssetFingerprintBefore = $before.activeAssetFingerprint
            activeAssetFingerprintAfter = $after.activeAssetFingerprint
            questionFingerprintBefore = $before.questionFingerprint
            questionFingerprintAfter = $after.questionFingerprint
            historicalQuestionTagsUnchanged = $true
        }
        governance = [ordered]@{ candidateOnly = $true; pendingReview = $true; productionEligible = $false; activeWrite = $false }
        fullGate = [ordered]@{
            status = 'gate_na'
            reason = 'tools/run-gates.ps1 may affect PostgreSQL and API processes and is reserved for CEK-34 current confirmation'
            alternative_verification = 'CEK-23 backup verification, API build, targeted Python/API tests, live import/query smoke, roadmap/reference guards, and static hotspot audit'
            evidence_link = 'docs/evidence/cek023-regional-exam-profile-query-smoke.json'
            expires_at = 'CEK-34'
            recovery_condition = 'obtain the planned current confirmation and run tools/run-gates.ps1 at CEK-34'
        }
        rollback = [ordered]@{
            importKey = $importKey
            transactionProbeDeleted = $rollbackInsideTransaction
            transactionRolledBack = $true
            restoreManifest = $BackupManifest
        }
        referencesReviewed = @(
            'official-docs/EntityFramework.Docs@058a5fc',
            'official-docs/npgsql-doc@d04d8fd',
            'official-docs/AspNetCore.Docs@0bb3c1d',
            'architecture-samples/CleanArchitecture@43831e2'
        )
        adoptionDecision = 'Reuse DomainAssetVersion candidate JSONB and thin workflow-service projection; no new table, active switch, question-tag write, or LMS model copy.'
        completionBoundary = 'CEK-23 proves idempotent candidate profile persistence and compatible read-only queries only; profiles still require teacher review and C002R activation, and REAL005 remains not_closed.'
    }
    Write-Json $evidence $report
    $evidence | ConvertTo-Json -Depth 50
}
finally {
    if ($null -ne $apiProcess -and -not $apiProcess.HasExited) {
        Stop-Process -Id $apiProcess.Id -Force
        $apiProcess.WaitForExit()
    }
    $env:ConnectionStrings__KqgDatabase = $oldConnection
    $env:ASPNETCORE_ENVIRONMENT = $oldEnvironment
    Pop-Location
}

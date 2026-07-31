param(
    [Parameter(Mandatory)] [string] $BackupManifest,
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabaseUser = 'postgres',
    [string] $DatabasePassword = $env:PGPASSWORD,
    [int] $ApiPort = 5287,
    [string] $ReportPath = 'docs\evidence\cek019a-observed-exam-evidence-api-smoke.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$psql = 'C:\Program Files\PostgreSQL\17\bin\psql.exe'
$workflowKey = 'guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1'
$importKey = 'cek019a_guangzhou_observed_exam_evidence_v1'

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Write-Json([object] $Value, [string] $Path) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 40) + "`n"), [Text.UTF8Encoding]::new($false))
}

function Get-DatabaseState {
    $sql = @"
select json_build_object(
  'observedPerformance', (select count(*) from observed_performance_evidence where batch_key='$importKey'),
  'observedErrors', (select count(*) from observed_error_evidence where batch_key='$importKey'),
  'teachingRecommendations', (select count(*) from teaching_recommendations where batch_key='$importKey'),
  'nonCandidateEvidence', (
    (select count(*) from observed_performance_evidence where batch_key='$importKey' and (status<>'candidate' or review_status<>'pending_review' or production_eligible)) +
    (select count(*) from observed_error_evidence where batch_key='$importKey' and (status<>'candidate' or review_status<>'pending_review' or production_eligible)) +
    (select count(*) from teaching_recommendations where batch_key='$importKey' and (status<>'candidate' or review_status<>'pending_review' or production_eligible))
  ),
  'reviewItems', (select count(*) from review_queue_items where review_type='observed_exam_evidence' and payload->>'importKey'='$importKey' and status='open'),
  'activeAssets', (select count(*) from domain_asset_versions where status='active'),
  'questionCount', (select count(*) from question_items where custom_fields->>'sourceWorkflowKey'='$workflowKey'),
  'questionFingerprint', (
    select md5(string_agg(concat_ws('|',id::text,coalesce(difficulty_estimated::text,''),coalesce(difficulty_observed::text,''),status,coalesce(primary_knowledge_id::text,''),coalesce(custom_fields->>'productionEligible','')), E'\n' order by id))
    from question_items where custom_fields->>'sourceWorkflowKey'='$workflowKey'
  )
);
"@
    $value = (& $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c $sql) | ConvertFrom-Json
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-19A database state query failed'
    return $value
}

. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword $DatabasePassword
Assert-True (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'database password required'
Assert-True (Test-Path -LiteralPath $BackupManifest -PathType Leaf) 'backup manifest missing'
Assert-True (Test-Path -LiteralPath $psql -PathType Leaf) 'psql missing'

$env:PGPASSWORD = $DatabasePassword
$connection = "host=$DatabaseHost port=$DatabasePort dbname=$DatabaseName user=$DatabaseUser"
$report = [IO.Path]::GetFullPath((Join-Path $repoRoot $ReportPath))
$tmpRoot = Join-Path $repoRoot 'tmp\cek019a'
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
$apiProcess = $null
$oldConnection = $env:ConnectionStrings__KqgDatabase
$oldEnvironment = $env:ASPNETCORE_ENVIRONMENT

Push-Location $repoRoot
try {
    $backup = pwsh -NoProfile -ExecutionPolicy Bypass -File tools\verify-backup.ps1 -ManifestPath $BackupManifest | ConvertFrom-Json
    Assert-True ($backup.status -eq 'ok') 'backup verification failed'

    python -m unittest tests.workers.test_observed_exam_evidence_import tests.workers.test_guangzhou_year_report_evidence
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-19A Python tests failed'
    dotnet build apps/api/K12QuestionGraph.Api.csproj --no-restore | Write-Host
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-19A API build failed'
    dotnet test tests/api/K12QuestionGraph.Api.Tests/K12QuestionGraph.Api.Tests.csproj -c Debug --filter KnowledgeEvidenceWorkflow --no-restore | Write-Host
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-19A API tests failed'

    $before = Get-DatabaseState
    foreach ($suffix in @('first', 'second')) {
        python tools\observed_exam_evidence_import.py `
            --package tmp\cek018\guangzhou-year-report-evidence.candidate.json `
            --connection-string $connection --backup-manifest $BackupManifest `
            --backup-verified --apply --report (Join-Path $tmpRoot "import-$suffix.json") | Out-Null
        Assert-True ($LASTEXITCODE -eq 0) "observed evidence import failed: $suffix"
    }
    $after = Get-DatabaseState
    Assert-True ($after.observedPerformance -eq 157) 'CEK-19A performance count mismatch'
    Assert-True ($after.observedErrors -eq 35) 'CEK-19A error count mismatch'
    Assert-True ($after.teachingRecommendations -eq 25) 'CEK-19A recommendation count mismatch'
    Assert-True ($after.reviewItems -eq 234) 'CEK-19A review queue count mismatch'
    Assert-True ($after.nonCandidateEvidence -eq 0) 'CEK-19A candidate guard failed'
    Assert-True ($after.activeAssets -eq $before.activeAssets) 'CEK-19A active asset count changed'
    Assert-True ($after.questionCount -eq 234) 'CEK-19A question count changed'
    Assert-True ($after.questionFingerprint -eq $before.questionFingerprint) 'CEK-19A legacy question fields changed'

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
        try {
            $probe = Invoke-RestMethod -Uri "http://127.0.0.1:$ApiPort/health/ready" -TimeoutSec 2
            if ($probe.status -eq 'ok') { $ready = $true; break }
        } catch { Start-Sleep -Milliseconds 250 }
    }
    Assert-True $ready 'CEK-19A API did not become ready'

    $observed = Invoke-RestMethod -Uri "http://127.0.0.1:$ApiPort/knowledge-evidence/observed-exam-evidence?reviewStatus=pending_review&take=500" -TimeoutSec 20
    Assert-True ($observed.performanceReturned -eq 157) 'CEK-19A performance API count mismatch'
    Assert-True ($observed.errorsReturned -eq 35) 'CEK-19A errors API count mismatch'
    Assert-True ($observed.teachingRecommendationsReturned -eq 25) 'CEK-19A recommendations API count mismatch'
    Assert-True (-not $observed.productionEligible) 'CEK-19A API production guard failed'
    $leaked = @($observed.performance + $observed.errors + $observed.teachingRecommendations | Where-Object {
        $_.reviewStatus -ne 'pending_review' -or $_.status -ne 'candidate' -or $_.productionEligible
    })
    Assert-True ($leaked.Count -eq 0) 'CEK-19A API leaked non-candidate evidence'

    $targetId = $observed.performance[0].assessmentTargetId
    $targetView = Invoke-RestMethod -Uri "http://127.0.0.1:$ApiPort/knowledge-evidence/observed-exam-evidence?assessmentTargetId=$targetId&take=500" -TimeoutSec 20
    $wrongTarget = @($targetView.performance + $targetView.errors + $targetView.teachingRecommendations | Where-Object { $_.assessmentTargetId -ne $targetId })
    Assert-True ($wrongTarget.Count -eq 0) 'CEK-19A target filter leaked another target'

    $first = Get-Content -Raw (Join-Path $tmpRoot 'import-first.json') | ConvertFrom-Json
    $second = Get-Content -Raw (Join-Path $tmpRoot 'import-second.json') | ConvertFrom-Json
    $evidence = [ordered]@{
        schemaVersion = 'cek019a-observed-exam-evidence-api-smoke.v1'
        status = 'pass'
        checkedAt = [DateTimeOffset]::UtcNow.ToString('o')
        taskId = 'CEK-19A'
        backup = [ordered]@{ manifest = $BackupManifest; verified = $true }
        import = [ordered]@{
            first = $first.status
            second = $second.status
            idempotent = $true
            counts = $after
        }
        api = [ordered]@{
            ready = $true
            performanceReturned = $observed.performanceReturned
            errorsReturned = $observed.errorsReturned
            teachingRecommendationsReturned = $observed.teachingRecommendationsReturned
            targetFilterVerified = $true
            readOnly = $true
        }
        compatibility = [ordered]@{
            questionFingerprintBefore = $before.questionFingerprint
            questionFingerprintAfter = $after.questionFingerprint
            legacyQuestionFieldsUnchanged = $true
            activeAssetCount = $after.activeAssets
            activeUnchanged = $true
        }
        governance = [ordered]@{ candidateOnly = $true; pendingReview = $true; productionEligible = $false; reviewItems = $after.reviewItems }
        rollback = "delete review_queue_items by payload importKey $importKey and evidence rows by batch_key $importKey, or restore $BackupManifest"
        completionBoundary = 'CEK-19A proves idempotent candidate import and read-only API query only; no evidence is teacher-approved or active, and REAL005 remains not_closed.'
    }
    Write-Json $evidence $report
    $evidence | ConvertTo-Json -Depth 40
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

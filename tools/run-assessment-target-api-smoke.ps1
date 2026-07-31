param(
    [Parameter(Mandatory)] [string] $BackupManifest,
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabaseUser = 'postgres',
    [string] $DatabasePassword = $env:PGPASSWORD,
    [int] $ApiPort = 5286,
    [string] $ReportPath = 'docs\evidence\cek016-assessment-target-api-smoke.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$psql = 'C:\Program Files\PostgreSQL\17\bin\psql.exe'

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Write-Json([object] $Value, [string] $Path) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 40) + "`n"), [Text.UTF8Encoding]::new($false))
}

. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword $DatabasePassword
Assert-True (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'database password required'
Assert-True (Test-Path -LiteralPath $BackupManifest -PathType Leaf) 'backup manifest missing'
Assert-True (Test-Path -LiteralPath $psql -PathType Leaf) 'psql missing'

$connection = "host=$DatabaseHost port=$DatabasePort dbname=$DatabaseName user=$DatabaseUser"
$report = [IO.Path]::GetFullPath((Join-Path $repoRoot $ReportPath))
$tmpRoot = Join-Path $repoRoot 'tmp\cek016'
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
$apiProcess = $null
$oldConnection = $env:ConnectionStrings__KqgDatabase
$oldEnvironment = $env:ASPNETCORE_ENVIRONMENT

Push-Location $repoRoot
try {
    $backup = pwsh -NoProfile -ExecutionPolicy Bypass -File tools\verify-backup.ps1 -ManifestPath $BackupManifest | ConvertFrom-Json
    Assert-True ($backup.status -eq 'ok') 'backup verification failed'
    python -m unittest tests.workers.test_curriculum_candidate_import tests.workers.test_assessment_target_import
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-16 Python tests failed'
    dotnet test tests/api/K12QuestionGraph.Api.Tests/K12QuestionGraph.Api.Tests.csproj -c Debug --filter KnowledgeEvidenceWorkflow --no-restore | Write-Host
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-16 API tests failed'

    foreach ($suffix in @('first', 'second')) {
        python tools\curriculum_candidate_import.py `
            --requirements tmp\cek007\curriculum-requirement-facets.candidate.json `
            --crosswalk tmp\cek008\curriculum-knowledge-crosswalk.candidate.json `
            --connection-string $connection --database-name $DatabaseName `
            --backup-manifest $BackupManifest --backup-verified --apply --allow-main-candidate-write `
            --report (Join-Path $tmpRoot "curriculum-$suffix.json") | Out-Null
        Assert-True ($LASTEXITCODE -eq 0) "curriculum candidate import failed: $suffix"

        python tools\assessment_target_import.py `
            --targets tmp\cek014\assessment-targets.candidate.json `
            --alignments tmp\cek013\guangzhou-three-source-alignment.candidate.json `
            --connection-string $connection --backup-manifest $BackupManifest `
            --backup-verified --apply --report (Join-Path $tmpRoot "targets-$suffix.json") | Out-Null
        Assert-True ($LASTEXITCODE -eq 0) "assessment target import failed: $suffix"
    }

    $sql = @"
select json_build_object(
  'targets', (select count(*) from assessment_targets where batch_key='cek016_guangzhou_assessment_targets_v1'),
  'nonCandidateTargets', (select count(*) from assessment_targets where batch_key='cek016_guangzhou_assessment_targets_v1' and (status<>'candidate' or review_status<>'pending_review' or production_eligible)),
  'knowledgeMappings', (select count(*) from assessment_target_knowledge_mappings m join assessment_targets t on t.id=m.assessment_target_id where t.batch_key='cek016_guangzhou_assessment_targets_v1'),
  'curriculumAlignments', (select count(*) from curriculum_alignments a join assessment_targets t on t.id=a.assessment_target_id where t.batch_key='cek016_guangzhou_assessment_targets_v1'),
  'originalBasis', (select count(*) from curriculum_alignments a join assessment_targets t on t.id=a.assessment_target_id where t.batch_key='cek016_guangzhou_assessment_targets_v1' and a.original_basis),
  'reviewItems', (select count(*) from review_queue_items where review_type='assessment_target' and payload->>'importKey'='cek016_guangzhou_assessment_targets_v1' and status='open'),
  'curriculumAssets', (select count(*) from domain_asset_versions where asset_type in ('curriculum_requirement','requirement_facet') and status='candidate'),
  'activeAssets', (select count(*) from domain_asset_versions where status='active')
);
"@
    $counts = (& $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c $sql) | ConvertFrom-Json
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-16 database verification query failed'
    Assert-True ($counts.targets -eq 444) 'CEK-16 target count mismatch'
    Assert-True ($counts.nonCandidateTargets -eq 0) 'CEK-16 candidate guard failed'
    Assert-True ($counts.reviewItems -eq 444) 'CEK-16 review queue count mismatch'
    Assert-True ($counts.curriculumAssets -eq 273) 'CEK-16 curriculum candidate asset count mismatch'
    Assert-True ($counts.activeAssets -eq 452) 'CEK-16 active asset count changed'
    Assert-True ($counts.originalBasis -eq 0) 'CEK-16 retrospective/original-basis guard failed'

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
    Assert-True $ready 'CEK-16 API did not become ready'
    $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$ApiPort/knowledge-evidence/assessment-targets?reviewStatus=pending_review&take=5" -TimeoutSec 10
    $queue = Invoke-RestMethod -Uri "http://127.0.0.1:$ApiPort/knowledge-evidence/review-queue?take=5" -TimeoutSec 10
    Assert-True ($targets.returned -eq 5 -and $targets.productionEligible -eq $false) 'CEK-16 target API response mismatch'
    Assert-True ($queue.returned -eq 5 -and $queue.productionEligible -eq $false) 'CEK-16 review API response mismatch'
    Assert-True (@($targets.items | Where-Object { $_.reviewStatus -ne 'pending_review' -or $_.productionEligible }).Count -eq 0) 'CEK-16 API leaked non-candidate state'
    Assert-True (@($targets.items.curriculumAlignments | Where-Object { $_.originalBasis }).Count -eq 0) 'CEK-16 API original-basis guard failed'

    $first = Get-Content -Raw (Join-Path $tmpRoot 'targets-first.json') | ConvertFrom-Json
    $second = Get-Content -Raw (Join-Path $tmpRoot 'targets-second.json') | ConvertFrom-Json
    $evidence = [ordered]@{
        schemaVersion = 'cek016-assessment-target-api-smoke.v1'
        status = 'pass'
        checkedAt = [DateTimeOffset]::UtcNow.ToString('o')
        taskId = 'CEK-16'
        backup = [ordered]@{ manifest = $BackupManifest; verified = $true }
        import = [ordered]@{ first = $first.status; second = $second.status; idempotent = $true; counts = $counts }
        api = [ordered]@{ ready = $true; targetReturned = $targets.returned; reviewReturned = $queue.returned; readOnly = $true }
        governance = [ordered]@{ candidateOnly = $true; pendingReview = $true; productionEligible = $false; activeAssetCount = $counts.activeAssets; activeUnchanged = $true }
        rollback = "delete rows by importKey cek016_guangzhou_assessment_targets_v1 and CEK009 candidate import key, or restore $BackupManifest"
        completionBoundary = 'CEK-16 proves idempotent candidate import and read-only API only; no candidate is teacher-approved or active, and REAL005 remains not_closed.'
    }
    Write-Json $evidence $report
    $evidence | ConvertTo-Json -Depth 30
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

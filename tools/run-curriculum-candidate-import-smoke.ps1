param(
    [string] $RequirementPath = 'tmp\cek007\curriculum-requirement-facets.candidate.json',
    [string] $CrosswalkPath = 'tmp\cek008\curriculum-knowledge-crosswalk.candidate.json',
    [Parameter(Mandatory)] [string] $BackupManifest,
    [string] $DatabaseName = 'k12_question_graph_cek009_20260728',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabaseUser = 'postgres',
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $ReportPath = 'docs\evidence\cek009-curriculum-candidate-import.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pgBin = 'C:\Program Files\PostgreSQL\17\bin'
$psql = Join-Path $pgBin 'psql.exe'

function Assert-True([bool]$Condition,[string]$Message) { if(-not $Condition){throw $Message} }
function Write-Json([object]$Value,[string]$Path) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path,(($Value|ConvertTo-Json -Depth 30)+"`n"),[Text.UTF8Encoding]::new($false))
}

. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword $DatabasePassword
Assert-True (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'database password required'
Assert-True ($DatabaseName -match 'cek009') 'smoke requires isolated CEK009 database'
Assert-True (Test-Path -LiteralPath $BackupManifest -PathType Leaf) 'backup manifest missing'
Assert-True (Test-Path -LiteralPath $psql -PathType Leaf) 'psql missing'

$requirements = (Resolve-Path $RequirementPath).Path
$crosswalk = (Resolve-Path $CrosswalkPath).Path
$report = [IO.Path]::GetFullPath((Join-Path $repoRoot $ReportPath))
$dryReport = Join-Path $repoRoot 'tmp\cek009\dry-run.json'
$applyReport = Join-Path $repoRoot 'tmp\cek009\apply.json'
$secondReport = Join-Path $repoRoot 'tmp\cek009\apply-second.json'
$connection = "host=$DatabaseHost port=$DatabasePort dbname=$DatabaseName user=$DatabaseUser"

Push-Location $repoRoot
try {
    $verifyOutput = pwsh -NoProfile -ExecutionPolicy Bypass -File tools\verify-backup.ps1 -ManifestPath $BackupManifest | ConvertFrom-Json
    Assert-True ($verifyOutput.status -eq 'ok') 'backup verification failed'
    python -m unittest tests.workers.test_curriculum_candidate_import
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-09 unit tests failed'

    foreach($run in @(
        @{path=$dryReport;apply=$false},
        @{path=$applyReport;apply=$true},
        @{path=$secondReport;apply=$true}
    )) {
        $args=@('tools\curriculum_candidate_import.py','--requirements',$requirements,'--crosswalk',$crosswalk,
            '--connection-string',$connection,'--database-name',$DatabaseName,'--backup-manifest',$BackupManifest,'--report',$run.path)
        if($run.apply){$args += @('--apply','--backup-verified')}
        python @args | Out-Null
        Assert-True ($LASTEXITCODE -eq 0) "candidate import run failed: $($run.path)"
    }
    $dry=Get-Content -Raw $dryReport|ConvertFrom-Json
    $first=Get-Content -Raw $applyReport|ConvertFrom-Json
    $second=Get-Content -Raw $secondReport|ConvertFrom-Json
    Assert-True ($dry.status -eq 'dry_run') 'dry-run status mismatch'
    Assert-True ($first.status -eq 'applied' -and $second.status -eq 'applied') 'apply status mismatch'
    Assert-True ($first.activeBefore.sha256 -eq $second.activeAfter.sha256) 'active fingerprint changed across idempotent apply'

    $sql=@"
select json_build_object(
 'assets',count(*),
 'requirements',count(*) filter(where asset_type='curriculum_requirement'),
 'facets',count(*) filter(where asset_type='requirement_facet'),
 'nonCandidate',count(*) filter(where status<>'candidate'),
 'missingAnchors',count(*) filter(where jsonb_array_length(source_evidence->'anchorSha256s')=0),
 'productionEligible',count(*) filter(where (source_evidence->>'productionEligible')::boolean)
) from domain_asset_versions where source_evidence->>'importKey'='cek009_curriculum_requirements_2022_2025_v1';
select json_build_object(
 'mappings',count(*),
 'nonPending',count(*) filter(where review_status<>'pending_review'),
 'autoApplied',count(*) filter(where auto_applied),
 'missingTargets',count(*) filter(where t.status<>'active' or t.asset_type<>'knowledge_point')
) from domain_asset_mappings m
join domain_asset_versions s on s.id=m.source_asset_version_id
join domain_asset_versions t on t.id=m.target_asset_version_id
where m.evidence->>'importKey'='cek009_curriculum_requirements_2022_2025_v1';
"@
    $rows=@(& $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c $sql)
    Assert-True ($LASTEXITCODE -eq 0 -and $rows.Count -eq 2) 'post-apply query failed'
    $assets=$rows[0]|ConvertFrom-Json
    $mappings=$rows[1]|ConvertFrom-Json
    Assert-True ($assets.assets -eq 273 -and $assets.requirements -eq 89 -and $assets.facets -eq 184) 'candidate counts mismatch'
    Assert-True ($assets.nonCandidate -eq 0 -and $assets.missingAnchors -eq 0 -and $assets.productionEligible -eq 0) 'candidate invariant failed'
    Assert-True ($mappings.mappings -eq 94 -and $mappings.nonPending -eq 0 -and $mappings.autoApplied -eq 0 -and $mappings.missingTargets -eq 0) 'mapping invariant failed'

    $evidence=[ordered]@{
        schemaVersion='cek009-curriculum-candidate-import.v1';status='pass';checkedAt=[DateTimeOffset]::UtcNow.ToString('o');taskId='CEK-09'
        isolation=[ordered]@{databaseName=$DatabaseName;isolated=$true;backupManifest=$BackupManifest;backupVerified=$true;rollback='drop isolated database; main database restore remains available from the verified manifest'}
        dryRun=[ordered]@{status=$dry.status;assets=$dry.counts.assets;mappings=$dry.counts.mappings}
        apply=[ordered]@{first=$first.status;second=$second.status;idempotent=$true;assets=$assets;mappings=$mappings}
        activeInvariant=[ordered]@{before=$first.activeBefore;after=$second.activeAfter;unchanged=$true}
        contracts=[ordered]@{canonicalAssetTypes=@('curriculum_requirement','requirement_facet');legacyAssetType='curriculum_standard_item';allCandidate=$true;allPendingReview=$true;productionEligible=$false;anchorsPresent=$true;targetsActive=$true}
        governance=[ordered]@{mainDatabaseWrite=$false;isolatedDatabaseWrite=$true;c002ActiveWrite=$false;knowledgeNodeWrite=$false;externalModelCalls=0}
        completionBoundary='CEK-09 proves isolated candidate persistence and idempotent query only; it does not approve candidates, switch production active, close REAL005, or establish teacher/live acceptance.'
    }
    Write-Json $evidence $report
    $evidence|ConvertTo-Json -Depth 20
}
finally { Pop-Location }

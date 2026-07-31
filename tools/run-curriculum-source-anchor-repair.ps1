param(
    [string] $RequirementsPath = 'tmp\cek007\curriculum-requirement-facets.candidate.json',
    [string] $CrosswalkPath = 'tmp\cek008\curriculum-knowledge-crosswalk.candidate.json',
    [string] $ReportPath = 'docs\evidence\cek030-curriculum-source-anchor-repair.json',
    [string] $BackupRoot = 'D:\KQG_Backups',
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'dotenv.ps1')
. (Join-Path $PSScriptRoot 'database-env.ps1')
Import-KqgDotEnv -RepoRoot $repoRoot
$env:PGPASSWORD = Resolve-KqgDatabasePassword -DatabasePassword $env:PGPASSWORD

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Resolve-RepoPath([string] $Path) {
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    return Join-Path $repoRoot $Path
}

$requirements = (Resolve-Path -LiteralPath (Resolve-RepoPath $RequirementsPath)).Path
$crosswalk = (Resolve-Path -LiteralPath (Resolve-RepoPath $CrosswalkPath)).Path
$resolvedReport = Resolve-RepoPath $ReportPath
$pgDump = Join-Path $PgBin 'pg_dump.exe'
$pgRestore = Join-Path $PgBin 'pg_restore.exe'
$psql = Join-Path $PgBin 'psql.exe'
foreach ($tool in @($pgDump, $pgRestore, $psql)) {
    Assert-Condition (Test-Path -LiteralPath $tool -PathType Leaf) "PostgreSQL tool missing: $tool"
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDirectory = Join-Path $BackupRoot "cek030-curriculum-anchor-$timestamp"
New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
$databaseDump = Join-Path $backupDirectory 'database.dump'
$restoreList = Join-Path $backupDirectory 'database.restore-list.txt'
$backupManifest = Join-Path $backupDirectory 'manifest.json'

& $pgDump -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -Fc -f $databaseDump
if ($LASTEXITCODE -ne 0) { throw "pg_dump failed with exit code $LASTEXITCODE" }
& $pgRestore -l $databaseDump | Set-Content -LiteralPath $restoreList -Encoding utf8
if ($LASTEXITCODE -ne 0) { throw "pg_restore list verification failed with exit code $LASTEXITCODE" }
$restoreListText = Get-Content -LiteralPath $restoreList -Raw
Assert-Condition ($restoreListText.Contains('TABLE DATA public domain_asset_versions')) 'backup restore list lacks domain_asset_versions data'
Assert-Condition ($restoreListText.Contains('TABLE DATA public domain_asset_mappings')) 'backup restore list lacks domain_asset_mappings data'
$databaseDumpHash = (Get-FileHash -LiteralPath $databaseDump -Algorithm SHA256).Hash.ToLowerInvariant()

$manifest = [ordered]@{
    schemaVersion = 'cek030-curriculum-source-anchor-backup.v1'
    status = 'verified'
    createdAt = (Get-Date).ToUniversalTime().ToString('o')
    database = [ordered]@{
        engine = 'postgresql'
        databaseName = $DatabaseName
        dump = 'database.dump'
        bytes = (Get-Item -LiteralPath $databaseDump).Length
        sha256 = $databaseDumpHash
        restoreList = 'database.restore-list.txt'
        restoreListSha256 = (Get-FileHash -LiteralPath $restoreList -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    restore = [ordered]@{
        boundary = 'Restore only into an empty or recreated database after stopping dependent services; never overlay the live database.'
        command = "pg_restore -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d <empty_database> --clean --if-exists database.dump"
    }
    scope = [ordered]@{
        operation = 'candidate curriculum SourceEvidence repair'
        activeWriteAllowed = $false
        reviewDecisionWriteAllowed = $false
    }
}
$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $backupManifest -Encoding utf8
Assert-Condition ((Get-FileHash -LiteralPath $databaseDump -Algorithm SHA256).Hash.ToLowerInvariant() -eq $databaseDumpHash) 'database dump hash changed after manifest write'

$importReportPath = Join-Path $backupDirectory 'curriculum-candidate-import-report.json'
$connectionString = "host=$DatabaseHost port=$DatabasePort dbname=$DatabaseName user=$DatabaseUser"
& python (Join-Path $PSScriptRoot 'curriculum_candidate_import.py') `
    --requirements $requirements `
    --crosswalk $crosswalk `
    --connection-string $connectionString `
    --database-name $DatabaseName `
    --backup-manifest $backupManifest `
    --backup-verified `
    --apply `
    --allow-main-candidate-write `
    --report $importReportPath
if ($LASTEXITCODE -ne 0) { throw "curriculum candidate repair failed with exit code $LASTEXITCODE" }
$importReport = Get-Content -LiteralPath $importReportPath -Raw | ConvertFrom-Json
Assert-Condition ($importReport.status -eq 'applied') 'candidate repair did not report applied status'
Assert-Condition ($importReport.activeUnchanged -eq $true) 'candidate repair changed the active fingerprint'
Assert-Condition ($importReport.activeBefore.sha256 -eq $importReport.activeAfter.sha256) 'active fingerprint SHA changed'

$verificationSql = @"
select json_build_object(
  'total',count(*),
  'candidate',count(*) filter (where status='candidate'),
  'withEvidenceAnchors',count(*) filter (where source_evidence ? 'evidenceAnchors' and jsonb_array_length(source_evidence->'evidenceAnchors') > 0),
  'pendingReview',count(*) filter (where source_evidence->>'reviewStatus'='pending_review'),
  'productionEligibleFalse',count(*) filter (where source_evidence->>'productionEligible'='false')
)::text
from domain_asset_versions
where source_evidence->>'importKey'='cek009_curriculum_requirements_2022_2025_v1';
"@
$verificationJson = (& $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -X -A -t -c $verificationSql).Trim()
if ($LASTEXITCODE -ne 0) { throw "candidate verification query failed with exit code $LASTEXITCODE" }
$verification = $verificationJson | ConvertFrom-Json
foreach ($property in @('candidate', 'withEvidenceAnchors', 'pendingReview', 'productionEligibleFalse')) {
    Assert-Condition ([int]$verification.$property -eq [int]$verification.total) "candidate verification mismatch: $property"
}

$report = [ordered]@{
    schemaVersion = 'cek030-curriculum-source-anchor-repair.v1'
    status = 'pass'
    checkedAt = (Get-Date).ToUniversalTime().ToString('o')
    backup = [ordered]@{
        manifest = $backupManifest
        dumpSha256 = $databaseDumpHash
        restoreListVerified = $true
    }
    import = $importReport
    verification = $verification
    boundary = 'Only existing curriculum candidate SourceEvidence and candidate mappings were refreshed. No review decision, active asset, active knowledge node, or production switch was written.'
    rollback = [ordered]@{
        manifest = $backupManifest
        action = 'stop dependent services and restore database.dump only into an empty or recreated database'
    }
}
New-Item -ItemType Directory -Path (Split-Path -Parent $resolvedReport) -Force | Out-Null
$report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $resolvedReport -Encoding utf8
$report | ConvertTo-Json -Depth 20

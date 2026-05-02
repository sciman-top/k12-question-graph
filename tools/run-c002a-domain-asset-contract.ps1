param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw "DatabasePassword or PGPASSWORD is required for C002A domain asset contract"
}

$psql = Join-Path $PgBin 'psql.exe'
if (-not (Test-Path -LiteralPath $psql)) {
    throw "psql.exe not found: $psql"
}

$previousConnectionString = $env:KQG_CONNECTION_STRING
$previousPgPassword = $env:PGPASSWORD
$env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
$env:PGPASSWORD = $DatabasePassword

function Invoke-Scalar([string] $Sql) {
    $value = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c $Sql
    if ($LASTEXITCODE -ne 0) {
        throw "psql scalar failed: $Sql"
    }

    return ($value | Select-Object -First 1).Trim()
}

function Invoke-Statement([string] $Sql) {
    & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -v ON_ERROR_STOP=1 -c $Sql | Write-Host
    if ($LASTEXITCODE -ne 0) {
        throw "psql statement failed"
    }
}

try {
    Push-Location $repoRoot
    try {
        dotnet ef database update --project apps\api\K12QuestionGraph.Api.csproj --startup-project apps\api\K12QuestionGraph.Api.csproj | Write-Host
        if ($LASTEXITCODE -ne 0) {
            throw "dotnet ef database update failed"
        }
    }
    finally {
        Pop-Location
    }

    $tableCount = [int](Invoke-Scalar @"
select count(*)
from information_schema.tables
where table_schema = 'public'
  and table_name in ('domain_asset_versions','domain_asset_mappings','domain_asset_migrations');
"@)
    if ($tableCount -ne 3) {
        throw "missing C002A domain asset tables"
    }

    $jsonbColumnCount = [int](Invoke-Scalar @"
select count(*)
from information_schema.columns
where table_schema = 'public'
  and table_name in ('domain_asset_versions','domain_asset_mappings','domain_asset_migrations')
  and column_name in ('effective_scope','source_evidence','metadata','evidence','impact_report','rollback_snapshot')
  and udt_name = 'jsonb';
"@)
    if ($jsonbColumnCount -ne 6) {
        throw "missing C002A jsonb evidence/scope/report columns"
    }

    $checkCount = [int](Invoke-Scalar @"
select count(*)
from information_schema.table_constraints
where table_schema = 'public'
  and constraint_type = 'CHECK'
  and constraint_name in (
    'ck_domain_asset_versions_version',
    'ck_domain_asset_versions_status',
    'ck_domain_asset_versions_authority',
    'ck_domain_asset_mappings_not_self',
    'ck_domain_asset_mappings_confidence',
    'ck_domain_asset_mappings_type',
    'ck_domain_asset_mappings_review_status',
    'ck_domain_asset_mappings_auto_review',
    'ck_domain_asset_migrations_status',
    'ck_domain_asset_migrations_not_self'
  );
"@)
    if ($checkCount -ne 10) {
        throw "missing C002A check constraints"
    }

    $foreignKeyCount = [int](Invoke-Scalar @"
select count(*)
from information_schema.table_constraints
where table_schema = 'public'
  and constraint_type = 'FOREIGN KEY'
  and constraint_name in (
    'fk_domain_asset_mappings_domain_asset_versions_source_asset_ve',
    'fk_domain_asset_mappings_domain_asset_versions_target_asset_ve',
    'fk_domain_asset_mappings_domain_asset_migrations_migration_id',
    'fk_domain_asset_migrations_domain_asset_versions_from_asset_ve',
    'fk_domain_asset_migrations_domain_asset_versions_to_asset_vers'
  );
"@)
    if ($foreignKeyCount -ne 5) {
        throw "missing C002A foreign keys"
    }

    $knowledgeStatusConstraint = Invoke-Scalar @"
select pg_get_constraintdef(c.oid)
from pg_constraint c
join pg_class t on t.oid = c.conrelid
join pg_namespace n on n.oid = t.relnamespace
where n.nspname = 'public'
  and t.relname = 'knowledge_nodes'
  and c.conname = 'ck_knowledge_nodes_status';
"@
    foreach ($status in @('candidate','reviewed','merged','superseded')) {
        if ($knowledgeStatusConstraint -notmatch $status) {
            throw "knowledge node status constraint does not allow $status"
        }
    }

    $scenarioKey = "c002a-contract-$([Guid]::NewGuid())"
    Invoke-Statement @"
begin;
with source_asset as (
  insert into domain_asset_versions (
    asset_type, stable_id, version, display_name, status, authority, effective_scope, source_evidence, metadata, created_at, updated_at
  )
  values (
    'knowledge_node',
    '$scenarioKey-draft',
    1,
    'C002A draft asset',
    'draft',
    'bootstrap',
    '{"subject":"physics","stage":"junior_middle_school"}',
    '{"source":"contract_test"}',
    '{"mode":"draft"}',
    now(),
    now()
  )
  returning id
), target_asset as (
  insert into domain_asset_versions (
    asset_type, stable_id, version, display_name, status, authority, effective_scope, source_evidence, metadata, created_at, updated_at
  )
  values (
    'knowledge_node',
    '$scenarioKey-formal',
    1,
    'C002A formal candidate asset',
    'candidate',
    'source_derived',
    '{"subject":"physics","stage":"junior_middle_school"}',
    '{"source":"contract_test"}',
    '{"mode":"formal_candidate"}',
    now(),
    now()
  )
  returning id
), migration as (
  insert into domain_asset_migrations (
    migration_key, status, from_asset_version_id, to_asset_version_id, impact_report, rollback_snapshot, created_by, created_at
  )
  select
    '$scenarioKey',
    'dry_run',
    source_asset.id,
    target_asset.id,
    '{"auto_migrated":1,"pending_review":0}',
    '{"snapshot":"contract"}',
    'contract',
    now()
  from source_asset, target_asset
  returning id, from_asset_version_id, to_asset_version_id
)
insert into domain_asset_mappings (
  source_asset_version_id, target_asset_version_id, mapping_type, confidence, review_status, auto_applied, evidence, migration_id, created_at
)
select
  from_asset_version_id,
  to_asset_version_id,
  'equivalent',
  0.99,
  'auto_applied',
  true,
  '{"reason":"high_confidence_low_impact_contract"}',
  id,
  now()
from migration;
rollback;
"@

    [ordered]@{
        status = 'pass'
        tables = $tableCount
        jsonbColumns = $jsonbColumnCount
        checkConstraints = $checkCount
        foreignKeys = $foreignKeyCount
        knowledgeNodeStatusExtended = $true
        dryRunMappingRollback = 'pass'
    } | ConvertTo-Json
}
finally {
    $env:KQG_CONNECTION_STRING = $previousConnectionString
    $env:PGPASSWORD = $previousPgPassword
}

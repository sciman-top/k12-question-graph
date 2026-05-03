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
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw "DatabasePassword or PGPASSWORD is required for C001 contract"
}

$psql = Join-Path $PgBin 'psql.exe'
if (-not (Test-Path -LiteralPath $psql)) {
    throw "psql.exe not found: $psql"
}

$previousConnectionString = $env:KQG_CONNECTION_STRING
$env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"

function Invoke-Scalar([string] $Sql) {
    $value = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c $Sql
    if ($LASTEXITCODE -ne 0) {
        throw "psql scalar failed: $Sql"
    }

    return ($value | Select-Object -First 1).Trim()
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
  and table_name in ('knowledge_nodes','knowledge_edges','knowledge_mappings');
"@)
    if ($tableCount -ne 3) {
        throw "missing C001 knowledge tables"
    }

    $versionColumnCount = [int](Invoke-Scalar @"
select count(*)
from information_schema.columns
where table_schema = 'public'
  and table_name in ('knowledge_nodes','knowledge_edges','knowledge_mappings')
  and column_name = 'version';
"@)
    if ($versionColumnCount -ne 3) {
        throw "missing C001 version columns"
    }

    $jsonbColumnCount = [int](Invoke-Scalar @"
select count(*)
from information_schema.columns
where table_schema = 'public'
  and table_name in ('knowledge_nodes','knowledge_edges','knowledge_mappings')
  and column_name in ('metadata','evidence')
  and udt_name = 'jsonb';
"@)
    if ($jsonbColumnCount -ne 3) {
        throw "missing C001 jsonb evidence/metadata columns"
    }

    $foreignKeyCount = [int](Invoke-Scalar @"
select count(*)
from information_schema.table_constraints
where table_schema = 'public'
  and constraint_type = 'FOREIGN KEY'
  and constraint_name in (
    'fk_question_items_knowledge_nodes_primary_knowledge_id',
    'fk_knowledge_nodes_knowledge_nodes_parent_id',
    'fk_knowledge_edges_knowledge_nodes_source_node_id',
    'fk_knowledge_edges_knowledge_nodes_target_node_id',
    'fk_knowledge_mappings_knowledge_nodes_knowledge_node_id',
    'fk_knowledge_mappings_question_items_question_item_id'
  );
"@)
    if ($foreignKeyCount -ne 6) {
        throw "missing C001 foreign keys"
    }

    $checkCount = [int](Invoke-Scalar @"
select count(*)
from information_schema.table_constraints
where table_schema = 'public'
  and constraint_type = 'CHECK'
  and constraint_name in (
    'ck_knowledge_nodes_level',
    'ck_knowledge_nodes_status',
    'ck_knowledge_nodes_version',
    'ck_knowledge_edges_not_self',
    'ck_knowledge_edges_type',
    'ck_knowledge_edges_version',
    'ck_knowledge_mappings_confidence',
    'ck_knowledge_mappings_source',
    'ck_knowledge_mappings_version'
  );
"@)
    if ($checkCount -ne 9) {
        throw "missing C001 check constraints"
    }

    [ordered]@{
        status = 'pass'
        tables = $tableCount
        versionColumns = $versionColumnCount
        jsonbColumns = $jsonbColumnCount
        foreignKeys = $foreignKeyCount
        checkConstraints = $checkCount
    } | ConvertTo-Json
}
finally {
    $env:KQG_CONNECTION_STRING = $previousConnectionString
}

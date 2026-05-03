param(
    [string] $SeedPath = 'configs\knowledge\junior-physics-l1-l3.json',
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
$resolvedSeedPath = (Resolve-Path -LiteralPath (Join-Path $repoRoot $SeedPath)).Path

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw "DatabasePassword or PGPASSWORD is required for knowledge seed"
}

$psql = Join-Path $PgBin 'psql.exe'
if (-not (Test-Path -LiteralPath $psql)) {
    throw "psql.exe not found: $psql"
}

$seed = Get-Content -LiteralPath $resolvedSeedPath -Raw | ConvertFrom-Json
$previousPgPassword = $env:PGPASSWORD
$env:PGPASSWORD = $DatabasePassword

function ConvertTo-SqlLiteral([AllowNull()] [object] $Value) {
    if ($null -eq $Value) {
        return 'null'
    }

    $text = [string]$Value
    return "'" + $text.Replace("'", "''") + "'"
}

function Invoke-NonQuery([string] $Sql) {
    $sqlPath = Join-Path ([System.IO.Path]::GetTempPath()) "kqg-seed-$([Guid]::NewGuid().ToString('N')).sql"
    try {
        Set-Content -LiteralPath $sqlPath -Value $Sql -Encoding utf8
        & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -v ON_ERROR_STOP=1 -f $sqlPath | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "psql command failed"
        }
    }
    finally {
        Remove-Item -LiteralPath $sqlPath -Force -ErrorAction SilentlyContinue
    }
}

try {
    foreach ($node in ($seed.nodes | Sort-Object level, code)) {
        $metadata = [ordered]@{
            seed_id = $seed.seedId
            source_basis = 'bootstrap_draft_not_authoritative'
            requires_source_review = $true
            aliases = @($node.aliases)
            formulas = @($node.formulas)
        } | ConvertTo-Json -Compress

        $parentExpression = 'null'
        if (-not [string]::IsNullOrWhiteSpace($node.parentCode)) {
            $parentExpression = "(select id from knowledge_nodes where subject = $(ConvertTo-SqlLiteral $seed.subject) and stage = $(ConvertTo-SqlLiteral $seed.stage) and code = $(ConvertTo-SqlLiteral $node.parentCode) and version = $($seed.version))"
        }

        Invoke-NonQuery @"
insert into knowledge_nodes (
  subject, stage, code, title, node_type, level, status, version, parent_id, metadata, created_at, updated_at
) values (
  $(ConvertTo-SqlLiteral $seed.subject),
  $(ConvertTo-SqlLiteral $seed.stage),
  $(ConvertTo-SqlLiteral $node.code),
  $(ConvertTo-SqlLiteral $node.title),
  $(ConvertTo-SqlLiteral $node.nodeType),
  $($node.level),
  'draft',
  $($seed.version),
  $parentExpression,
  $(ConvertTo-SqlLiteral $metadata)::jsonb,
  now(),
  now()
)
on conflict (subject, stage, code, version) do update set
  title = excluded.title,
  node_type = excluded.node_type,
  level = excluded.level,
  status = excluded.status,
  parent_id = excluded.parent_id,
  metadata = excluded.metadata,
  updated_at = now();
"@
    }

    foreach ($node in ($seed.nodes | Where-Object { -not [string]::IsNullOrWhiteSpace($_.parentCode) })) {
        Invoke-NonQuery @"
insert into knowledge_edges (
  source_node_id, target_node_id, edge_type, version, metadata, created_at
)
select parent.id, child.id, 'parent_child', $($seed.version), jsonb_build_object('seed_id', $(ConvertTo-SqlLiteral $seed.seedId)), now()
from knowledge_nodes parent
join knowledge_nodes child
  on child.subject = parent.subject
 and child.stage = parent.stage
 and child.version = parent.version
where parent.subject = $(ConvertTo-SqlLiteral $seed.subject)
  and parent.stage = $(ConvertTo-SqlLiteral $seed.stage)
  and parent.code = $(ConvertTo-SqlLiteral $node.parentCode)
  and parent.version = $($seed.version)
  and child.code = $(ConvertTo-SqlLiteral $node.code)
on conflict (source_node_id, target_node_id, edge_type, version) do update set
  metadata = excluded.metadata;
"@
    }

    [ordered]@{
        status = 'pass'
        seedId = $seed.seedId
        nodeCount = @($seed.nodes).Count
        edgeCount = @($seed.nodes | Where-Object { -not [string]::IsNullOrWhiteSpace($_.parentCode) }).Count
    } | ConvertTo-Json
}
finally {
    $env:PGPASSWORD = $previousPgPassword
}

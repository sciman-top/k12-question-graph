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
    throw "DatabasePassword or PGPASSWORD is required for C002 seed validation"
}

$psql = Join-Path $PgBin 'psql.exe'
if (-not (Test-Path -LiteralPath $psql)) {
    throw "psql.exe not found: $psql"
}

$seed = Get-Content -LiteralPath $resolvedSeedPath -Raw | ConvertFrom-Json
$expectedNodes = @($seed.nodes).Count
$expectedEdges = @($seed.nodes | Where-Object { -not [string]::IsNullOrWhiteSpace($_.parentCode) }).Count
$expectedL1 = @($seed.nodes | Where-Object level -eq 1).Count
$expectedL2 = @($seed.nodes | Where-Object level -eq 2).Count
$expectedL3 = @($seed.nodes | Where-Object level -eq 3).Count

$previousPgPassword = $env:PGPASSWORD
$env:PGPASSWORD = $DatabasePassword

function ConvertTo-SqlLiteral([AllowNull()] [object] $Value) {
    if ($null -eq $Value) {
        return 'null'
    }

    $text = [string]$Value
    return "'" + $text.Replace("'", "''") + "'"
}

function Invoke-Scalar([string] $Sql) {
    $value = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c $Sql
    if ($LASTEXITCODE -ne 0) {
        throw "psql scalar failed: $Sql"
    }

    return ($value | Select-Object -First 1).Trim()
}

function Invoke-NonQuery([string] $Sql) {
    $sqlPath = Join-Path ([System.IO.Path]::GetTempPath()) "kqg-validation-$([Guid]::NewGuid().ToString('N')).sql"
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
    Push-Location $repoRoot
    try {
        .\tools\run-c001-contract.ps1 -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
        .\tools\seed-knowledge.ps1 -SeedPath $SeedPath -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
        .\tools\seed-knowledge.ps1 -SeedPath $SeedPath -DatabaseName $DatabaseName -DatabaseUser $DatabaseUser -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabasePassword $DatabasePassword -PgBin $PgBin | Write-Host
    }
    finally {
        Pop-Location
    }

    $nodeCount = [int](Invoke-Scalar "select count(*) from knowledge_nodes where metadata->>'seed_id' = $(ConvertTo-SqlLiteral $seed.seedId);")
    if ($nodeCount -ne $expectedNodes) {
        throw "expected $expectedNodes seeded nodes, got $nodeCount"
    }

    $l1Count = [int](Invoke-Scalar "select count(*) from knowledge_nodes where metadata->>'seed_id' = $(ConvertTo-SqlLiteral $seed.seedId) and level = 1;")
    $l2Count = [int](Invoke-Scalar "select count(*) from knowledge_nodes where metadata->>'seed_id' = $(ConvertTo-SqlLiteral $seed.seedId) and level = 2;")
    $l3Count = [int](Invoke-Scalar "select count(*) from knowledge_nodes where metadata->>'seed_id' = $(ConvertTo-SqlLiteral $seed.seedId) and level = 3;")
    if ($l1Count -ne $expectedL1 -or $l2Count -ne $expectedL2 -or $l3Count -ne $expectedL3) {
        throw "unexpected seeded level counts: L1=$l1Count L2=$l2Count L3=$l3Count"
    }

    $missingParents = [int](Invoke-Scalar "select count(*) from knowledge_nodes where metadata->>'seed_id' = $(ConvertTo-SqlLiteral $seed.seedId) and level > 1 and parent_id is null;")
    if ($missingParents -ne 0) {
        throw "seeded child nodes missing parent"
    }

    $nonDraftNodes = [int](Invoke-Scalar "select count(*) from knowledge_nodes where metadata->>'seed_id' = $(ConvertTo-SqlLiteral $seed.seedId) and status <> 'draft';")
    if ($nonDraftNodes -ne 0) {
        throw "C002 bootstrap nodes must remain draft until source-derived review"
    }

    $missingSourceBasis = [int](Invoke-Scalar "select count(*) from knowledge_nodes where metadata->>'seed_id' = $(ConvertTo-SqlLiteral $seed.seedId) and metadata->>'source_basis' <> 'bootstrap_draft_not_authoritative';")
    if ($missingSourceBasis -ne 0) {
        throw "C002 bootstrap nodes missing non-authoritative source basis marker"
    }

    $edgeCount = [int](Invoke-Scalar "select count(*) from knowledge_edges where metadata->>'seed_id' = $(ConvertTo-SqlLiteral $seed.seedId) and edge_type = 'parent_child';")
    if ($edgeCount -ne $expectedEdges) {
        throw "expected $expectedEdges seeded parent edges, got $edgeCount"
    }

    $bindSmokeSql = @"
do `$`$
declare
  speed_node uuid;
  ohm_node uuid;
  file_id uuid;
  doc_id uuid;
  region_id uuid;
  question_id uuid;
  source_region_count integer;
  mapping_count integer;
begin
  delete from question_items
  where custom_fields->>'validation' = 'C002';

  delete from question_blocks
  where source_region_id in (
    select sr.id
    from source_regions sr
    join source_documents sd on sd.id = sr.source_document_id
    where sd.source_title = 'C002 validation source'
  );

  delete from source_regions
  where source_document_id in (
    select id from source_documents
    where source_title = 'C002 validation source'
  );

  delete from source_documents
  where source_title = 'C002 validation source';

  select id into speed_node
  from knowledge_nodes
  where code = 'PHY-JH-MECH-MOTION-SPEED'
    and version = 1;

  select id into ohm_node
  from knowledge_nodes
  where code = 'PHY-JH-ELEC-OHM-LAW'
    and version = 1;

  if speed_node is null or ohm_node is null then
    raise exception 'required C002 L3 nodes are missing';
  end if;

  insert into file_assets (
    original_file_name, relative_path, storage_scope, content_type, sha256, size_bytes, source_metadata, created_at
  ) values (
    'c002-source.txt',
    'gate/c002-source.txt',
    'original',
    'text/plain',
    'c002000000000000000000000000000000000000000000000000000000000001',
    17,
    '{"seed_id":"C002_JUNIOR_PHYSICS_V1"}'::jsonb,
    now()
  )
  on conflict (sha256, size_bytes) do update set
    source_metadata = excluded.source_metadata
  returning id into file_id;

  insert into source_documents (
    file_asset_id, source_type, source_title, owner_scope, license_or_permission,
    sharing_allowed, contains_student_pii, anonymization_status, external_ai_allowed, created_at
  ) values (
    file_id, 'synthetic', 'C002 validation source', 'school', 'synthetic_fixture',
    true, false, 'synthetic', false, now()
  )
  returning id into doc_id;

  insert into source_regions (
    source_document_id, page_number, x, y, width, height, coordinate_unit, screenshot_relative_path, region_type, created_at
  ) values (
    doc_id, 1, 10, 10, 40, 20, 'percent', null, 'question', now()
  )
  returning id into region_id;

  insert into question_items (
    subject, stage, grade, question_type, default_score, status, primary_knowledge_id,
    blocks, custom_fields, quality_signals, created_at, updated_at
  ) values (
    'physics', 'junior_middle_school', 'grade_8', 'calculation', 3, 'draft', speed_node,
    '[]'::jsonb, '{"validation":"C002"}'::jsonb, '{}'::jsonb, now(), now()
  )
  returning id into question_id;

  insert into question_blocks (
    question_item_id, block_type, sort_order, content, source_region_id, created_at
  ) values (
    question_id, 'text', 0, '{"text":"C002 validation question"}'::jsonb, region_id, now()
  );

  insert into knowledge_mappings (
    question_item_id, knowledge_node_id, mapping_source, is_primary, confidence, version, evidence, created_at
  ) values
    (question_id, speed_node, 'manual', true, 1.0, 1, jsonb_build_object('validation','C002','reason','initial teacher binding','source_region_id',region_id), now()),
    (question_id, ohm_node, 'manual', false, 0.8, 2, jsonb_build_object('validation','C002','reason','changed mapping keeps source evidence','source_region_id',region_id), now());

  select count(*) into source_region_count
  from question_blocks
  where question_item_id = question_id
    and source_region_id = region_id;

  select count(*) into mapping_count
  from knowledge_mappings
  where question_item_id = question_id
    and version in (1, 2);

  if source_region_count <> 1 or mapping_count <> 2 then
    raise exception 'C002 mapping history/source validation failed';
  end if;
end
`$`$;
"@
    Invoke-NonQuery $bindSmokeSql

    [ordered]@{
        status = 'pass'
        seedId = $seed.seedId
        nodeCount = $nodeCount
        l1 = $l1Count
        l2 = $l2Count
        l3 = $l3Count
        parentChildEdges = $edgeCount
        nodeStatus = 'draft'
        sourceBasis = 'bootstrap_draft_not_authoritative'
        questionBindingSmoke = 'pass'
        mappingHistorySmoke = 'pass'
    } | ConvertTo-Json
}
finally {
    $env:PGPASSWORD = $previousPgPassword
}

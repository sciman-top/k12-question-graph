param(
    [Parameter(Mandatory)]
    [string] $BackupManifest,
    [switch] $Apply,
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $ReportPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
$workflowKey = 'guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1'

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for REAL005C residue cleanup'
}
if (-not (Test-Path -LiteralPath $BackupManifest -PathType Leaf)) {
    throw "Backup manifest not found: $BackupManifest"
}
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = 'docs/evidence/{0}-real005c-residue-cleanup.json' -f (Get-Date -Format 'yyyyMMdd')
}

function Invoke-Rows([string] $Sql) {
    $psql = Join-Path $PgBin 'psql.exe'
    $output = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -F '|' -v ON_ERROR_STOP=1 -c $Sql
    if ($LASTEXITCODE -ne 0) { throw 'REAL005C residue cleanup SQL failed' }
    return @(
        ($output | Out-String) -split "`r?`n" |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Invoke-Counts {
    $row = @(Invoke-Rows @"
select concat_ws('|',
  (select count(*) from knowledge_nodes where code like 'REAL005C%'),
  (select count(*) from knowledge_mappings km join knowledge_nodes kn on kn.id=km.knowledge_node_id where kn.code like 'REAL005C%'),
  (select count(*) from paper_baskets where title like 'REAL005C1%'),
  (select count(*) from assessments where title='REAL005C2 reviewed real question analysis smoke' and synthetic_fixture=true),
  (select count(*) from score_import_batches where source_file_name='real005c2-score-import.xlsx' and synthetic_fixture=true),
  (select count(*) from review_queue_items where payload::text like '%real005c1_search_paper_export_smoke%' or payload::text like '%real005c2_analysis_reference_smoke%'),
  (select count(*) from question_items qi join knowledge_nodes kn on kn.id=qi.primary_knowledge_id where kn.code like 'REAL005C%')
);
"@)
    if ($row.Count -ne 1) { throw 'REAL005C residue count query returned an unexpected shape' }
    $parts = $row[0] -split '\|', 7
    return [ordered]@{
        knowledgeNodes = [int] $parts[0]
        knowledgeMappings = [int] $parts[1]
        paperBaskets = [int] $parts[2]
        assessments = [int] $parts[3]
        scoreImportBatches = [int] $parts[4]
        reviewQueueRows = [int] $parts[5]
        questionPrimaryKnowledgeReferences = [int] $parts[6]
    }
}

function Invoke-V2Invariants {
    $row = @(Invoke-Rows @"
select concat_ws('|',
  count(*),
  count(*) filter (where status='pending_review'),
  count(*) filter (where primary_knowledge_id is null),
  count(*) filter (where coalesce((custom_fields->>'productionEligible')::boolean,false)=false),
  (select count(*) from review_queue_items where payload->>'sourceWorkflowKey'='$workflowKey' and status='open')
)
from question_items
where custom_fields->>'sourceWorkflowKey'='$workflowKey';
"@)
    if ($row.Count -ne 1) { throw 'Guangzhou v2 invariant query returned an unexpected shape' }
    $parts = $row[0] -split '\|', 5
    return [ordered]@{
        total = [int] $parts[0]
        pendingReview = [int] $parts[1]
        primaryKnowledgeNull = [int] $parts[2]
        productionEligibleFalse = [int] $parts[3]
        openReviews = [int] $parts[4]
    }
}

$backupVerification = & (Join-Path $PSScriptRoot 'verify-backup.ps1') -ManifestPath $BackupManifest | ConvertFrom-Json
if ($backupVerification.status -ne 'ok') { throw 'Backup verification failed' }
$before = Invoke-Counts
$v2Before = Invoke-V2Invariants
if ($before.questionPrimaryKnowledgeReferences -ne 0) {
    throw 'REAL005C knowledge nodes are still referenced by questions; cleanup is blocked'
}

if ($Apply) {
    $null = Invoke-Rows @'
begin;
delete from paper_baskets where title like 'REAL005C1%';
delete from review_queue_items
where payload::text like '%real005c1_search_paper_export_smoke%'
   or payload::text like '%real005c2_analysis_reference_smoke%';
delete from assessments
where title='REAL005C2 reviewed real question analysis smoke'
  and synthetic_fixture=true;
delete from score_import_templates where template_key like 'real005c2-score-template-v1%';
delete from knowledge_mappings
where knowledge_node_id in (select id from knowledge_nodes where code like 'REAL005C%');
delete from knowledge_nodes where code like 'REAL005C%';
commit;
'@
}

$after = Invoke-Counts
$v2After = Invoke-V2Invariants
if ($Apply) {
    foreach ($property in $after.GetEnumerator()) {
        if ($property.Value -ne 0) { throw "REAL005C residue remains after cleanup: $($property.Key)=$($property.Value)" }
    }
}
foreach ($propertyName in @('total','pendingReview','primaryKnowledgeNull','productionEligibleFalse','openReviews')) {
    if ($v2Before[$propertyName] -ne 234 -or $v2After[$propertyName] -ne 234) {
        throw "Guangzhou v2 invariant failed: $propertyName"
    }
}

$report = [ordered]@{
    status = 'pass'
    mode = if ($Apply) { 'apply' } else { 'dry_run' }
    checkedAt = (Get-Date).ToString('o')
    backupManifest = (Resolve-Path -LiteralPath $BackupManifest).Path
    backupVerified = $true
    before = $before
    after = $after
    v2Before = $v2Before
    v2After = $v2After
    deletedScope = @('REAL005C temporary knowledge mappings/nodes','REAL005C1 draft baskets','REAL005C2 synthetic assessments and dependent score rows','REAL005C1/C2 review queue audit rows','REAL005C2 temporary import templates')
    preservedScope = @('Guangzhou v2 questions and review queue','source documents and authorization','students','unmarked product data','C002 active state')
    restoreCommand = "pwsh -NoProfile -ExecutionPolicy Bypass -File tools/restore.ps1 -ManifestPath '$((Resolve-Path -LiteralPath $BackupManifest).Path)' -ApplyDatabase -ApplyFileStore -DryRun:`$false"
}
$fullReportPath = Join-Path $repoRoot ($ReportPath -replace '/', '\')
New-Item -ItemType Directory -Path (Split-Path -Parent $fullReportPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $fullReportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8

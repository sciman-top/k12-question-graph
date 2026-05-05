param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/r001-search-semantic-retrieval-eval-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-r001-search-semantic-retrieval-eval-preflight.md'
)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$rows = Import-Csv -LiteralPath (Join-Path $repoRoot $BacklogPath) -Encoding UTF8
$byId=@{}; foreach($r in $rows){$byId[$r.id]=$r}
foreach($id in @('P006','R001')){ Assert-True ($byId.ContainsKey($id)) "R001 prerequisite task missing: $id" }
$p006=$byId['P006']; $r001=$byId['R001']
Assert-True ($r001.depends_on -eq 'P006') 'R001 must depend on P006'
Assert-True ($p006.status -eq '待办') 'P006 still pending; R001 must remain todo before release decision closes'
Assert-True ($r001.status -eq '待办') 'R001 must remain todo until FTS benchmark + ADR evidence is completed'
$checklist = Get-Content -LiteralPath (Join-Path $repoRoot $ChecklistPath) -Raw
foreach($k in @('PostgreSQL FTS','pgvector','benchmark report','ADR')){ Assert-True ($checklist.Contains($k)) "R001 checklist missing keyword: $k" }
$evidence = Get-Content -LiteralPath (Join-Path $repoRoot $EvidencePath) -Raw
foreach($k in @('preflight','R001','platform_na','gate_na','语义检索','下一步')){ Assert-True ($evidence.Contains($k)) "R001 evidence missing keyword: $k" }
[ordered]@{status='pass';taskId='R001';mode='preflight_only';p006Status=$p006.status;r001Status=$r001.status;checklistPath=$ChecklistPath;evidencePath=$EvidencePath;boundary='search/semantic retrieval evaluation is not executed in this contract; keep R001 as todo until P006 closes and benchmark evidence is complete';checkedAt=(Get-Date).ToString('s')}|ConvertTo-Json -Depth 4


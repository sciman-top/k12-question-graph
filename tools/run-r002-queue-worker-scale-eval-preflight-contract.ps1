param([string] $BacklogPath='tasks/backlog.csv',[string] $ChecklistPath='docs/templates/r002-queue-worker-scale-eval-checklist.md',[string] $EvidencePath='docs/evidence/20260505-r002-queue-worker-scale-eval-preflight.md')
$ErrorActionPreference='Stop'; $repoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
function Assert-True([bool]$Condition,[string]$Message){ if(-not $Condition){ throw $Message } }
$rows=Import-Csv -LiteralPath (Join-Path $repoRoot $BacklogPath) -Encoding UTF8; $byId=@{}; foreach($r in $rows){$byId[$r.id]=$r}
foreach($id in @('P006','R002')){ Assert-True ($byId.ContainsKey($id)) "R002 prerequisite task missing: $id" }
$p006=$byId['P006']; $r002=$byId['R002']
Assert-True ($r002.depends_on -eq 'P006') 'R002 must depend on P006'
Assert-True ($p006.status -eq '待办') 'P006 still pending; R002 must remain todo before release decision closes'
Assert-True ($r002.status -eq '待办') 'R002 must remain todo until queue/worker metrics + ADR evidence is completed'
$checklist=Get-Content -LiteralPath (Join-Path $repoRoot $ChecklistPath) -Raw
foreach($k in @('BackgroundService','Hangfire','RabbitMQ','operational metrics','ADR')){ Assert-True ($checklist.Contains($k)) "R002 checklist missing keyword: $k" }
$evidence=Get-Content -LiteralPath (Join-Path $repoRoot $EvidencePath) -Raw
foreach($k in @('preflight','R002','platform_na','gate_na','Worker 扩展','下一步')){ Assert-True ($evidence.Contains($k)) "R002 evidence missing keyword: $k" }
[ordered]@{status='pass';taskId='R002';mode='preflight_only';p006Status=$p006.status;r002Status=$r002.status;checklistPath=$ChecklistPath;evidencePath=$EvidencePath;boundary='queue/worker scale evaluation is not executed in this contract; keep R002 as todo until P006 closes and metrics evidence is complete';checkedAt=(Get-Date).ToString('s')}|ConvertTo-Json -Depth 4


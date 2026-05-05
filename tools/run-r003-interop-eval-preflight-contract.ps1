param([string] $BacklogPath='tasks/backlog.csv',[string] $ChecklistPath='docs/templates/r003-interop-eval-checklist.md',[string] $EvidencePath='docs/evidence/20260505-r003-interop-eval-preflight.md')
$ErrorActionPreference='Stop'; $repoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
function Assert-True([bool]$Condition,[string]$Message){ if(-not $Condition){ throw $Message } }
$rows=Import-Csv -LiteralPath (Join-Path $repoRoot $BacklogPath) -Encoding UTF8; $byId=@{}; foreach($r in $rows){$byId[$r.id]=$r}
foreach($id in @('P006','R003')){ Assert-True ($byId.ContainsKey($id)) "R003 prerequisite task missing: $id" }
$p006=$byId['P006']; $r003=$byId['R003']
Assert-True ($r003.depends_on -eq 'P006') 'R003 must depend on P006'
Assert-True ($p006.status -eq '待办') 'P006 still pending; R003 must remain todo before release decision closes'
Assert-True ($r003.status -eq '待办') 'R003 must remain todo until interoperability admission evidence is completed'
$checklist=Get-Content -LiteralPath (Join-Path $repoRoot $ChecklistPath) -Raw
foreach($k in @('QTI','CASE','OneRoster','admission card','integration spike')){ Assert-True ($checklist.Contains($k)) "R003 checklist missing keyword: $k" }
$evidence=Get-Content -LiteralPath (Join-Path $repoRoot $EvidencePath) -Raw
foreach($k in @('preflight','R003','platform_na','gate_na','标准互操作','下一步')){ Assert-True ($evidence.Contains($k)) "R003 evidence missing keyword: $k" }
[ordered]@{status='pass';taskId='R003';mode='preflight_only';p006Status=$p006.status;r003Status=$r003.status;checklistPath=$ChecklistPath;evidencePath=$EvidencePath;boundary='interoperability evaluation is not executed in this contract; keep R003 as todo until P006 closes and admission evidence is complete';checkedAt=(Get-Date).ToString('s')}|ConvertTo-Json -Depth 4


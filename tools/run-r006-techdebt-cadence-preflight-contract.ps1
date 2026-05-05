param([string] $BacklogPath='tasks/backlog.csv',[string] $ChecklistPath='docs/templates/r006-techdebt-cadence-checklist.md',[string] $EvidencePath='docs/evidence/20260505-r006-techdebt-cadence-preflight.md')
$ErrorActionPreference='Stop'; $repoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
function Assert-True([bool]$Condition,[string]$Message){ if(-not $Condition){ throw $Message } }
$rows=Import-Csv -LiteralPath (Join-Path $repoRoot $BacklogPath) -Encoding UTF8; $byId=@{}; foreach($r in $rows){$byId[$r.id]=$r}
foreach($id in @('P006','R006')){ Assert-True ($byId.ContainsKey($id)) "R006 prerequisite task missing: $id" }
$p006=$byId['P006']; $r006=$byId['R006']
Assert-True ($r006.depends_on -eq 'P006') 'R006 must depend on P006'
Assert-True ($p006.status -eq '待办') 'P006 still pending; R006 must remain todo before release decision closes'
Assert-True ($r006.status -eq '待办') 'R006 must remain todo until quality dashboard/dependency gate cadence evidence is completed'
$checklist=Get-Content -LiteralPath (Join-Path $repoRoot $ChecklistPath) -Raw
foreach($k in @('门禁维护','依赖升级','性能基线','quality dashboard','dependency gate')){ Assert-True ($checklist.Contains($k)) "R006 checklist missing keyword: $k" }
$evidence=Get-Content -LiteralPath (Join-Path $repoRoot $EvidencePath) -Raw
foreach($k in @('preflight','R006','platform_na','gate_na','技术债','下一步')){ Assert-True ($evidence.Contains($k)) "R006 evidence missing keyword: $k" }
[ordered]@{status='pass';taskId='R006';mode='preflight_only';p006Status=$p006.status;r006Status=$r006.status;checklistPath=$ChecklistPath;evidencePath=$EvidencePath;boundary='long-term tech-debt cadence is not executed in this contract; keep R006 as todo until P006 closes and cadence evidence is complete';checkedAt=(Get-Date).ToString('s')}|ConvertTo-Json -Depth 4


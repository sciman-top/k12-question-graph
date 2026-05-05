param([string] $BacklogPath='tasks/backlog.csv',[string] $ChecklistPath='docs/templates/r004-advanced-analysis-eval-checklist.md',[string] $EvidencePath='docs/evidence/20260505-r004-advanced-analysis-eval-preflight.md')
$ErrorActionPreference='Stop'; $repoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
function Assert-True([bool]$Condition,[string]$Message){ if(-not $Condition){ throw $Message } }
$rows=Import-Csv -LiteralPath (Join-Path $repoRoot $BacklogPath) -Encoding UTF8; $byId=@{}; foreach($r in $rows){$byId[$r.id]=$r}
foreach($id in @('N004','R004')){ Assert-True ($byId.ContainsKey($id)) "R004 prerequisite task missing: $id" }
$n004=$byId['N004']; $r004=$byId['R004']
Assert-True ($r004.depends_on -eq 'N004') 'R004 must depend on N004'
Assert-True ($n004.status -eq '已完成') 'N004 must be completed before R004 preflight can pass'
Assert-True ($r004.status -eq '待办') 'R004 must remain todo until advanced-analysis research/admission evidence is completed'
$checklist=Get-Content -LiteralPath (Join-Path $repoRoot $ChecklistPath) -Raw
foreach($k in @('IRT','等值','样本量','解释责任边界','feature admission')){ Assert-True ($checklist.Contains($k)) "R004 checklist missing keyword: $k" }
$evidence=Get-Content -LiteralPath (Join-Path $repoRoot $EvidencePath) -Raw
foreach($k in @('preflight','R004','platform_na','gate_na','高级分析','下一步')){ Assert-True ($evidence.Contains($k)) "R004 evidence missing keyword: $k" }
[ordered]@{status='pass';taskId='R004';mode='preflight_only';n004Status=$n004.status;r004Status=$r004.status;checklistPath=$ChecklistPath;evidencePath=$EvidencePath;boundary='advanced-analysis evaluation is not executed in this contract; keep R004 as todo until sufficient sample and admission evidence is complete';checkedAt=(Get-Date).ToString('s')}|ConvertTo-Json -Depth 4


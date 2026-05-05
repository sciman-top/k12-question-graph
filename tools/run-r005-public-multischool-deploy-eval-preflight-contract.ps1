param([string] $BacklogPath='tasks/backlog.csv',[string] $ChecklistPath='docs/templates/r005-public-multischool-deploy-eval-checklist.md',[string] $EvidencePath='docs/evidence/20260505-r005-public-multischool-deploy-eval-preflight.md')
$ErrorActionPreference='Stop'; $repoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
function Assert-True([bool]$Condition,[string]$Message){ if(-not $Condition){ throw $Message } }
$rows=Import-Csv -LiteralPath (Join-Path $repoRoot $BacklogPath) -Encoding UTF8; $byId=@{}; foreach($r in $rows){$byId[$r.id]=$r}
foreach($id in @('P006','R005')){ Assert-True ($byId.ContainsKey($id)) "R005 prerequisite task missing: $id" }
$p006=$byId['P006']; $r005=$byId['R005']
Assert-True ($r005.depends_on -eq 'P006') 'R005 must depend on P006'
Assert-True ($p006.status -eq '待办') 'P006 still pending; R005 must remain todo before release decision closes'
Assert-True ($r005.status -eq '待办') 'R005 must remain todo until public/multischool security privacy ADR evidence is completed'
$checklist=Get-Content -LiteralPath (Join-Path $repoRoot $ChecklistPath) -Raw
foreach($k in @('SaaS','多租户','security privacy ADR','采购','运维边界')){ Assert-True ($checklist.Contains($k)) "R005 checklist missing keyword: $k" }
$evidence=Get-Content -LiteralPath (Join-Path $repoRoot $EvidencePath) -Raw
foreach($k in @('preflight','R005','platform_na','gate_na','公网','下一步')){ Assert-True ($evidence.Contains($k)) "R005 evidence missing keyword: $k" }
[ordered]@{status='pass';taskId='R005';mode='preflight_only';p006Status=$p006.status;r005Status=$r005.status;checklistPath=$ChecklistPath;evidencePath=$EvidencePath;boundary='public/multi-school deployment evaluation is not executed in this contract; keep R005 as todo until P006 closes and ADR evidence is complete';checkedAt=(Get-Date).ToString('s')}|ConvertTo-Json -Depth 4


param([string] $BacklogPath='tasks/backlog.csv',[string] $ChecklistPath='docs/templates/r007-interoperability-profile-map-checklist.md',[string] $EvidencePath='docs/evidence/20260505-r007-interoperability-profile-map-preflight.md')
$ErrorActionPreference='Stop'; $repoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
function Assert-True([bool]$Condition,[string]$Message){ if(-not $Condition){ throw $Message } }
$rows=Import-Csv -LiteralPath (Join-Path $repoRoot $BacklogPath) -Encoding UTF8; $byId=@{}; foreach($r in $rows){$byId[$r.id]=$r}
foreach($id in @('P006','R007')){ Assert-True ($byId.ContainsKey($id)) "R007 prerequisite task missing: $id" }
$p006=$byId['P006']; $r007=$byId['R007']
Assert-True ($r007.depends_on -eq 'P006') 'R007 must depend on P006'
Assert-True ($p006.status -eq '待办') 'P006 still pending; R007 must remain todo before release decision closes'
Assert-True ($r007.status -eq '待办') 'R007 must remain todo until interoperability profile map evidence is completed'
$checklist=Get-Content -LiteralPath (Join-Path $repoRoot $ChecklistPath) -Raw
foreach($k in @('QuestionItem','QTI','CASE','OneRoster','Caliper','profile map')){ Assert-True ($checklist.Contains($k)) "R007 checklist missing keyword: $k" }
$evidence=Get-Content -LiteralPath (Join-Path $repoRoot $EvidencePath) -Raw
foreach($k in @('preflight','R007','platform_na','gate_na','interoperability profile map','下一步')){ Assert-True ($evidence.Contains($k)) "R007 evidence missing keyword: $k" }
[ordered]@{status='pass';taskId='R007';mode='preflight_only';p006Status=$p006.status;r007Status=$r007.status;checklistPath=$ChecklistPath;evidencePath=$EvidencePath;boundary='interoperability profile map is not executed in this contract; keep R007 as todo until P006 closes and profile evidence is complete';checkedAt=(Get-Date).ToString('s')}|ConvertTo-Json -Depth 4


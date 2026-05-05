param(
  [string] $F003ReportPath = 'docs\evidence\f003-knowledge-mastery-analysis-report.json',
  [string] $N004EvidencePath = 'docs\evidence\20260505-n004-class-commentary-report-mvp.md'
)
$ErrorActionPreference='Stop'
$repoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
function Assert-True([bool]$c,[string]$m){ if(-not $c){ throw $m } }

$f003=Get-Content -LiteralPath (Join-Path $repoRoot $F003ReportPath) -Raw | ConvertFrom-Json
Assert-True ($f003.status -eq 'pass') 'N004 requires F003 pass'
Assert-True ($f003.noProductionHistoryWrite -eq $true) 'N004 requires no production history write'
Assert-True ($f003.realStudentDataUsed -eq $false) 'N004 requires no real student data'
Assert-True (@($f003.weakKnowledgePoints).Count -ge 1) 'N004 requires weak knowledge point outputs'

$e=Get-Content -LiteralPath (Join-Path $repoRoot $N004EvidencePath) -Raw
foreach($k in @('得分率','区分度','薄弱知识点','讲评建议','不写正式历史口径')){
  Assert-True ($e.Contains($k)) "N004 evidence missing keyword: $k"
}
[ordered]@{status='pass';taskId='N004';f003ReportPath=$F003ReportPath;n004EvidencePath=$N004EvidencePath;checkedAt=(Get-Date).ToString('s')}|ConvertTo-Json

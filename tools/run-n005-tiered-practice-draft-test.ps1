param(
  [string] $F003ReportPath = 'docs\evidence\f003-knowledge-mastery-analysis-report.json',
  [string] $N005EvidencePath = 'docs\evidence\20260505-n005-tiered-practice-draft-test.md'
)
$ErrorActionPreference='Stop'
$repoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
function Assert-True([bool]$c,[string]$m){ if(-not $c){ throw $m } }

$f003=Get-Content -LiteralPath (Join-Path $repoRoot $F003ReportPath) -Raw | ConvertFrom-Json
Assert-True ($f003.status -eq 'pass') 'N005 requires F003 pass'
Assert-True ($f003.mode -eq 'draft_test') 'N005 requires draft_test mode'
Assert-True ($f003.productionEligible -eq $false) 'N005 requires non-production outputs'

$e=Get-Content -LiteralPath (Join-Path $repoRoot $N005EvidencePath) -Raw
foreach($k in @('A/B/C','教师自定义分层','draft/test','人工确认','no production write')){
  Assert-True ($e.Contains($k)) "N005 evidence missing keyword: $k"
}
[ordered]@{status='pass';taskId='N005';f003ReportPath=$F003ReportPath;n005EvidencePath=$N005EvidencePath;checkedAt=(Get-Date).ToString('s')}|ConvertTo-Json

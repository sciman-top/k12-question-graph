param(
  [string] $N006EvidencePath = 'docs\evidence\20260505-n006-pre-pilot-security-audit.md'
)
$ErrorActionPreference='Stop'
$repoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
function Assert-True([bool]$c,[string]$m){ if(-not $c){ throw $m } }

$scanTargets=@(
  'docs\evidence\f002-score-import-report.json',
  'docs\evidence\f003-knowledge-mastery-analysis-report.json',
  'docs\evidence\20260505-n001-real-privacy-boundary-admission.md',
  'docs\evidence\20260505-n002-excel-template-reuse.md',
  'docs\evidence\20260505-n003-item-score-mapping-workbench.md',
  'docs\evidence\20260505-n004-class-commentary-report-mvp.md',
  'docs\evidence\20260505-n005-tiered-practice-draft-test.md',
  'docs\evidence\20260505-n006-pre-pilot-security-audit.md'
)

$forbidden=@('sk-','api_key=','apikey=','password=','真实学生姓名','学号:','身份证')
foreach($p in $scanTargets){
  $fp=Join-Path $repoRoot $p
  Assert-True (Test-Path -LiteralPath $fp) "N006 scan target missing: $p"
  $txt=Get-Content -LiteralPath $fp -Raw
  foreach($f in $forbidden){
    Assert-True (-not $txt.ToLower().Contains($f.ToLower())) "N006 found forbidden token '$f' in $p"
  }
}

$e=Get-Content -LiteralPath (Join-Path $repoRoot $N006EvidencePath) -Raw
foreach($k in @('日志','prompt','备份','fixture','无真实学生 PII','无 API key')){
  Assert-True ($e.Contains($k)) "N006 evidence missing keyword: $k"
}
[ordered]@{status='pass';taskId='N006';scannedFiles=$scanTargets.Count;checkedAt=(Get-Date).ToString('s')}|ConvertTo-Json

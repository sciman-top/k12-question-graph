param(
  [string] $F002ReportPath = 'docs\evidence\f002-score-import-report.json',
  [string] $M001EvidencePath = 'docs\evidence\20260505-m001-paper-basket-structure-contract.md',
  [string] $N003EvidencePath = 'docs\evidence\20260505-n003-item-score-mapping-workbench.md'
)
$ErrorActionPreference='Stop'
$repoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
function Assert-True([bool]$c,[string]$m){ if(-not $c){ throw $m } }

$f002=Get-Content -LiteralPath (Join-Path $repoRoot $F002ReportPath) -Raw | ConvertFrom-Json
Assert-True ($f002.status -eq 'pass') 'N003 requires F002 pass'
Assert-True ($f002.errorCount -ge 1) 'N003 requires centralized error prompts'
$m001=Get-Content -LiteralPath (Join-Path $repoRoot $M001EvidencePath) -Raw
Assert-True ($m001.Contains('版本引用可保存和复现')) 'N003 requires M001 version-reference anchor'

$e=Get-Content -LiteralPath (Join-Path $repoRoot $N003EvidencePath) -Raw
foreach($k in @('小题分映射到题目和知识点','映射不清时集中提示','synthetic fixture')){
  Assert-True ($e.Contains($k)) "N003 evidence missing keyword: $k"
}
[ordered]@{status='pass';taskId='N003';f002ReportPath=$F002ReportPath;n003EvidencePath=$N003EvidencePath;checkedAt=(Get-Date).ToString('s')}|ConvertTo-Json

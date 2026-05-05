param(
    [string] $H003EvidencePath = 'docs\evidence\20260504-h003-teacher-efficiency-baseline.md',
    [string] $M006EvidencePath = 'docs\evidence\20260505-m006-ten-minute-paper-workflow-acceptance.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
function Assert-True([bool]$c,[string]$m){ if(-not $c){ throw $m } }

$h003 = Get-Content -LiteralPath (Join-Path $repoRoot $H003EvidencePath) -Raw
Assert-True ($h003.Contains('10 分钟')) 'M006 requires teacher-efficiency baseline with 10-minute target'

$e = Get-Content -LiteralPath (Join-Path $repoRoot $M006EvidencePath) -Raw
foreach($k in @('自然语言需求','可打印导出','小于等于 10 分钟','阻断项','teacher-efficiency evidence','hotspot')){
  Assert-True ($e.Contains($k)) "M006 evidence missing keyword: $k"
}

[ordered]@{
  status='pass'; taskId='M006'; h003EvidencePath=$H003EvidencePath; m006EvidencePath=$M006EvidencePath; checkedAt=(Get-Date).ToString('s')
}|ConvertTo-Json

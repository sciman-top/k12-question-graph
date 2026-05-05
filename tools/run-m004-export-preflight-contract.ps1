param(
    [string] $M004EvidencePath = 'docs\evidence\20260505-m004-export-preflight-contract.md',
    [string] $AppPath = 'apps\web\src\App.tsx'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
function Assert-True([bool]$c,[string]$m){ if(-not $c){ throw $m } }

$app = Get-Content -LiteralPath (Join-Path $repoRoot $AppPath) -Raw
foreach($marker in @('导出','答案','解析','题图','版本')){
  Assert-True ($app.Contains($marker)) "M004 app marker missing: $marker"
}

$e = Get-Content -LiteralPath (Join-Path $repoRoot $M004EvidencePath) -Raw
foreach($k in @('导出前显示版本','题号','答案','解析','题图缺失','授权风险')){
  Assert-True ($e.Contains($k)) "M004 evidence missing keyword: $k"
}

[ordered]@{
  status='pass'; taskId='M004'; appPath=$AppPath; m004EvidencePath=$M004EvidencePath; checkedAt=(Get-Date).ToString('s')
}|ConvertTo-Json

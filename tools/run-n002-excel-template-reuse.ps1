param(
  [string] $F002ReportPath = 'docs\evidence\f002-score-import-report.json',
  [string] $N002EvidencePath = 'docs\evidence\20260505-n002-excel-template-reuse.md'
)
$ErrorActionPreference='Stop'
$repoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
function Assert-True([bool]$c,[string]$m){ if(-not $c){ throw $m } }

$f002=Get-Content -LiteralPath (Join-Path $repoRoot $F002ReportPath) -Raw | ConvertFrom-Json
Assert-True ($f002.status -eq 'pass') 'N002 requires F002 pass'
Assert-True ($f002.templateReusable -eq $true) 'N002 requires reusable field mapping template'
Assert-True ($f002.errorCount -ge 1) 'N002 requires centralized abnormal rows handling evidence'

$e=Get-Content -LiteralPath (Join-Path $repoRoot $N002EvidencePath) -Raw
foreach($k in @('二次导入自动复用字段映射','仅异常行需要处理','templateReusable=true')){
  Assert-True ($e.Contains($k)) "N002 evidence missing keyword: $k"
}
[ordered]@{status='pass';taskId='N002';f002ReportPath=$F002ReportPath;n002EvidencePath=$N002EvidencePath;checkedAt=(Get-Date).ToString('s')}|ConvertTo-Json

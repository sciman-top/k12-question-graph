param(
    [string] $E004ReportPath = 'docs\evidence\e004-paper-export-report.json',
    [string] $M005EvidencePath = 'docs\evidence\20260505-m005-export-regression-extended.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
function Assert-True([bool]$c,[string]$m){ if(-not $c){ throw $m } }

$e004 = Get-Content -LiteralPath (Join-Path $repoRoot $E004ReportPath) -Raw | ConvertFrom-Json
Assert-True ($e004.status -eq 'pass') 'M005 requires E004 report pass'
Assert-True ($e004.docxChecks.hasFormulaText -eq $true) 'M005 requires formula regression pass'
Assert-True ($e004.docxChecks.hasFigureMedia -eq $true) 'M005 requires figure regression pass'
Assert-True ($e004.docxChecks.hasTable -eq $true) 'M005 requires table regression pass'

$e = Get-Content -LiteralPath (Join-Path $repoRoot $M005EvidencePath) -Raw
foreach($k in @('学生版','教师版','答案版','Word WPS PDF','公式','题图','表格不丢')){
  Assert-True ($e.Contains($k)) "M005 evidence missing keyword: $k"
}

[ordered]@{
  status='pass'; taskId='M005'; e004ReportPath=$E004ReportPath; m005EvidencePath=$M005EvidencePath; checkedAt=(Get-Date).ToString('s')
}|ConvertTo-Json

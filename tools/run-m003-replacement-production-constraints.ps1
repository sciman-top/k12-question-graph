param(
    [string] $E003ContractPath = 'tools\run-e003-question-replacement-contract.ps1',
    [string] $M003EvidencePath = 'docs\evidence\20260505-m003-replacement-production-constraints.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
function Assert-True([bool]$c,[string]$m){ if(-not $c){ throw $m } }

Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot $E003ContractPath)) 'M003 requires E003 contract entrypoint'
$e = Get-Content -LiteralPath (Join-Path $repoRoot $M003EvidencePath) -Raw
foreach($k in @('换题保持知识点','题型','难度','分值','近期未用','不重复','可撤销')){
  Assert-True ($e.Contains($k)) "M003 evidence missing keyword: $k"
}

[ordered]@{
  status='pass'; taskId='M003'; e003ContractPath=$E003ContractPath; m003EvidencePath=$M003EvidencePath; checkedAt=(Get-Date).ToString('s')
}|ConvertTo-Json

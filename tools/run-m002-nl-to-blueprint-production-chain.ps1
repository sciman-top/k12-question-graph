param(
    [string] $E002ContractPath = 'tools\run-e002-paper-request-contract.ps1',
    [string] $L001EvidencePath = 'docs\evidence\20260505-l001-real-model-admission-card.md',
    [string] $M002EvidencePath = 'docs\evidence\20260505-m002-nl-to-blueprint-production-chain.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
function Assert-True([bool]$c,[string]$m){ if(-not $c){ throw $m } }

Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot $E002ContractPath)) 'M002 requires E002 contract entrypoint'
$l001 = Get-Content -LiteralPath (Join-Path $repoRoot $L001EvidencePath) -Raw
Assert-True (($l001.Contains('no active write')) -or ($l001.Contains('noActiveWrite=true'))) 'M002 requires L001 no-active-write boundary'

$e = Get-Content -LiteralPath (Join-Path $repoRoot $M002EvidencePath) -Raw
foreach($k in @('自然语言','可审查细目表','不直接生成不可解释试卷','pending_review','未进入 active')){
  Assert-True ($e.Contains($k)) "M002 evidence missing keyword: $k"
}

[ordered]@{
  status='pass'; taskId='M002'; e002ContractPath=$E002ContractPath; l001EvidencePath=$L001EvidencePath; m002EvidencePath=$M002EvidencePath; checkedAt=(Get-Date).ToString('s')
}|ConvertTo-Json

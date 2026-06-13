param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

$gateGroupPath = Join-Path $repoRoot 'tools\run-gate-group.ps1'
Assert-True (Test-Path -LiteralPath $gateGroupPath) 'run-gate-group.ps1 is missing'

$scriptText = Get-Content -LiteralPath $gateGroupPath -Raw

Assert-True ($scriptText.Contains("`$reportRoot = 'tmp/gate-group-pqr'")) 'pqr group must use tmp/gate-group-pqr as report root'
Assert-True ($scriptText.Contains("New-Item -ItemType Directory -Path (Join-Path `$repoRoot `$reportRoot) -Force | Out-Null")) 'pqr group must create tmp/gate-group-pqr before writing reports'
Assert-True ($scriptText.Contains('run-pqr-preflight-pack-contract.ps1')) 'pqr group must include pack contract'
Assert-True ($scriptText.Contains('run-pqr-preflight-freshness-guard.ps1')) 'pqr group must include freshness guard'
Assert-True ($scriptText.Contains('run-pqr-preflight-dashboard-contract.ps1')) 'pqr group must include dashboard contract'
Assert-True ($scriptText.Contains('run-pqr-orchestration-consistency-guard.ps1')) 'pqr group must include orchestration guard'

Assert-True ($scriptText.Contains("Join-Path `$reportRoot 'pqr-preflight-pack-report.json'")) 'pqr pack contract must write to tmp/gate-group-pqr'
Assert-True ($scriptText.Contains("Join-Path `$reportRoot 'pqr-preflight-freshness-report.json'")) 'pqr freshness guard must write to tmp/gate-group-pqr'
Assert-True ($scriptText.Contains("Join-Path `$reportRoot 'pqr-preflight-dashboard.json'")) 'pqr dashboard contract must write JSON to tmp/gate-group-pqr'
Assert-True ($scriptText.Contains("Join-Path `$reportRoot 'pqr-preflight-dashboard.md'")) 'pqr dashboard contract must write markdown to tmp/gate-group-pqr'
Assert-True ($scriptText.Contains("Join-Path `$reportRoot 'pqr-orchestration-consistency-report.json'")) 'pqr orchestration guard must write to tmp/gate-group-pqr'

[ordered]@{
    status = 'pass'
    taskId = 'PQR_GATE_GROUP_PATH_CONTRACT'
    checkedAt = (Get-Date).ToString('s')
    guardedScript = 'tools/run-gate-group.ps1'
    boundary = 'guards the pqr gate-group entrypoint from mutating historical docs/evidence report files'
} | ConvertTo-Json -Depth 5

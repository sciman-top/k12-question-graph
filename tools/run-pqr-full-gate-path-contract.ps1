param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

$gateScriptPath = Join-Path $repoRoot 'tools\run-gates.ps1'
Assert-True (Test-Path -LiteralPath $gateScriptPath) 'run-gates.ps1 is missing'

$scriptText = Get-Content -LiteralPath $gateScriptPath -Raw

Assert-True ($scriptText.Contains("$pqrReportRoot = 'tmp/full-gate-pqr'")) 'full gate must use tmp/full-gate-pqr as PQR report root'
Assert-True ($scriptText.Contains("New-Item -ItemType Directory -Path (Join-Path `$repoRoot `$pqrReportRoot) -Force | Out-Null")) 'full gate must create tmp/full-gate-pqr before PQR writes'
Assert-True ($scriptText.Contains("Join-Path `$pqrReportRoot 'pqr-preflight-pack-report.json'")) 'full gate PQR pack must write to tmp/full-gate-pqr'
Assert-True ($scriptText.Contains("Join-Path `$pqrReportRoot 'pqr-preflight-freshness-report.json'")) 'full gate PQR freshness must write to tmp/full-gate-pqr'
Assert-True ($scriptText.Contains("Join-Path `$pqrReportRoot 'pqr-preflight-dashboard.json'")) 'full gate PQR dashboard JSON must write to tmp/full-gate-pqr'
Assert-True ($scriptText.Contains("Join-Path `$pqrReportRoot 'pqr-preflight-dashboard.md'")) 'full gate PQR dashboard markdown must write to tmp/full-gate-pqr'
Assert-True ($scriptText.Contains("Join-Path `$pqrReportRoot 'pqr-orchestration-consistency-report.json'")) 'full gate PQR orchestration report must write to tmp/full-gate-pqr'
Assert-True ($scriptText.Contains("Join-Path `$pqrReportRoot 'real005-closure-standard-report.json'")) 'full gate REAL005 slice coverage JSON must write to tmp/full-gate-pqr'
Assert-True ($scriptText.Contains("Join-Path `$pqrReportRoot 'real005-closure-standard-report.md'")) 'full gate REAL005 slice coverage markdown must write to tmp/full-gate-pqr'

[ordered]@{
    status = 'pass'
    taskId = 'PQR_FULL_GATE_PATH_CONTRACT'
    checkedAt = (Get-Date).ToString('s')
    guardedScript = 'tools/run-gates.ps1'
    boundary = 'guards the full gate from mutating historical PQR and REAL005 self-check evidence files during repo-side reporting'
} | ConvertTo-Json -Depth 5

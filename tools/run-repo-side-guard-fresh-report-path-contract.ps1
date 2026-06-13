param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

foreach ($relativePath in @(
    'tools/run-real005-guangzhou-2015-2025-closure-standard.ps1',
    'tools/run-live-pilot-closeout-plan-guard.ps1',
    'tools/run-reference-basis-guard.ps1',
    'tools/run-ns905-status-sync-audit.ps1'
)) {
    $fullPath = Join-Path $repoRoot $relativePath
    Assert-True (Test-Path -LiteralPath $fullPath) "missing guard script: $relativePath"

    $scriptText = Get-Content -LiteralPath $fullPath -Raw
    Assert-True ($scriptText.Contains("`$runDate = Get-Date -Format 'yyyyMMdd'")) "$relativePath must derive a fresh yyyyMMdd run date"
    Assert-True ($scriptText.Contains("if ([string]::IsNullOrWhiteSpace(`$")) "$relativePath must fill report paths only when caller does not pass them"
}

Assert-True ((Get-Content -LiteralPath (Join-Path $repoRoot 'tools/run-real005-guangzhou-2015-2025-closure-standard.ps1') -Raw).Contains("docs/evidence/{0}-real005-guangzhou-2015-2025-closure-standard-report.json")) 'REAL005 guard must use date-scoped default JSON report path'
Assert-True ((Get-Content -LiteralPath (Join-Path $repoRoot 'tools/run-real005-guangzhou-2015-2025-closure-standard.ps1') -Raw).Contains("docs/evidence/{0}-real005-guangzhou-2015-2025-closure-standard-report.md")) 'REAL005 guard must use date-scoped default markdown report path'
Assert-True ((Get-Content -LiteralPath (Join-Path $repoRoot 'tools/run-live-pilot-closeout-plan-guard.ps1') -Raw).Contains("docs/evidence/{0}-live-pilot-closeout-plan-guard.json")) 'live closeout guard must use date-scoped default JSON report path'
Assert-True ((Get-Content -LiteralPath (Join-Path $repoRoot 'tools/run-live-pilot-closeout-plan-guard.ps1') -Raw).Contains("docs/evidence/{0}-live-pilot-closeout-plan-guard.md")) 'live closeout guard must use date-scoped default markdown report path'
Assert-True ((Get-Content -LiteralPath (Join-Path $repoRoot 'tools/run-reference-basis-guard.ps1') -Raw).Contains("docs/evidence/{0}-reference-basis-guard.json")) 'reference-basis guard must use date-scoped default JSON report path'
Assert-True ((Get-Content -LiteralPath (Join-Path $repoRoot 'tools/run-reference-basis-guard.ps1') -Raw).Contains("docs/evidence/{0}-reference-basis-guard.md")) 'reference-basis guard must use date-scoped default markdown report path'
Assert-True ((Get-Content -LiteralPath (Join-Path $repoRoot 'tools/run-ns905-status-sync-audit.ps1') -Raw).Contains("docs/evidence/{0}-ns905-status-sync.md")) 'NS905 audit must use date-scoped default report path'

[ordered]@{
    status = 'pass'
    taskId = 'REPO_SIDE_GUARD_FRESH_REPORT_PATH_CONTRACT'
    checkedAt = (Get-Date).ToString('s')
    guardedScripts = @(
        'tools/run-real005-guangzhou-2015-2025-closure-standard.ps1',
        'tools/run-live-pilot-closeout-plan-guard.ps1',
        'tools/run-reference-basis-guard.ps1',
        'tools/run-ns905-status-sync-audit.ps1'
    )
    boundary = 'guards repo-side truth-maintenance scripts from mutating historical evidence files when invoked without explicit output paths'
} | ConvertTo-Json -Depth 5

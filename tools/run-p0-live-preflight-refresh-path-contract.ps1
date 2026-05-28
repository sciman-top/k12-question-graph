param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$refreshScriptPath = Join-Path $repoRoot 'tools\run-p0-live-preflight-refresh.ps1'
Assert-True (Test-Path -LiteralPath $refreshScriptPath) 'P0-live preflight refresh script is missing'

$scriptText = Get-Content -LiteralPath $refreshScriptPath -Raw
$expectedReportTemplates = @(
    'docs/evidence/{0}-p001-live-pilot-readiness-preflight-report.json',
    'docs/evidence/{0}-p002-teacher-proxy-pilot-admission-report.json',
    'docs/evidence/{0}-p003-onsite-pilot-admission-report.json',
    'docs/evidence/{0}-p004-onsite-pilot-round1-report.json',
    'docs/evidence/{0}-p005-pilot-feedback-backlog-admission-report.json',
    'docs/evidence/{0}-p006-release-decision-admission-report.json'
)

foreach ($template in $expectedReportTemplates) {
    Assert-True ($scriptText.Contains($template)) "missing date-scoped report template: $template"
}

Assert-True ($scriptText.Contains('-ReportPath')) 'P0-live refresh must pass explicit ReportPath to each P001-P006 contract'
Assert-True ($scriptText.Contains('Get-Date -Format ''yyyyMMdd''')) 'P0-live refresh must derive a date stamp for fresh evidence'
Assert-True (-not $scriptText.Contains('[string[]]$Args')) 'P0-live refresh must not name forwarded script arguments Args because it collides with PowerShell automatic args'
Assert-True ($scriptText.Contains('ScriptArgs')) 'P0-live refresh must use an explicit ScriptArgs variable when forwarding child script parameters'

foreach ($relativePath in @('tools\run-p0-live-auto-advance.ps1', 'tools\run-p0-live-skip-advance.ps1')) {
    $runnerPath = Join-Path $repoRoot $relativePath
    Assert-True (Test-Path -LiteralPath $runnerPath) "P0-live runner is missing: $relativePath"
    $runnerText = Get-Content -LiteralPath $runnerPath -Raw
    Assert-True (-not $runnerText.Contains('[string[]]$Args')) "P0-live runner must avoid Args forwarding collision: $relativePath"
}

$skipRunnerPath = Join-Path $repoRoot 'tools\run-p0-live-skip-advance.ps1'
$skipRunnerText = Get-Content -LiteralPath $skipRunnerPath -Raw
Assert-True ($skipRunnerText.Contains('$runDate = Get-Date -Format ''yyyyMMdd''')) 'P0-live skip runner must derive the same date stamp as refresh/auto-advance'
Assert-True ($skipRunnerText.Contains("('docs/evidence/{0}-p0-live-auto-advance-report.json' -f `$runDate)")) 'P0-live skip runner must link the current-date auto-advance report'
Assert-True ($skipRunnerText.Contains("('docs/evidence/{0}-p0-live-preflight-refresh-report.json' -f `$runDate)")) 'P0-live skip runner must link the current-date preflight refresh report'
Assert-True ($skipRunnerText.Contains('docs/evidence/20260505-pqr-preflight-dashboard-report.json')) 'P0-live skip runner must link the real PQR dashboard report path'
Assert-True (-not $skipRunnerText.Contains('docs/evidence/20260505-pqr-preflight-dashboard.json')) 'P0-live skip runner must not link the stale dashboard path'

$fullGatePath = Join-Path $repoRoot 'tools\run-gates.ps1'
Assert-True (Test-Path -LiteralPath $fullGatePath) 'full gate script is missing: tools\run-gates.ps1'
$fullGateText = Get-Content -LiteralPath $fullGatePath -Raw
Assert-True ($fullGateText.Contains('$p0LiveRunDate = Get-Date -Format ''yyyyMMdd''')) 'full gate must derive a date stamp for fresh P0-live reports'
Assert-True ($fullGateText.Contains('-ReportPath')) 'full gate must pass explicit ReportPath to each P001-P006 contract'
foreach ($template in $expectedReportTemplates) {
    Assert-True ($fullGateText.Contains($template)) "full gate missing date-scoped report template: $template"
}

foreach ($relativePath in @('tools\run-gate-group.ps1', 'tools\run-gates.ps1')) {
    $gatePath = Join-Path $repoRoot $relativePath
    Assert-True (Test-Path -LiteralPath $gatePath) "gate script is missing: $relativePath"
    $gateText = Get-Content -LiteralPath $gatePath -Raw
    Assert-True ($gateText.Contains('run-p0-live-preflight-refresh-path-contract.ps1')) "P0-live refresh path contract must be wired into gate script: $relativePath"
}

[ordered]@{
    status = 'pass'
    taskId = 'P0LIVE_REFRESH_PATH_CONTRACT'
    checkedAt = (Get-Date).ToString('s')
    guardedScript = 'tools/run-p0-live-preflight-refresh.ps1'
    guardedReportTemplates = $expectedReportTemplates
    boundary = 'guards fresh P0-live preflight refresh reports from mutating older date-stamped evidence files'
} | ConvertTo-Json -Depth 5

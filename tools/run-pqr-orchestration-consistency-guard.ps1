param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $GateScriptPath = 'tools/run-gates.ps1',
    [string] $ReportPath = 'docs/evidence/20260505-pqr-orchestration-consistency-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Write-ContentIfChanged([string]$Path, [string]$Content) {
    if (Test-Path -LiteralPath $Path) {
        $existing = Get-Content -LiteralPath $Path -Raw
        if ($existing -eq $Content) { return }
    }
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

$backlogRows = Import-Csv -LiteralPath (Join-Path $repoRoot $BacklogPath) -Encoding UTF8
$gateScriptText = Get-Content -LiteralPath (Join-Path $repoRoot $GateScriptPath) -Raw
$gateScriptNormalized = $gateScriptText.ToLower().Replace('\', '/')

$targets = $backlogRows | Where-Object { $_.id -match '^(P00[1-6]|Q00[1-5]|R00[1-7])$' }
Assert-True ($targets.Count -eq 18) 'PQR orchestration guard expects 18 targets'

$issues = New-Object System.Collections.Generic.List[object]
foreach ($row in $targets) {
    $parts = @($row.verification -split '\+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($parts.Count -lt 1) {
        $issues.Add([ordered]@{ id = $row.id; issue = 'verification missing contract path' })
        continue
    }
    $contractPath = $parts[0]
    if (-not $contractPath.EndsWith('.ps1')) {
        $issues.Add([ordered]@{ id = $row.id; issue = "verification first token is not ps1 contract: $contractPath" })
        continue
    }
    $normalizedContractPath = $contractPath.ToLower().Replace('\', '/')
    if (-not $gateScriptNormalized.Contains($normalizedContractPath)) {
        $issues.Add([ordered]@{ id = $row.id; issue = "contract not orchestrated in run-gates: $contractPath" })
    }
}

foreach ($guard in @(
    'tools/run-repo-side-guard-fresh-report-path-contract.ps1',
    'tools/run-live-pilot-closeout-import-contract.ps1',
    'tools/run-real005-report-write-lock-contract.ps1',
    'tools/run-real005-slice-coverage-contract.ps1',
    'tools/run-pqr-preflight-pack-contract.ps1',
    'tools/run-pqr-preflight-freshness-guard.ps1',
    'tools/run-pqr-preflight-dashboard-contract.ps1',
    'tools/run-repo-preflight-local-api-detection-contract.ps1'
)) {
    $guardNormalized = $guard.ToLower().Replace('\', '/')
    if (-not $gateScriptNormalized.Contains($guardNormalized)) {
        $issues.Add([ordered]@{ id = 'PQR'; issue = "missing orchestration guard step: $guard" })
    }
}

Assert-True ($issues.Count -eq 0) ("PQR orchestration consistency failed: " + ($issues | ConvertTo-Json -Depth 5 -Compress))

$report = [ordered]@{
    status = 'pass'
    task = 'PQR orchestration consistency guard'
    checkedDate = (Get-Date).ToString('yyyy-MM-dd')
    targetCount = $targets.Count
    gateScript = $GateScriptPath
    report = $ReportPath
}
$reportFullPath = Join-Path $repoRoot $ReportPath
$reportJson = $report | ConvertTo-Json -Depth 4
Write-ContentIfChanged -Path $reportFullPath -Content $reportJson
$report | ConvertTo-Json -Depth 4

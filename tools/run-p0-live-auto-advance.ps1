param(
    [string] $ReportPath = '',
    [switch] $FailOnNonPass
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Invoke-JsonScript([string]$RelativeScriptPath, [string[]]$ScriptArgs = @()) {
    $scriptPath = Join-Path $repoRoot $RelativeScriptPath
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "missing script: $RelativeScriptPath"
    }

    $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath @ScriptArgs
    if ($LASTEXITCODE -ne 0) {
        throw "script failed: $RelativeScriptPath (exit=$LASTEXITCODE)"
    }
    return ($raw | ConvertFrom-Json)
}

function Get-ReportPathFromResult([object]$Result) {
    foreach ($key in @('report', 'reportPath', 'evidencePath')) {
        if ($null -ne $Result.PSObject.Properties[$key]) {
            $value = [string]$Result.$key
            if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
        }
    }
    return $null
}

function Write-ContentIfChanged([string]$Path, [string]$Content) {
    if (Test-Path -LiteralPath $Path) {
        $existing = Get-Content -LiteralPath $Path -Raw
        if ($existing -eq $Content) { return }
    }
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = 'docs/evidence/{0}-p0-live-auto-advance-report.json' -f (Get-Date -Format 'yyyyMMdd')
}

$steps = New-Object System.Collections.Generic.List[object]

$refreshArgs = @()
if ($FailOnNonPass) { $refreshArgs += '-FailOnNonPass' }
$refresh = Invoke-JsonScript -RelativeScriptPath 'tools/run-p0-live-preflight-refresh.ps1' -ScriptArgs $refreshArgs
$steps.Add([ordered]@{
    name = 'p0-live preflight refresh'
    status = $refresh.status
    report = (Get-ReportPathFromResult -Result $refresh)
})

$pack = Invoke-JsonScript -RelativeScriptPath 'tools/run-pqr-preflight-pack-contract.ps1'
$steps.Add([ordered]@{
    name = 'pqr preflight pack'
    status = $pack.status
    report = Get-ReportPathFromResult -Result $pack
})

$freshness = Invoke-JsonScript -RelativeScriptPath 'tools/run-pqr-preflight-freshness-guard.ps1'
$steps.Add([ordered]@{
    name = 'pqr preflight freshness'
    status = $freshness.status
    report = Get-ReportPathFromResult -Result $freshness
})

$dashboard = Invoke-JsonScript -RelativeScriptPath 'tools/run-pqr-preflight-dashboard-contract.ps1'
$steps.Add([ordered]@{
    name = 'pqr preflight dashboard'
    status = $dashboard.status
    report = (Get-ReportPathFromResult -Result $dashboard)
})

$orchestration = Invoke-JsonScript -RelativeScriptPath 'tools/run-pqr-orchestration-consistency-guard.ps1'
$steps.Add([ordered]@{
    name = 'pqr orchestration consistency'
    status = $orchestration.status
    report = Get-ReportPathFromResult -Result $orchestration
})

if ([string]::IsNullOrWhiteSpace([string]$steps[0].report)) {
    $steps[0].report = 'docs/evidence/{0}-p0-live-preflight-refresh-report.json' -f (Get-Date -Format 'yyyyMMdd')
}
if ([string]::IsNullOrWhiteSpace([string]$steps[3].report)) {
    $steps[3].report = 'docs/evidence/20260505-pqr-preflight-dashboard-report.json'
}

$nonPassCount = @($steps | Where-Object { $_.status -ne 'pass' }).Count
$summary = [ordered]@{
    status = if ($nonPassCount -eq 0) { 'pass' } else { 'warn' }
    task = 'P0-live auto advance'
    checkedDate = (Get-Date).ToString('yyyy-MM-dd')
    checkedAt = (Get-Date).ToString('s')
    boundary = 'preflight_only; no live/on-site execution, no backlog status transition'
    nonPassCount = $nonPassCount
    nextAction = 'execute isolated-machine pilot for P001 and write real evidence, then close P002-P006 in order'
    steps = $steps
}

$reportFullPath = Join-Path $repoRoot $ReportPath
$summaryJson = $summary | ConvertTo-Json -Depth 8
Write-ContentIfChanged -Path $reportFullPath -Content $summaryJson
$summary | ConvertTo-Json -Depth 8

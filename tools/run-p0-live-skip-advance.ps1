param(
    [string] $SkipReason = 'temporarily skip live/on-site pilot execution and continue preflight-only automation',
    [string] $ExpiresAt = '',
    [string] $ReportPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Write-ContentIfChanged([string]$Path, [string]$Content) {
    if (Test-Path -LiteralPath $Path) {
        $existing = Get-Content -LiteralPath $Path -Raw
        if ($existing -eq $Content) { return }
    }
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

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

if ([string]::IsNullOrWhiteSpace($ExpiresAt)) {
    $ExpiresAt = (Get-Date).AddDays(7).ToString('yyyy-MM-dd')
}
$runDate = Get-Date -Format 'yyyyMMdd'
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = 'docs/evidence/{0}-p0-live-skip-advance-report.json' -f $runDate
}

$autoAdvance = Invoke-JsonScript -RelativeScriptPath 'tools/run-p0-live-auto-advance.ps1' -ScriptArgs @('-FailOnNonPass')

$summary = [ordered]@{
    status = if ($autoAdvance.status -eq 'pass') { 'pass' } else { 'warn' }
    task = 'P0-live skip and advance'
    checkedDate = (Get-Date).ToString('yyyy-MM-dd')
    checkedAt = (Get-Date).ToString('s')
    skip = [ordered]@{
        type = 'gate_na'
        scope = @('P001','P002','P003','P004','P005','P006')
        reason = $SkipReason
        alternative_verification = 'tools/run-p0-live-auto-advance.ps1 -FailOnNonPass'
        evidence_link = @(
            ('docs/evidence/{0}-p0-live-auto-advance-report.json' -f $runDate),
            ('docs/evidence/{0}-p0-live-preflight-refresh-report.json' -f $runDate),
            'docs/evidence/20260505-pqr-preflight-pack-report.json',
            'docs/evidence/20260505-pqr-preflight-freshness-report.json',
            'docs/evidence/20260505-pqr-preflight-dashboard-report.json',
            'docs/evidence/20260505-pqr-orchestration-consistency-report.json'
        )
        expires_at = $ExpiresAt
    }
    boundary = 'skip only applies to live/on-site execution evidence; backlog status remains unchanged'
    downstream = [ordered]@{
        qr_preflight = 'kept active'
        live_execution_required_for_closure = $true
    }
    autoAdvanceStatus = $autoAdvance.status
}

$reportFullPath = Join-Path $repoRoot $ReportPath
$summaryJson = $summary | ConvertTo-Json -Depth 8
Write-ContentIfChanged -Path $reportFullPath -Content $summaryJson
$summary | ConvertTo-Json -Depth 8

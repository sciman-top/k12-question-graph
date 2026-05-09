param(
    [string] $ReportPath = '',
    [switch] $FailOnNonPass
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Invoke-JsonContract([string]$RelativeScriptPath) {
    $scriptPath = Join-Path $repoRoot $RelativeScriptPath
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "missing script: $RelativeScriptPath"
    }

    $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath
    if ($LASTEXITCODE -ne 0) {
        throw "script failed: $RelativeScriptPath (exit=$LASTEXITCODE)"
    }
    return ($raw | ConvertFrom-Json)
}

function Write-ContentIfChanged([string]$Path, [string]$Content) {
    if (Test-Path -LiteralPath $Path) {
        $existing = Get-Content -LiteralPath $Path -Raw
        if ($existing -eq $Content) { return }
    }
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = 'docs/evidence/{0}-p0-live-preflight-refresh-report.json' -f (Get-Date -Format 'yyyyMMdd')
}

$contracts = @(
    [ordered]@{ id = 'P001'; path = 'tools/run-p001-live-pilot-readiness-preflight-contract.ps1' },
    [ordered]@{ id = 'P002'; path = 'tools/run-p002-teacher-proxy-pilot-preflight-contract.ps1' },
    [ordered]@{ id = 'P003'; path = 'tools/run-p003-onsite-pilot-admission-preflight-contract.ps1' },
    [ordered]@{ id = 'P004'; path = 'tools/run-p004-onsite-pilot-round1-preflight-contract.ps1' },
    [ordered]@{ id = 'P005'; path = 'tools/run-p005-pilot-feedback-backlog-preflight-contract.ps1' },
    [ordered]@{ id = 'P006'; path = 'tools/run-p006-release-decision-preflight-contract.ps1' }
)

$results = New-Object System.Collections.Generic.List[object]
foreach ($contract in $contracts) {
    $obj = Invoke-JsonContract -RelativeScriptPath $contract.path
    $results.Add([ordered]@{
        id = $contract.id
        script = $contract.path
        status = $obj.status
        mode = $obj.mode
        boundary = $obj.boundary
        checklistPath = $obj.checklistPath
        evidencePath = $obj.evidencePath
        checkedAt = $obj.checkedAt
    })
}

$nonPass = @($results | Where-Object { $_.status -ne 'pass' })
if ($FailOnNonPass -and $nonPass.Count -gt 0) {
    throw ("p0 live preflight refresh has non-pass items: " + (($nonPass | Select-Object -ExpandProperty id) -join ','))
}

$summary = [ordered]@{
    status = if ($nonPass.Count -eq 0) { 'pass' } else { 'warn' }
    task = 'P0-live preflight refresh'
    checkedDate = (Get-Date).ToString('yyyy-MM-dd')
    checkedAt = (Get-Date).ToString('s')
    total = $results.Count
    passCount = (@($results | Where-Object { $_.status -eq 'pass' })).Count
    nonPassCount = $nonPass.Count
    boundary = 'preflight_only; no live pilot execution, no backlog status transition'
    nextAction = 'collect isolated-machine pilot evidence for P001, then execute P002-P006 in sequence'
    results = $results
}

$reportFullPath = Join-Path $repoRoot $ReportPath
$summaryJson = $summary | ConvertTo-Json -Depth 8
Write-ContentIfChanged -Path $reportFullPath -Content $summaryJson

$summary | ConvertTo-Json -Depth 8

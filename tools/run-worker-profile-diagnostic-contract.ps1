param(
    [string] $Report = 'docs\evidence\worker-profile-diagnostic-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

Push-Location $repoRoot
try {
    python tools\worker_profile_diagnostic.py --output $Report | Write-Host
    Assert-Condition ($LASTEXITCODE -eq 0) 'worker profile diagnostic failed'
    Assert-Condition (Test-Path -LiteralPath $Report) "missing worker profile diagnostic report: $Report"

    $json = Get-Content -LiteralPath $Report -Raw | ConvertFrom-Json
    Assert-Condition ($json.schemaVersion -eq 'worker-profile-diagnostic.v1') 'unexpected worker profile diagnostic schemaVersion'
    Assert-Condition ($json.mode -eq 'read_only') 'worker profile diagnostic must be read-only'
    Assert-Condition ([bool]$json.guardrail.noInstallPerformed) 'diagnostic must not install dependencies'
    Assert-Condition ([bool]$json.guardrail.noNetworkRequired) 'diagnostic must not require network'
    Assert-Condition (-not [bool]$json.guardrail.productionDefaultChanged) 'diagnostic must not change production default'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($json.recommendation.recommendedDefaultProfile)) 'missing recommended worker profile'
    Assert-Condition (@('direct_venv_lite','uv_venv_lite','conda_paddle_cpu','wsl_or_docker_heavy') -contains [string]$json.recommendation.recommendedDefaultProfile) 'unexpected recommended worker profile'
    Assert-Condition ([string]$json.guardrail.failClosedPolicy -match 'pending_review') 'fail-closed policy must mention pending_review'

    [ordered]@{
        status = 'pass'
        task = 'worker profile diagnostic contract'
        report = $Report
        recommendedDefaultProfile = [string]$json.recommendation.recommendedDefaultProfile
        availableProfileCandidates = @($json.recommendation.availableProfileCandidates)
        noInstallPerformed = [bool]$json.guardrail.noInstallPerformed
    } | ConvertTo-Json -Depth 5
}
finally {
    Pop-Location
}

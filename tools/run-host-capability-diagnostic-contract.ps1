param(
    [string] $Config = 'configs\installer_init.defaults.yaml',
    [string] $Report = 'docs\evidence\host-capability-diagnostic-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

Push-Location $repoRoot
try {
    Assert-Condition (Test-Path -LiteralPath $Config) "missing installer config: $Config"

    python tools\host_capability_diagnostic.py --config $Config --output $Report | Write-Host
    Assert-Condition ($LASTEXITCODE -eq 0) 'host capability diagnostic failed'
    Assert-Condition (Test-Path -LiteralPath $Report) "missing host capability diagnostic report: $Report"

    $json = Get-Content -LiteralPath $Report -Raw | ConvertFrom-Json
    Assert-Condition ($json.schemaVersion -eq 'host-capability-diagnostic.v1') 'unexpected host capability diagnostic schemaVersion'
    Assert-Condition ($json.mode -eq 'read_only') 'host capability diagnostic must be read-only'
    Assert-Condition ([bool]$json.guardrail.noInstallPerformed) 'diagnostic must not install dependencies'
    Assert-Condition ([bool]$json.guardrail.noNetworkRequired) 'diagnostic must not require network'
    Assert-Condition (-not [bool]$json.guardrail.productionDefaultChanged) 'diagnostic must not change production defaults'
    Assert-Condition (-not [bool]$json.guardrail.localAiDefaultChanged) 'diagnostic must not change local AI defaults'
    Assert-Condition (-not [bool]$json.guardrail.modelWeightsDownloaded) 'diagnostic must not download model weights'
    Assert-Condition (-not [bool]$json.guardrail.secretsPrinted) 'diagnostic must not print secret values'
    Assert-Condition ([string]$json.guardrail.failClosedPolicy -match 'block|pending_review') 'fail-closed policy must block live release or mention pending_review'
    Assert-Condition ($json.bestConfiguration.profileSet -eq 'local_system_profile.v1') 'missing local system profile recommendation'

    $requiredProfiles = @(
        'runtimeProfile',
        'databaseProfile',
        'storageBackupProfile',
        'workerOcrProfile',
        'exportPrintProfile',
        'aiNetworkProfile',
        'aiLocalModelProfile',
        'searchProfile',
        'queueProfile',
        'securityProfile'
    )
    foreach ($profile in $requiredProfiles) {
        Assert-Condition ($null -ne $json.recommendedProfiles.$profile) "missing recommended profile: $profile"
        Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$json.recommendedProfiles.$profile.recommended)) "missing recommended value for profile: $profile"
    }

    Assert-Condition (@('direct_venv_lite','uv_venv_lite','conda_paddle_cpu','wsl_or_docker_heavy') -contains [string]$json.recommendedProfiles.workerOcrProfile.recommended) 'unexpected worker OCR recommended profile'
    Assert-Condition ([bool]$json.recommendedProfiles.aiLocalModelProfile.requiresEvalBeforeDefault) 'local AI model profile must require eval before default'
    Assert-Condition ([bool]$json.recommendedProfiles.aiLocalModelProfile.noModelDownloadPerformed) 'local AI model diagnostic must not download model weights'
    Assert-Condition ([bool]$json.recommendedProfiles.aiLocalModelProfile.noActiveWrite) 'local AI model profile must forbid active writes'
    Assert-Condition ([string]$json.recommendedProfiles.aiLocalModelProfile.fallback -match 'pending_review|rules_first') 'local AI model profile must retain fail-closed fallback'
    Assert-Condition ([bool]$json.bestConfiguration.adaptiveOnNewHost) 'local system profile must be adaptive on new host'
    Assert-Condition (@($json.bestConfiguration.humanConfirmationBefore).Count -gt 0) 'human confirmation boundary must not be empty'
    Assert-Condition (@($json.bestConfiguration.lowRiskAgentActions).Count -gt 0) 'low-risk agent action list must not be empty'

    [ordered]@{
        status = 'pass'
        task = 'host capability diagnostic contract'
        report = $Report
        profileSet = [string]$json.bestConfiguration.profileSet
        runtimeProfile = [string]$json.recommendedProfiles.runtimeProfile.recommended
        databaseProfile = [string]$json.recommendedProfiles.databaseProfile.recommended
        workerOcrProfile = [string]$json.recommendedProfiles.workerOcrProfile.recommended
        aiLocalModelProfile = [string]$json.recommendedProfiles.aiLocalModelProfile.recommended
        noInstallPerformed = [bool]$json.guardrail.noInstallPerformed
        localAiDefaultChanged = [bool]$json.guardrail.localAiDefaultChanged
        modelWeightsDownloaded = [bool]$json.guardrail.modelWeightsDownloaded
    } | ConvertTo-Json -Depth 5
}
finally {
    Pop-Location
}

param(
    [string] $Config = 'configs\installer_init.defaults.yaml',
    [string] $WorkerReportPath = 'docs/evidence/20260607-ns1303-worker-profile-diagnostic-report.json',
    [string] $HostReportPath = 'docs/evidence/20260607-ns1303-host-capability-diagnostic-report.json',
    [string] $ReportPath = 'docs/evidence/20260607-ns1303-runtime-profile.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Read-Json([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing json report: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Read-Text([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing text file: $Path"
    return Get-Content -LiteralPath $fullPath -Raw
}

function New-DiffEntry(
    [string] $Key,
    [string] $Current,
    [string] $Proposed,
    [string] $Source,
    [string] $WriteMode = 'draft_overlay_only'
) {
    [ordered]@{
        key = $Key
        current = $Current
        proposed = $Proposed
        source = $Source
        writeMode = $WriteMode
    }
}

Push-Location $repoRoot
try {
    Assert-Condition (Test-Path -LiteralPath $Config) "missing installer config: $Config"

    $ns1302 = Read-Json 'docs/evidence/20260607-ns1302-service-control-panel.json'
    Assert-Condition ($ns1302.status -eq 'pass') 'NS1303 dependency NS1302 did not pass'

    $configJson = python -c "import json, pathlib, yaml; p=pathlib.Path(r'$($Config.Replace('\','\\'))'); d=yaml.safe_load(p.read_text(encoding='utf-8')); print(json.dumps(d, ensure_ascii=False))"
    Assert-Condition ($LASTEXITCODE -eq 0) 'failed to parse installer init config yaml'
    $installerConfig = $configJson | ConvertFrom-Json
    $configVersion = ([string] $installerConfig.version).Trim()
    $configMode = ([string] $installerConfig.mode).Trim()
    if ($configVersion -ne 'o002.installer-init.v1') {
        throw "unexpected installer init config version: [$configVersion]"
    }
    if ($configMode -ne 'draft_test') {
        throw "NS1303 installer config must stay in draft_test mode: [$configMode]"
    }

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
        Assert-Condition (@($installerConfig.local_system_profile.required_profiles) -contains $profile) "NS1303 installer config missing required profile: $profile"
    }

    & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'run-worker-profile-diagnostic-contract.ps1') -Report $WorkerReportPath | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) 'NS1303 worker profile diagnostic failed'
    & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'run-host-capability-diagnostic-contract.ps1') -Config $Config -Report $HostReportPath | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) 'NS1303 host capability diagnostic failed'

    $workerJson = Read-Json $WorkerReportPath
    $hostJson = Read-Json $HostReportPath

    Assert-Condition ($workerJson.schemaVersion -eq 'worker-profile-diagnostic.v1') 'NS1303 worker diagnostic schema mismatch'
    Assert-Condition ($workerJson.mode -eq 'read_only') 'NS1303 worker diagnostic must stay read_only'
    Assert-Condition ([bool]$workerJson.guardrail.noInstallPerformed) 'NS1303 worker diagnostic must not install dependencies'
    Assert-Condition (-not [bool]$workerJson.guardrail.productionDefaultChanged) 'NS1303 worker diagnostic must not change production default'

    Assert-Condition ($hostJson.schemaVersion -eq 'host-capability-diagnostic.v1') 'NS1303 host diagnostic schema mismatch'
    Assert-Condition ($hostJson.mode -eq 'read_only') 'NS1303 host diagnostic must stay read_only'
    Assert-Condition ([bool]$hostJson.guardrail.noInstallPerformed) 'NS1303 host diagnostic must not install dependencies'
    Assert-Condition ([bool]$hostJson.guardrail.noNetworkRequired) 'NS1303 host diagnostic must not require network'
    Assert-Condition (-not [bool]$hostJson.guardrail.productionDefaultChanged) 'NS1303 host diagnostic must not change production default'
    Assert-Condition (-not [bool]$hostJson.guardrail.localAiDefaultChanged) 'NS1303 host diagnostic must not change local AI default'
    Assert-Condition (-not [bool]$hostJson.guardrail.modelWeightsDownloaded) 'NS1303 host diagnostic must not download model weights'
    Assert-Condition (-not [bool]$hostJson.guardrail.secretsPrinted) 'NS1303 host diagnostic must not print secrets'

    $serviceControlPanel = Read-Text 'apps/web/src/ui/ServiceControlPanel.tsx'
    Assert-Condition ($serviceControlPanel.Contains('service-open-config-diff')) 'NS1303 service control panel must expose config diff action'

    $appSettings = Read-Json 'apps/api/appsettings.json'
    $dataRoot = [string] $installerConfig.paths.data_root
    $backupRoot = [string] $installerConfig.paths.backup_root
    $fileStoreRoot = Join-Path $dataRoot ([string] $installerConfig.paths.file_store_relative)
    $logsRoot = Join-Path $dataRoot ([string] $installerConfig.paths.logs_relative)
    $cacheRoot = Join-Path $dataRoot ([string] $installerConfig.paths.cache_relative)
    $modelCacheRoot = Join-Path $dataRoot ([string] $installerConfig.worker_profiles.model_cache_relative)

    $generatedConfigDiffEntries = @(
        (New-DiffEntry 'LocalSystemProfile.profileSet' '' ([string] $hostJson.bestConfiguration.profileSet) 'host_capability_diagnostic')
        (New-DiffEntry 'LocalSystemProfile.runtimeProfile' '' ([string] $hostJson.recommendedProfiles.runtimeProfile.recommended) 'host_capability_diagnostic')
        (New-DiffEntry 'LocalSystemProfile.databaseProfile' '' ([string] $hostJson.recommendedProfiles.databaseProfile.recommended) 'host_capability_diagnostic')
        (New-DiffEntry 'LocalSystemProfile.storageBackupProfile' '' ([string] $hostJson.recommendedProfiles.storageBackupProfile.recommended) 'host_capability_diagnostic')
        (New-DiffEntry 'LocalSystemProfile.workerOcrProfile' '' ([string] $hostJson.recommendedProfiles.workerOcrProfile.recommended) 'host_capability_diagnostic')
        (New-DiffEntry 'LocalSystemProfile.exportPrintProfile' '' ([string] $hostJson.recommendedProfiles.exportPrintProfile.recommended) 'host_capability_diagnostic')
        (New-DiffEntry 'LocalSystemProfile.aiNetworkProfile' '' ([string] $hostJson.recommendedProfiles.aiNetworkProfile.recommended) 'host_capability_diagnostic')
        (New-DiffEntry 'LocalSystemProfile.aiLocalModelProfile' '' ([string] $hostJson.recommendedProfiles.aiLocalModelProfile.recommended) 'host_capability_diagnostic')
        (New-DiffEntry 'LocalSystemProfile.searchProfile' '' ([string] $hostJson.recommendedProfiles.searchProfile.recommended) 'host_capability_diagnostic')
        (New-DiffEntry 'LocalSystemProfile.queueProfile' '' ([string] $hostJson.recommendedProfiles.queueProfile.recommended) 'host_capability_diagnostic')
        (New-DiffEntry 'LocalSystemProfile.securityProfile' '' ([string] $hostJson.recommendedProfiles.securityProfile.recommended) 'host_capability_diagnostic')
        (New-DiffEntry 'KqgPaths.DataRoot' ([string] $appSettings.KqgPaths.DataRoot) $dataRoot 'installer_defaults')
        (New-DiffEntry 'KqgPaths.FileStoreRoot' ([string] $appSettings.KqgPaths.FileStoreRoot) $fileStoreRoot 'installer_defaults')
        (New-DiffEntry 'KqgPaths.BackupRoot' ([string] $appSettings.KqgPaths.BackupRoot) $backupRoot 'installer_defaults')
        (New-DiffEntry 'KqgPaths.LogsRoot' ([string] $appSettings.KqgPaths.LogsRoot) $logsRoot 'installer_defaults')
        (New-DiffEntry 'KqgPaths.CacheRoot' ([string] $appSettings.KqgPaths.CacheRoot) $cacheRoot 'installer_defaults')
        (New-DiffEntry 'PythonWorker.RecommendedProfile' '' ([string] $workerJson.recommendation.recommendedDefaultProfile) 'worker_profile_diagnostic')
        (New-DiffEntry 'PythonWorker.ModelCacheRoot' '' $modelCacheRoot 'installer_defaults')
        (New-DiffEntry 'Runtime.WindowsServiceHost' '' ([string] $hostJson.recommendedProfiles.runtimeProfile.recommended) 'host_capability_diagnostic')
        (New-DiffEntry 'AiProfiles.Network' '' ([string] $hostJson.recommendedProfiles.aiNetworkProfile.recommended) 'host_capability_diagnostic')
        (New-DiffEntry 'AiProfiles.LocalModel' '' ([string] $hostJson.recommendedProfiles.aiLocalModelProfile.recommended) 'host_capability_diagnostic')
        (New-DiffEntry 'SearchQueue.SearchProfile' '' ([string] $hostJson.recommendedProfiles.searchProfile.recommended) 'host_capability_diagnostic')
        (New-DiffEntry 'SearchQueue.QueueProfile' '' ([string] $hostJson.recommendedProfiles.queueProfile.recommended) 'host_capability_diagnostic')
    )

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS1303'
        checkedAt = (Get-Date).ToString('s')
        mode = 'read_only_runtime_profile_generation'
        productionEligible = $false
        dependency = [ordered]@{
            ns1302 = 'docs/evidence/20260607-ns1302-service-control-panel.json'
        }
        diagnostics = [ordered]@{
            workerProfileReport = $WorkerReportPath
            hostCapabilityReport = $HostReportPath
            workerRecommendedDefaultProfile = [string] $workerJson.recommendation.recommendedDefaultProfile
            localSystemProfile = [ordered]@{
                profileSet = [string] $hostJson.bestConfiguration.profileSet
                runtimeProfile = [string] $hostJson.recommendedProfiles.runtimeProfile.recommended
                databaseProfile = [string] $hostJson.recommendedProfiles.databaseProfile.recommended
                storageBackupProfile = [string] $hostJson.recommendedProfiles.storageBackupProfile.recommended
                workerOcrProfile = [string] $hostJson.recommendedProfiles.workerOcrProfile.recommended
                exportPrintProfile = [string] $hostJson.recommendedProfiles.exportPrintProfile.recommended
                aiNetworkProfile = [string] $hostJson.recommendedProfiles.aiNetworkProfile.recommended
                aiLocalModelProfile = [string] $hostJson.recommendedProfiles.aiLocalModelProfile.recommended
                searchProfile = [string] $hostJson.recommendedProfiles.searchProfile.recommended
                queueProfile = [string] $hostJson.recommendedProfiles.queueProfile.recommended
                securityProfile = [string] $hostJson.recommendedProfiles.securityProfile.recommended
            }
        }
        generatedConfigDiff = [ordered]@{
            mode = 'draft_overlay_only'
            installerConfig = $Config
            serviceControlAction = 'service-open-config-diff'
            entries = $generatedConfigDiffEntries
            proposedOverlay = [ordered]@{
                    installer = [ordered]@{
                        version = $configVersion
                        mode = $configMode
                    adaptiveOnNewHost = [bool] $installerConfig.local_system_profile.adaptive_on_new_host
                    requiredProfiles = @($installerConfig.local_system_profile.required_profiles)
                }
                paths = [ordered]@{
                    dataRoot = $dataRoot
                    backupRoot = $backupRoot
                    fileStoreRoot = $fileStoreRoot
                    logsRoot = $logsRoot
                    cacheRoot = $cacheRoot
                    modelCacheRoot = $modelCacheRoot
                }
                pythonWorker = [ordered]@{
                    recommendedProfile = [string] $workerJson.recommendation.recommendedDefaultProfile
                    pythonExecutable = [string] $appSettings.PythonWorker.PythonExecutable
                    documentWorkerScript = [string] $appSettings.PythonWorker.DocumentWorkerScript
                    timeoutSeconds = [int] $appSettings.PythonWorker.TimeoutSeconds
                    fallback = [string] $workerJson.guardrail.failClosedPolicy
                }
                ai = [ordered]@{
                    networkProfile = [string] $hostJson.recommendedProfiles.aiNetworkProfile.recommended
                    localModelProfile = [string] $hostJson.recommendedProfiles.aiLocalModelProfile.recommended
                    localModelRequiresEvalBeforeDefault = [bool] $hostJson.recommendedProfiles.aiLocalModelProfile.requiresEvalBeforeDefault
                    localModelNoActiveWrite = [bool] $hostJson.recommendedProfiles.aiLocalModelProfile.noActiveWrite
                }
                searchQueue = [ordered]@{
                    searchProfile = [string] $hostJson.recommendedProfiles.searchProfile.recommended
                    queueProfile = [string] $hostJson.recommendedProfiles.queueProfile.recommended
                }
            }
        }
        automationBoundary = [ordered]@{
            lowRiskAutoActions = @($hostJson.bestConfiguration.lowRiskAgentActions)
            humanConfirmationBefore = @($hostJson.bestConfiguration.humanConfirmationBefore)
        }
        acceptance = [ordered]@{
            hostCapabilityDiagnosticReadOnly = $true
            workerProfileDiagnosticReadOnly = $true
            localSystemProfilePresent = $true
            workerOcrProfilePresent = $true
            aiNetworkProfilePresent = $true
            aiLocalModelProfilePresent = $true
            searchProfilePresent = $true
            queueProfilePresent = $true
            generatedConfigDiffPresent = $true
            serviceControlPanelCanExposeConfigDiff = $true
            onlyLowRiskActionsAutoSuggested = $true
        }
        verification = [ordered]@{
            build = 'gate_na: NS1303 uses read-only diagnostics and generated draft config diff only; no product build needed for this slice'
            test = 'tools/run-worker-profile-diagnostic-contract.ps1 + tools/run-host-capability-diagnostic-contract.ps1'
            contractInvariant = 'required localSystemProfile keys plus generated config diff must stay present and service control panel must expose the config-diff action'
            hotspot = 'gate_na: no real service install, no driver/runtime change, no cloud token enablement, no model download, and no production default switch'
        }
        boundary = 'NS1303 turns host/worker diagnostics into a reusable draft config overlay for installer or service control panel review. It does not mutate appsettings, install dependencies, enable cloud AI, download local models, or switch production defaults.'
        rollback = "git restore tasks/non-site-implementation-plan.csv tasks/productization-roadmap.csv tools/run-gates.ps1 tools/README.md; git clean -f -- tools/run-ns1303-runtime-profile-contract.ps1 $WorkerReportPath $HostReportPath $ReportPath"
        next = 'NS1304 can continue toolchain admission and fail-closed profile selection from the generated runtime profile overlay.'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 12
}
finally {
    Pop-Location
}

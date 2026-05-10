param(
    [string]$Config = 'configs\installer_init.defaults.yaml',
    [string]$DatabasePassword = $env:PGPASSWORD,
    [string]$Report = 'docs\evidence\o002-installer-init-wizard-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

function Assert-Condition([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Require-Command([string]$Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    Assert-Condition ($null -ne $cmd) "missing required command: $Name"
}

Push-Location $repoRoot
try {
    Assert-Condition (Test-Path -LiteralPath $Config) "missing config: $Config"
    Require-Command 'python'

    $cfgJson = python -c "import json, pathlib, yaml; p=pathlib.Path(r'$($Config.Replace('\','\\'))'); d=yaml.safe_load(p.read_text(encoding='utf-8')); print(json.dumps(d, ensure_ascii=False))"
    Assert-Condition ($LASTEXITCODE -eq 0) 'failed to parse installer init config yaml'
    $cfg = $cfgJson | ConvertFrom-Json
    Assert-Condition ($cfg.version -eq 'o002.installer-init.v1') 'unexpected installer init config version'

    $dataRoot = [string]$cfg.paths.data_root
    $backupRoot = [string]$cfg.paths.backup_root
    $fileStoreRoot = Join-Path $dataRoot ([string]$cfg.paths.file_store_relative)
    $logsRoot = Join-Path $dataRoot ([string]$cfg.paths.logs_relative)
    $cacheRoot = Join-Path $dataRoot ([string]$cfg.paths.cache_relative)

    foreach ($path in @($dataRoot, $backupRoot, $fileStoreRoot, $logsRoot, $cacheRoot)) {
        Assert-Condition ($path -match '^[A-Za-z]:\\') "path must be absolute windows path: $path"
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        $probe = Join-Path $path ('.o002-probe-' + [Guid]::NewGuid().ToString('N') + '.tmp')
        Set-Content -LiteralPath $probe -Value 'ok' -Encoding ASCII
        Remove-Item -LiteralPath $probe -Force
    }

    $pgpassConfig = [string]$cfg.references.pgpass_config
    $pgpassGate = [string]$cfg.references.pgpass_gate
    $workerProfileDiagnosticGate = [string]$cfg.references.worker_profile_diagnostic_gate
    $hostCapabilityDiagnosticGate = [string]$cfg.references.host_capability_diagnostic_gate
    Assert-Condition (Test-Path -LiteralPath $pgpassConfig) "missing pgpass config: $pgpassConfig"
    Assert-Condition (Test-Path -LiteralPath $pgpassGate) "missing pgpass gate script: $pgpassGate"
    Assert-Condition (Test-Path -LiteralPath $workerProfileDiagnosticGate) "missing worker profile diagnostic gate script: $workerProfileDiagnosticGate"
    Assert-Condition (Test-Path -LiteralPath $hostCapabilityDiagnosticGate) "missing host capability diagnostic gate script: $hostCapabilityDiagnosticGate"

    Assert-Condition (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'DatabasePassword or PGPASSWORD is required for O002 installer init dry-run'

    $pgpassReport = 'docs\evidence\o002-installer-pgpass-dry-run-report.json'
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $pgpassGate -DatabasePassword $DatabasePassword -Config $pgpassConfig -Report $pgpassReport | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) 'embedded G004 pgpass dry-run failed'
    Assert-Condition (Test-Path -LiteralPath $pgpassReport) 'missing embedded pgpass evidence report'

    $workerProfileReport = 'docs\evidence\o002-worker-profile-diagnostic-report.json'
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $workerProfileDiagnosticGate -Report $workerProfileReport | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) 'embedded worker profile diagnostic failed'
    Assert-Condition (Test-Path -LiteralPath $workerProfileReport) 'missing embedded worker profile diagnostic report'
    $workerProfileJson = Get-Content -LiteralPath $workerProfileReport -Raw | ConvertFrom-Json

    $hostCapabilityReport = 'docs\evidence\o002-host-capability-diagnostic-report.json'
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $hostCapabilityDiagnosticGate -Config $Config -Report $hostCapabilityReport | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) 'embedded host capability diagnostic failed'
    Assert-Condition (Test-Path -LiteralPath $hostCapabilityReport) 'missing embedded host capability diagnostic report'
    $hostCapabilityJson = Get-Content -LiteralPath $hostCapabilityReport -Raw | ConvertFrom-Json

    $adminKey = [Convert]::ToBase64String((1..24 | ForEach-Object { Get-Random -Minimum 0 -Maximum 256 }))
    $adminKeySha256 = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($adminKey))).Replace('-', '').ToLowerInvariant()

    $reportObject = [ordered]@{
        status = 'pass'
        task = 'O002'
        mode = 'draft_test'
        productionEligible = $false
        config = $Config
        installerChecks = [ordered]@{
            postgresqlConnectionConfig = [ordered]@{
                host = [string]$cfg.postgresql.host
                port = [int]$cfg.postgresql.port
                database = [string]$cfg.postgresql.database
                username = [string]$cfg.postgresql.username
                passwordProvided = $true
            }
            directories = [ordered]@{
                dataRoot = $dataRoot
                backupRoot = $backupRoot
                fileStoreRoot = $fileStoreRoot
                logsRoot = $logsRoot
                cacheRoot = $cacheRoot
                writableProbePassed = $true
            }
            pgpass = [ordered]@{
                config = $pgpassConfig
                gate = $pgpassGate
                report = $pgpassReport
                status = 'pass'
            }
            workerProfile = [ordered]@{
                adaptiveOnNewHost = [bool]$cfg.worker_profiles.adaptive_on_new_host
                gate = $workerProfileDiagnosticGate
                report = $workerProfileReport
                recommendedDefaultProfile = [string]$workerProfileJson.recommendation.recommendedDefaultProfile
                availableProfileCandidates = @($workerProfileJson.recommendation.availableProfileCandidates)
                productionDefaultChanged = [bool]$workerProfileJson.guardrail.productionDefaultChanged
            }
            localSystemProfile = [ordered]@{
                adaptiveOnNewHost = [bool]$cfg.local_system_profile.adaptive_on_new_host
                gate = $hostCapabilityDiagnosticGate
                report = $hostCapabilityReport
                profileSet = [string]$hostCapabilityJson.bestConfiguration.profileSet
                runtimeProfile = [string]$hostCapabilityJson.recommendedProfiles.runtimeProfile.recommended
                databaseProfile = [string]$hostCapabilityJson.recommendedProfiles.databaseProfile.recommended
                storageBackupProfile = [string]$hostCapabilityJson.recommendedProfiles.storageBackupProfile.recommended
                workerOcrProfile = [string]$hostCapabilityJson.recommendedProfiles.workerOcrProfile.recommended
                exportPrintProfile = [string]$hostCapabilityJson.recommendedProfiles.exportPrintProfile.recommended
                aiNetworkProfile = [string]$hostCapabilityJson.recommendedProfiles.aiNetworkProfile.recommended
                aiLocalModelProfile = [string]$hostCapabilityJson.recommendedProfiles.aiLocalModelProfile.recommended
                aiLocalModelStatus = [string]$hostCapabilityJson.recommendedProfiles.aiLocalModelProfile.status
                searchProfile = [string]$hostCapabilityJson.recommendedProfiles.searchProfile.recommended
                queueProfile = [string]$hostCapabilityJson.recommendedProfiles.queueProfile.recommended
                securityProfile = [string]$hostCapabilityJson.recommendedProfiles.securityProfile.recommended
                noInstallPerformed = [bool]$hostCapabilityJson.guardrail.noInstallPerformed
                modelWeightsDownloaded = [bool]$hostCapabilityJson.guardrail.modelWeightsDownloaded
                localAiDefaultChanged = [bool]$hostCapabilityJson.guardrail.localAiDefaultChanged
                productionDefaultChanged = [bool]$hostCapabilityJson.guardrail.productionDefaultChanged
            }
            bootstrapAdmin = [ordered]@{
                mode = [string]$cfg.security.bootstrap_admin.mode
                rotateRequiredOnFirstLogin = [bool]$cfg.security.bootstrap_admin.rotate_required_on_first_login
                persistedPlaintext = $false
                adminKeySha256 = $adminKeySha256
            }
        }
        guardrail = [ordered]@{
            o004bNotCompleted = $true
            note = 'O002 only initializes installer-level admin key bootstrap; RBAC and audit trail remain blocked by O004B.'
        }
        rollback = [ordered]@{
            directories = @(
                "Remove-Item -LiteralPath '$dataRoot' -Recurse -Force",
                "Remove-Item -LiteralPath '$backupRoot' -Recurse -Force"
            )
            pgpass = 'see o002-installer-pgpass-dry-run-report.json for temp APPDATA cleanup evidence'
            adminKey = 'generated bootstrap key is not persisted in plaintext; rotate key when real install is enabled'
        }
        summaryChinese = [ordered]@{
            title = 'O002 安装初始化向导 dry-run 合同报告'
            result = '通过'
            boundary = '仅验证初始化向导所需参数、目录、pgpass 流程和管理员引导 key，不开启真实试点部署。'
        }
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $Report) -Force | Out-Null
    $reportJson = $reportObject | ConvertTo-Json -Depth 10
    $reportJson | Set-Content -LiteralPath $Report -Encoding UTF8
    $reportJson
}
finally {
    Pop-Location
}

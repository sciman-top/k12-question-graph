param(
    [string] $Config = 'configs\installer_init.defaults.yaml',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $ReportPath = '',
    [string] $PgpassReportPath = '',
    [string] $WorkerProfileReportPath = '',
    [string] $HostCapabilityReportPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runDate = Get-Date -Format 'yyyyMMdd'
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = ('docs/evidence/{0}-ns803-installer-host.json' -f $runDate)
}
if ([string]::IsNullOrWhiteSpace($PgpassReportPath)) {
    $PgpassReportPath = ('docs/evidence/{0}-ns803-pgpass-dry-run-report.json' -f $runDate)
}
if ([string]::IsNullOrWhiteSpace($WorkerProfileReportPath)) {
    $WorkerProfileReportPath = ('docs/evidence/{0}-ns803-worker-profile-diagnostic-report.json' -f $runDate)
}
if ([string]::IsNullOrWhiteSpace($HostCapabilityReportPath)) {
    $HostCapabilityReportPath = ('docs/evidence/{0}-ns803-host-capability-diagnostic-report.json' -f $runDate)
}

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Read-Json([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing report: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Read-Text([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing file: $Path"
    return Get-Content -LiteralPath $fullPath -Raw
}

function Assert-NoSecretInFile([string] $Path, [string] $Secret, [string] $Label) {
    if ([string]::IsNullOrWhiteSpace($Secret)) {
        return
    }

    $text = Read-Text $Path
    Assert-Condition (-not $text.Contains($Secret)) "$Label leaked the database password"
}

function Test-DirectoryWritable([string] $Name, [string] $Path) {
    Assert-Condition ($Path -match '^[A-Za-z]:\\') "path must be absolute windows path: $Path"
    $existedBefore = Test-Path -LiteralPath $Path
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    $probe = Join-Path $Path ('.ns803-probe-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    Set-Content -LiteralPath $probe -Value 'ok' -Encoding ASCII
    Remove-Item -LiteralPath $probe -Force

    return [ordered]@{
        name = $Name
        path = $Path
        existedBefore = $existedBefore
        writableProbePassed = $true
    }
}

Push-Location $repoRoot
try {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'DatabasePassword or PGPASSWORD is required for NS803 installer host diagnostic.'

    $ns802 = Read-Json 'docs/evidence/20260530-ns802-restore-drill-report.json'
    Assert-Condition ($ns802.status -eq 'pass') 'NS803 dependency NS802 report did not pass'
    Assert-Condition ([bool]$ns802.acceptance.productionDatabaseUntouched) 'NS803 requires NS802 restore drill to leave production database untouched'
    Assert-Condition ([bool]$ns802.acceptance.productionFileStoreUntouched) 'NS803 requires NS802 restore drill to leave production file store untouched'

    Assert-Condition (Test-Path -LiteralPath $Config) "missing installer config: $Config"
    $cfgJson = python -c "import json, pathlib, yaml; p=pathlib.Path(r'$($Config.Replace('\','\\'))'); d=yaml.safe_load(p.read_text(encoding='utf-8')); print(json.dumps(d, ensure_ascii=False))"
    Assert-Condition ($LASTEXITCODE -eq 0) 'failed to parse installer init config yaml'
    $cfg = $cfgJson | ConvertFrom-Json
    Assert-Condition ($cfg.version -eq 'o002.installer-init.v1') 'unexpected installer init config version'
    Assert-Condition ($cfg.mode -eq 'draft_test') 'NS803 installer initialization must stay in draft_test mode'

    $dataRoot = [string]$cfg.paths.data_root
    $backupRoot = [string]$cfg.paths.backup_root
    $fileStoreRoot = Join-Path $dataRoot ([string]$cfg.paths.file_store_relative)
    $logsRoot = Join-Path $dataRoot ([string]$cfg.paths.logs_relative)
    $cacheRoot = Join-Path $dataRoot ([string]$cfg.paths.cache_relative)
    $modelCacheRoot = Join-Path $dataRoot ([string]$cfg.worker_profiles.model_cache_relative)

    $directoryChecks = @(
        Test-DirectoryWritable 'dataRoot' $dataRoot
        Test-DirectoryWritable 'backupRoot' $backupRoot
        Test-DirectoryWritable 'fileStoreRoot' $fileStoreRoot
        Test-DirectoryWritable 'logsRoot' $logsRoot
        Test-DirectoryWritable 'cacheRoot' $cacheRoot
        Test-DirectoryWritable 'modelCacheRoot' $modelCacheRoot
    )

    $pgpassConfig = [string]$cfg.references.pgpass_config
    $pgpassGate = [string]$cfg.references.pgpass_gate
    $workerProfileDiagnosticGate = [string]$cfg.references.worker_profile_diagnostic_gate
    $hostCapabilityDiagnosticGate = [string]$cfg.references.host_capability_diagnostic_gate
    Assert-Condition (Test-Path -LiteralPath $pgpassConfig) "missing pgpass config: $pgpassConfig"
    Assert-Condition (Test-Path -LiteralPath $pgpassGate) "missing pgpass gate script: $pgpassGate"
    Assert-Condition (Test-Path -LiteralPath $workerProfileDiagnosticGate) "missing worker profile diagnostic gate script: $workerProfileDiagnosticGate"
    Assert-Condition (Test-Path -LiteralPath $hostCapabilityDiagnosticGate) "missing host capability diagnostic gate script: $hostCapabilityDiagnosticGate"

    & pwsh -NoProfile -ExecutionPolicy Bypass -File $pgpassGate `
        -Config $pgpassConfig `
        -Report $PgpassReportPath `
        -DatabaseName $DatabaseName `
        -DatabaseUser $DatabaseUser `
        -DatabaseHost $DatabaseHost `
        -DatabasePort $DatabasePort `
        -DatabasePassword $DatabasePassword `
        -PgBin $PgBin | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) 'NS803 embedded pgpass dry-run failed'
    $pgpassJson = Read-Json $PgpassReportPath
    Assert-Condition ($pgpassJson.status -eq 'pass') 'NS803 pgpass report did not pass'
    Assert-Condition (-not [bool]$pgpassJson.realUserPgpassModified) 'NS803 pgpass dry-run must not modify real user pgpass'
    Assert-Condition ([bool]$pgpassJson.processPgpasswordClearedForVerification) 'NS803 pgpass dry-run must clear process PGPASSWORD before psql -w'
    Assert-Condition ([bool]$pgpassJson.psqlNoPasswordPromptVerified) 'NS803 pgpass dry-run must verify psql -w without password prompt'
    Assert-Condition ([bool]$pgpassJson.cleanup.tempPgpassRemoved) 'NS803 pgpass dry-run must remove temporary pgpass'
    Assert-Condition (-not [bool]$pgpassJson.secretHandling.passwordLogged) 'NS803 pgpass dry-run must not log password'
    Assert-Condition (-not [bool]$pgpassJson.secretHandling.reportContainsPassword) 'NS803 pgpass dry-run report must not contain password'

    & pwsh -NoProfile -ExecutionPolicy Bypass -File $workerProfileDiagnosticGate -Report $WorkerProfileReportPath | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) 'NS803 embedded worker profile diagnostic failed'
    $workerProfileJson = Read-Json $WorkerProfileReportPath
    Assert-Condition ($workerProfileJson.schemaVersion -eq 'worker-profile-diagnostic.v1') 'NS803 worker diagnostic schema mismatch'
    Assert-Condition ($workerProfileJson.mode -eq 'read_only') 'NS803 worker diagnostic must be read_only'
    Assert-Condition ([bool]$workerProfileJson.guardrail.noInstallPerformed) 'NS803 worker diagnostic must not install dependencies'
    Assert-Condition (-not [bool]$workerProfileJson.guardrail.productionDefaultChanged) 'NS803 worker diagnostic must not change production default'

    & pwsh -NoProfile -ExecutionPolicy Bypass -File $hostCapabilityDiagnosticGate -Config $Config -Report $HostCapabilityReportPath | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) 'NS803 embedded host capability diagnostic failed'
    $hostCapabilityJson = Read-Json $HostCapabilityReportPath
    Assert-Condition ($hostCapabilityJson.schemaVersion -eq 'host-capability-diagnostic.v1') 'NS803 host diagnostic schema mismatch'
    Assert-Condition ($hostCapabilityJson.mode -eq 'read_only') 'NS803 host diagnostic must be read_only'
    Assert-Condition ([bool]$hostCapabilityJson.guardrail.noInstallPerformed) 'NS803 host diagnostic must not install dependencies'
    Assert-Condition ([bool]$hostCapabilityJson.guardrail.noNetworkRequired) 'NS803 host diagnostic must not require network'
    Assert-Condition (-not [bool]$hostCapabilityJson.guardrail.secretsPrinted) 'NS803 host diagnostic must not print secrets'
    Assert-Condition (-not [bool]$hostCapabilityJson.guardrail.productionDefaultChanged) 'NS803 host diagnostic must not change production defaults'
    Assert-Condition (-not [bool]$hostCapabilityJson.guardrail.localAiDefaultChanged) 'NS803 host diagnostic must not change local AI defaults'
    Assert-Condition (-not [bool]$hostCapabilityJson.guardrail.modelWeightsDownloaded) 'NS803 host diagnostic must not download model weights'
    Assert-Condition ($hostCapabilityJson.storage.dataRoot.available -and $hostCapabilityJson.storage.backupRoot.available) 'NS803 host diagnostic must see data and backup storage anchors'

    foreach ($evidencePath in @($PgpassReportPath, $WorkerProfileReportPath, $HostCapabilityReportPath)) {
        Assert-NoSecretInFile $evidencePath $DatabasePassword $evidencePath
    }

    $adminKey = [Convert]::ToBase64String((1..24 | ForEach-Object { Get-Random -Minimum 0 -Maximum 256 }))
    $adminKeySha256 = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($adminKey))).Replace('-', '').ToLowerInvariant()

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS803'
        checkedAt = (Get-Date).ToString('s')
        mode = 'installer_host_diagnostic'
        productionEligible = $false
        externalAiCalls = 0
        realStudentDataUsed = $false
        writesProductionHistory = $false
        activeAssetMutation = $false
        dependency = [ordered]@{
            ns802 = 'docs/evidence/20260530-ns802-restore-drill-report.json'
        }
        installer = [ordered]@{
            config = $Config
            configVersion = [string]$cfg.version
            configMode = [string]$cfg.mode
            postgresql = [ordered]@{
                host = $DatabaseHost
                port = $DatabasePort
                database = $DatabaseName
                username = $DatabaseUser
                passwordProvided = $true
                pgpassReport = $PgpassReportPath
            }
            directories = $directoryChecks
            workerProfile = [ordered]@{
                report = $WorkerProfileReportPath
                recommendedDefaultProfile = [string]$workerProfileJson.recommendation.recommendedDefaultProfile
                availableProfileCandidates = @($workerProfileJson.recommendation.availableProfileCandidates)
                noInstallPerformed = [bool]$workerProfileJson.guardrail.noInstallPerformed
                productionDefaultChanged = [bool]$workerProfileJson.guardrail.productionDefaultChanged
            }
            hostCapability = [ordered]@{
                report = $HostCapabilityReportPath
                profileSet = [string]$hostCapabilityJson.bestConfiguration.profileSet
                runtimeProfile = [string]$hostCapabilityJson.recommendedProfiles.runtimeProfile.recommended
                databaseProfile = [string]$hostCapabilityJson.recommendedProfiles.databaseProfile.recommended
                storageBackupProfile = [string]$hostCapabilityJson.recommendedProfiles.storageBackupProfile.recommended
                workerOcrProfile = [string]$hostCapabilityJson.recommendedProfiles.workerOcrProfile.recommended
                exportPrintProfile = [string]$hostCapabilityJson.recommendedProfiles.exportPrintProfile.recommended
                aiNetworkProfile = [string]$hostCapabilityJson.recommendedProfiles.aiNetworkProfile.recommended
                aiLocalModelProfile = [string]$hostCapabilityJson.recommendedProfiles.aiLocalModelProfile.recommended
                searchProfile = [string]$hostCapabilityJson.recommendedProfiles.searchProfile.recommended
                queueProfile = [string]$hostCapabilityJson.recommendedProfiles.queueProfile.recommended
                securityProfile = [string]$hostCapabilityJson.recommendedProfiles.securityProfile.recommended
                noInstallPerformed = [bool]$hostCapabilityJson.guardrail.noInstallPerformed
                noNetworkRequired = [bool]$hostCapabilityJson.guardrail.noNetworkRequired
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
        acceptance = [ordered]@{
            ns802RestoreEvidencePassed = $true
            postgresqlConnectionConfigChecked = $true
            dataAndBackupRootsWritable = $true
            fileStoreLogCacheAndModelCacheWritable = $true
            pgpassDryRunPassed = $true
            realUserPgpassUntouched = $true
            temporaryPgpassRemoved = $true
            processPgpasswordClearedBeforePsql = $true
            workerProfileDiagnosticReadOnly = $true
            hostCapabilityDiagnosticReadOnly = $true
            noPlaintextPasswordInEvidence = $true
            noDependencyInstall = $true
            noNetworkRequired = $true
            noModelWeightsDownloaded = $true
            noProductionDefaultChanged = $true
            noLocalAiDefaultChanged = $true
            noActiveWrite = $true
        }
        verification = [ordered]@{
            build = 'gate_na: installer/host diagnostic orchestration only; no product code build required for this slice'
            test = 'tools/run-g004-pgpass-installer-dry-run.ps1 + tools/run-worker-profile-diagnostic-contract.ps1 + tools/run-host-capability-diagnostic-contract.ps1'
            contractInvariant = 'NS803 requires NS802 restore evidence, writable installer roots, pgpass temp cleanup, read-only worker/host diagnostics, no secret leakage, no install/network/model/default mutation'
            hotspot = 'gate_na: no isolated-machine GUI installer or service install in this non-site slice; NS804/NS1001 own publish/service and live install rehearsals'
        }
        boundary = 'NS803 proves draft/test installer initialization and host diagnostic readiness on this host. It does not install a Windows Service, change firewall or drivers, download model weights, process real materials, or switch production defaults.'
        rollback = "Remove only empty directories created by this dry-run under $dataRoot or $backupRoot if they did not exist before; git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1 tools/README.md; git clean -f -- tools/run-ns803-installer-host.ps1 $ReportPath $PgpassReportPath $WorkerProfileReportPath $HostCapabilityReportPath"
        next = 'NS804 can continue Windows Service publish package.'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 10
}
finally {
    Pop-Location
}

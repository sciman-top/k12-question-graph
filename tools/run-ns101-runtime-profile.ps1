param(
    [string] $ReportPath = 'docs/evidence/20260528-ns101-runtime-profile.json',
    [string] $HostReportPath = 'docs/evidence/20260528-ns101-host-capability-diagnostic-report.json',
    [string] $WorkerReportPath = 'docs/evidence/20260528-ns101-worker-profile-diagnostic-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Resolve-ToolPath([string] $Name, [string[]] $FallbackPaths = @()) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return [ordered]@{
            present = $true
            path = [string]$command.Source
            source = 'PATH'
        }
    }

    foreach ($candidate in $FallbackPaths) {
        if (Test-Path -LiteralPath $candidate) {
            return [ordered]@{
                present = $true
                path = $candidate
                source = 'fallback_path'
            }
        }
    }

    return [ordered]@{
        present = $false
        path = $null
        source = 'not_found'
    }
}

function Invoke-ToolProbe([string] $Name, [hashtable] $ResolvedTool, [string[]] $Arguments = @()) {
    if (-not [bool]$ResolvedTool.present) {
        return [ordered]@{
            present = $false
            path = $null
            source = [string]$ResolvedTool.source
            args = $Arguments
            exitCode = $null
            output = ''
        }
    }

    $toolPath = [string]$ResolvedTool.path
    $output = & $toolPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($null -eq $exitCode) { $exitCode = 0 }

    return [ordered]@{
        present = $true
        path = $toolPath
        source = [string]$ResolvedTool.source
        args = $Arguments
        exitCode = [int]$exitCode
        output = (($output | Select-Object -First 120) -join "`n").Trim()
    }
}

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

Push-Location $repoRoot
try {
    $postgresFallbacks = @(
        'C:\Program Files\PostgreSQL\17\bin\psql.exe',
        'C:\Program Files\PostgreSQL\16\bin\psql.exe',
        'C:\Program Files\PostgreSQL\15\bin\psql.exe'
    )

    $resolved = [ordered]@{
        dotnet = Resolve-ToolPath 'dotnet'
        node = Resolve-ToolPath 'node'
        npm = Resolve-ToolPath 'npm'
        python = Resolve-ToolPath 'python'
        pwsh = Resolve-ToolPath 'pwsh'
        psql = Resolve-ToolPath 'psql' $postgresFallbacks
        pg_dump = Resolve-ToolPath 'pg_dump' @(
            'C:\Program Files\PostgreSQL\17\bin\pg_dump.exe',
            'C:\Program Files\PostgreSQL\16\bin\pg_dump.exe',
            'C:\Program Files\PostgreSQL\15\bin\pg_dump.exe'
        )
        pg_restore = Resolve-ToolPath 'pg_restore' @(
            'C:\Program Files\PostgreSQL\17\bin\pg_restore.exe',
            'C:\Program Files\PostgreSQL\16\bin\pg_restore.exe',
            'C:\Program Files\PostgreSQL\15\bin\pg_restore.exe'
        )
    }

    $probes = [ordered]@{
        dotnetInfo = Invoke-ToolProbe 'dotnet' $resolved.dotnet @('--info')
        nodeVersion = Invoke-ToolProbe 'node' $resolved.node @('--version')
        npmVersion = Invoke-ToolProbe 'npm' $resolved.npm @('--version')
        pythonVersion = Invoke-ToolProbe 'python' $resolved.python @('--version')
        pwshVersion = Invoke-ToolProbe 'pwsh' $resolved.pwsh @('--version')
        psqlVersion = Invoke-ToolProbe 'psql' $resolved.psql @('--version')
        pgDumpVersion = Invoke-ToolProbe 'pg_dump' $resolved.pg_dump @('--version')
        pgRestoreVersion = Invoke-ToolProbe 'pg_restore' $resolved.pg_restore @('--version')
    }

    foreach ($requiredProbe in @('dotnetInfo','nodeVersion','pythonVersion')) {
        Assert-Condition ([bool]$probes.$requiredProbe.present) "required runtime probe missing: $requiredProbe"
        Assert-Condition ([int]$probes.$requiredProbe.exitCode -eq 0) "required runtime probe failed: $requiredProbe"
    }

    $hostOutput = & (Join-Path $PSScriptRoot 'run-host-capability-diagnostic-contract.ps1') -Report $HostReportPath 6>&1 2>&1 | Out-String
    $workerOutput = & (Join-Path $PSScriptRoot 'run-worker-profile-diagnostic-contract.ps1') -Report $WorkerReportPath 6>&1 2>&1 | Out-String

    $hostReportFullPath = Join-Path $repoRoot $HostReportPath
    $workerReportFullPath = Join-Path $repoRoot $WorkerReportPath
    Assert-Condition (Test-Path -LiteralPath $hostReportFullPath) "host diagnostic report missing: $HostReportPath"
    Assert-Condition (Test-Path -LiteralPath $workerReportFullPath) "worker diagnostic report missing: $WorkerReportPath"

    $hostJson = Get-Content -LiteralPath $hostReportFullPath -Raw | ConvertFrom-Json
    $workerJson = Get-Content -LiteralPath $workerReportFullPath -Raw | ConvertFrom-Json

    $dataRoot = [string]$hostJson.config.dataRoot
    $backupRoot = [string]$hostJson.config.backupRoot
    $fileStoreRoot = if ([string]::IsNullOrWhiteSpace($dataRoot)) { '' } else { Join-Path $dataRoot 'file_store' }
    $logsRoot = if ([string]::IsNullOrWhiteSpace($dataRoot)) { '' } else { Join-Path $dataRoot 'logs' }
    $cacheRoot = if ([string]::IsNullOrWhiteSpace($dataRoot)) { '' } else { Join-Path $dataRoot 'cache' }

    $gaps = @()
    if (-not [bool]$probes.psqlVersion.present) { $gaps += 'postgresql_cli_missing' }
    if (-not [bool]$probes.pgDumpVersion.present) { $gaps += 'pg_dump_missing' }
    if (-not [bool]$probes.pgRestoreVersion.present) { $gaps += 'pg_restore_missing' }
    if (-not [bool]$hostJson.guardrail.noInstallPerformed) { $gaps += 'host_diagnostic_changed_install_state' }
    if (-not [bool]$workerJson.guardrail.noInstallPerformed) { $gaps += 'worker_diagnostic_changed_install_state' }

    $report = [ordered]@{
        status = 'pass'
        task = 'NS101 runtime profile refresh'
        checkedAt = (Get-Date).ToString('s')
        mode = 'read_only'
        guardrail = [ordered]@{
            noInstallPerformed = $true
            noNetworkRequired = $true
            productionDefaultChanged = $false
            secretsPrinted = $false
            externalAiUsed = $false
        }
        probes = $probes
        diagnosticReports = [ordered]@{
            hostCapability = $HostReportPath
            workerProfile = $WorkerReportPath
        }
        hostDiagnosticSummary = [ordered]@{
            schemaVersion = [string]$hostJson.schemaVersion
            runtimeProfile = [string]$hostJson.recommendedProfiles.runtimeProfile.recommended
            databaseProfile = [string]$hostJson.recommendedProfiles.databaseProfile.recommended
            workerOcrProfile = [string]$hostJson.recommendedProfiles.workerOcrProfile.recommended
            storageBackupProfile = [string]$hostJson.recommendedProfiles.storageBackupProfile.recommended
            exportPrintProfile = [string]$hostJson.recommendedProfiles.exportPrintProfile.recommended
            aiNetworkProfile = [string]$hostJson.recommendedProfiles.aiNetworkProfile.recommended
            aiLocalModelProfile = [string]$hostJson.recommendedProfiles.aiLocalModelProfile.recommended
            searchProfile = [string]$hostJson.recommendedProfiles.searchProfile.recommended
            queueProfile = [string]$hostJson.recommendedProfiles.queueProfile.recommended
            securityProfile = [string]$hostJson.recommendedProfiles.securityProfile.recommended
        }
        workerDiagnosticSummary = [ordered]@{
            schemaVersion = [string]$workerJson.schemaVersion
            recommendedDefaultProfile = [string]$workerJson.recommendation.recommendedDefaultProfile
            availableProfileCandidates = @($workerJson.recommendation.availableProfileCandidates)
            noInstallPerformed = [bool]$workerJson.guardrail.noInstallPerformed
            productionDefaultChanged = [bool]$workerJson.guardrail.productionDefaultChanged
        }
        dataDirectories = [ordered]@{
            dataRoot = $dataRoot
            backupRoot = $backupRoot
            fileStoreRoot = $fileStoreRoot
            logsRoot = $logsRoot
            cacheRoot = $cacheRoot
        }
        gaps = $gaps
        teacherEfficiencyCheck = 'runtime profile refresh reduces onsite uncertainty before teacher-facing import, export, analysis, backup, and worker flows are exercised'
        rollback = 'git restore tools/run-ns101-runtime-profile.ps1 tasks/non-site-implementation-plan.csv; git clean -f -- docs/evidence/20260528-ns101-runtime-profile.json docs/evidence/20260528-ns101-host-capability-diagnostic-report.json docs/evidence/20260528-ns101-worker-profile-diagnostic-report.json'
        hostDiagnosticOutput = $hostOutput.Trim()
        workerDiagnosticOutput = $workerOutput.Trim()
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent (Join-Path $repoRoot $ReportPath)) -Force | Out-Null
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $repoRoot $ReportPath) -Encoding UTF8
    [ordered]@{
        status = $report.status
        task = $report.task
        report = $ReportPath
        hostCapabilityReport = $HostReportPath
        workerProfileReport = $WorkerReportPath
        dotnet = (($probes.dotnetInfo.output -split "`n" | Where-Object { $_ -match 'Version:' } | Select-Object -First 1) -as [string]).Trim()
        node = [string]$probes.nodeVersion.output
        python = [string]$probes.pythonVersion.output
        postgresqlCli = [string]$probes.psqlVersion.output
        workerProfile = [string]$workerJson.recommendation.recommendedDefaultProfile
        gaps = $gaps
    } | ConvertTo-Json -Depth 5
}
finally {
    Pop-Location
}

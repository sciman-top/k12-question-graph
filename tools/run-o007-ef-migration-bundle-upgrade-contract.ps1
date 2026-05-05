param(
    [string]$DatabaseName = 'k12_question_graph',
    [string]$DatabaseUser = 'postgres',
    [string]$DatabaseHost = '127.0.0.1',
    [int]$DatabasePort = 5432,
    [string]$DatabasePassword = $env:PGPASSWORD,
    [string]$PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string]$ReportPath = 'docs/evidence/o007-ef-migration-bundle-upgrade-drill-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

function Assert-Condition([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function To-Relative([string]$Base, [string]$Path) {
    return [System.IO.Path]::GetRelativePath($Base, $Path).Replace('\\', '/')
}

Push-Location $repoRoot
try {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'DatabasePassword or PGPASSWORD is required for O007 drill'

    $workRoot = Join-Path $repoRoot 'tmp/o007'
    $bundleRoot = Join-Path $workRoot 'bundle'
    $releaseRoot = Join-Path $workRoot 'release-package'
    $migrationsPackageRoot = Join-Path $releaseRoot 'migrations'
    $backupRoot = Join-Path $workRoot 'backup-root'

    Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $bundleRoot, $migrationsPackageRoot, $backupRoot -Force | Out-Null

    dotnet tool restore | Write-Host
    Assert-Condition ($LASTEXITCODE -eq 0) 'dotnet tool restore failed'

    $bundleExe = Join-Path $bundleRoot 'efbundle.exe'
    dotnet ef migrations list --project apps/api/K12QuestionGraph.Api.csproj --startup-project apps/api/K12QuestionGraph.Api.csproj | Write-Host
    Assert-Condition ($LASTEXITCODE -eq 0) 'dotnet ef migrations list failed'

    dotnet ef migrations bundle --project apps/api/K12QuestionGraph.Api.csproj --startup-project apps/api/K12QuestionGraph.Api.csproj --target-runtime win-x64 --output $bundleExe | Write-Host
    Assert-Condition ($LASTEXITCODE -eq 0) 'dotnet ef migrations bundle failed'
    Assert-Condition (Test-Path -LiteralPath $bundleExe) 'efbundle.exe not found after bundle generation'

    Copy-Item -LiteralPath $bundleExe -Destination (Join-Path $migrationsPackageRoot 'efbundle.exe') -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'apps/api/appsettings.json') -Destination (Join-Path $migrationsPackageRoot 'appsettings.json') -Force

    $connectionString = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"

    $bundleOutputPath = Join-Path $workRoot 'efbundle-run.log'
    Push-Location $migrationsPackageRoot
    try {
        & .\efbundle.exe --connection $connectionString --verbose | Tee-Object -FilePath $bundleOutputPath | Out-Host
        Assert-Condition ($LASTEXITCODE -eq 0) 'efbundle execution failed'
    }
    finally {
        Pop-Location
    }

    $backupJson = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'backup.ps1') -BackupRoot $backupRoot -FileStoreRoot 'D:\KQG_Data\file_store' -PgBin $PgBin -DatabaseName $DatabaseName -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabaseUser $DatabaseUser
    Assert-Condition ($LASTEXITCODE -eq 0) 'backup.ps1 failed in O007 drill'
    $backup = $backupJson | ConvertFrom-Json

    & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'verify-backup.ps1') -ManifestPath $backup.manifest | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) 'verify-backup.ps1 failed in O007 drill'

    $o003ReportPath = 'docs/evidence/o007-o003-recovery-drill-report.json'
    & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'run-o003-recovery-drill-contract.ps1') -BackupRoot 'tmp/o007/o003-backup-root' -ReportPath $o003ReportPath -PgBin $PgBin -DatabaseName $DatabaseName -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabaseUser $DatabaseUser -DatabasePassword $DatabasePassword | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) 'embedded O003 recovery drill failed in O007'
    Assert-Condition (Test-Path -LiteralPath $o003ReportPath) 'missing embedded O003 report for O007'

    $report = [ordered]@{
        status = 'pass'
        task = 'O007'
        mode = 'draft_test'
        productionEligible = $false
        migrationBundle = [ordered]@{
            bundleExe = To-Relative -Base $repoRoot -Path $bundleExe
            releasePackageRoot = To-Relative -Base $repoRoot -Path $releaseRoot
            packageFiles = @(
                'migrations/efbundle.exe',
                'migrations/appsettings.json'
            )
            noSourceOrSdkRequiredAtExecution = $true
            executionLog = To-Relative -Base $repoRoot -Path $bundleOutputPath
        }
        upgradeDrill = [ordered]@{
            bundleRunExitCode = 0
            backupManifest = To-Relative -Base $repoRoot -Path $backup.manifest
            backupDir = To-Relative -Base $repoRoot -Path $backup.backupDir
            backupVerify = 'pass'
            restoreDrillReport = $o003ReportPath
        }
        rollback = [ordered]@{
            bundle = "Remove-Item -LiteralPath '$workRoot' -Recurse -Force"
            database = 'restore database from backup manifest before downstream production use'
            notes = 'if a real apply introduces incompatibility, restore database and file store from manifest, then rerun efbundle after fixing migration'
        }
        summaryChinese = [ordered]@{
            title = 'O007 EF migration bundle 与升级演练报告'
            result = '通过'
            boundary = '已验证 efbundle 可执行、备份可校验和隔离恢复演练链路；未执行生产环境不可逆变更。'
        }
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $ReportPath) -Force | Out-Null
    $json = $report | ConvertTo-Json -Depth 10
    $json | Set-Content -LiteralPath $ReportPath -Encoding UTF8
    $json
}
finally {
    Pop-Location
}

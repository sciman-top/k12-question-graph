param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [string] $LocalBackupRoot = 'tmp\g001-backups\local',
    [string] $SharedBackupRoot = 'tmp\g001-backups\shared',
    [string] $Report = 'docs\evidence\g001-backup-share-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw "DatabasePassword or PGPASSWORD is required for G001 backup/share contract"
}

Push-Location $repoRoot
try {
    $policyText = Get-Content -LiteralPath 'configs\backup_policy.defaults.yaml' -Raw
    Assert-Condition ($policyText -match 'network_share:') "backup policy must expose configurable network_share"
    Assert-Condition ($policyText -match 'no_mirror_delete_to_network_share:\s*true') "network share mirror-delete guard must be enabled"

    $runId = "$(Get-Date -Format 'yyyyMMdd-HHmmss')-$(([Guid]::NewGuid().ToString('N')).Substring(0, 8))"
    $localRunRoot = Join-Path $LocalBackupRoot $runId
    $sharedRunRoot = Join-Path $SharedBackupRoot $runId
    New-Item -ItemType Directory -Path $localRunRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $sharedRunRoot -Force | Out-Null

    $backup = .\tools\backup.ps1 `
        -BackupRoot $localRunRoot `
        -FileStoreRoot $FileStoreRoot `
        -PgBin $PgBin `
        -DatabaseName $DatabaseName `
        -DatabaseHost $DatabaseHost `
        -DatabasePort $DatabasePort `
        -DatabaseUser $DatabaseUser | ConvertFrom-Json

    $localVerify = .\tools\verify-backup.ps1 -ManifestPath $backup.manifest | ConvertFrom-Json
    Assert-Condition ($localVerify.status -eq 'ok') "local backup verification failed"

    $backupDirItem = Get-Item -LiteralPath $backup.backupDir
    $sharedBackupDir = Join-Path $sharedRunRoot $backupDirItem.Name
    Copy-Item -LiteralPath $backup.backupDir -Destination $sharedBackupDir -Recurse
    $sharedManifest = Join-Path $sharedBackupDir 'manifest.json'
    $sharedVerify = .\tools\verify-backup.ps1 -ManifestPath $sharedManifest | ConvertFrom-Json
    Assert-Condition ($sharedVerify.status -eq 'ok') "shared backup verification failed"

    $manifest = Get-Content -LiteralPath $backup.manifest -Raw | ConvertFrom-Json
    $sharedManifestObject = Get-Content -LiteralPath $sharedManifest -Raw | ConvertFrom-Json
    Assert-Condition ($manifest.database.sha256 -eq $sharedManifestObject.database.sha256) "shared database hash differs from local backup"
    Assert-Condition (@($manifest.configs).Count -gt 0) "backup manifest must include config files"

    $reportObject = [ordered]@{
        status = 'pass'
        task = 'G001'
        mode = 'draft_test'
        apiStarted = $false
        productionEligible = $false
        localBackupManifest = [System.IO.Path]::GetRelativePath($repoRoot, (Resolve-Path -LiteralPath $backup.manifest)).Replace('\', '/')
        sharedBackupManifest = [System.IO.Path]::GetRelativePath($repoRoot, (Resolve-Path -LiteralPath $sharedManifest)).Replace('\', '/')
        sharedBackupRootConfigurable = $true
        noMirrorDeleteToNetworkShare = $true
        localVerify = $localVerify
        sharedVerify = $sharedVerify
        databaseSha256 = [string]$manifest.database.sha256
        fileCount = [int]$localVerify.fileCount
        configCount = [int]$localVerify.configCount
        rollback = [ordered]@{
            local = 'delete the generated tmp/g001-backups run directory if this dry-run backup is no longer needed'
            shared = 'delete only the generated shared run directory; never mirror-delete the target share'
        }
        summaryChinese = [ordered]@{
            title = 'G001 自动备份到本机与共享目录合同报告'
            result = '通过'
            boundary = '仅做 draft/test 备份演练；不启动 Web/API 主程序，不删除共享目录既有内容。'
        }
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $Report) -Force | Out-Null
    $reportObject | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Report -Encoding UTF8
    $reportObject | ConvertTo-Json -Depth 10
}
finally {
    Pop-Location
}

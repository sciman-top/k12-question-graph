param(
    [string]$BackupRoot = 'tmp/o003/backup-root',
    [string]$FileStoreRoot = 'D:\KQG_Data\file_store',
    [string]$PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string]$DatabaseName = 'k12_question_graph',
    [string]$DatabaseHost = '127.0.0.1',
    [int]$DatabasePort = 5432,
    [string]$DatabaseUser = 'postgres',
    [string]$ReportPath = 'docs/evidence/o003-recovery-drill-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$drillRoot = Join-Path $repoRoot 'tmp/o003/restore-drill'

function Assert-Condition([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Copy-IfExists([string]$Source, [string]$DestinationRoot) {
    if (-not (Test-Path -LiteralPath $Source)) { return $null }
    $name = Split-Path -Leaf $Source
    $target = Join-Path $DestinationRoot $name
    Copy-Item -LiteralPath $Source -Destination $target -Recurse -Force
    return $target
}

function Convert-ToRelative([string]$Base, [string]$Path) {
    return [System.IO.Path]::GetRelativePath($Base, $Path).Replace('\\', '/')
}

Push-Location $repoRoot
try {
    Remove-Item -LiteralPath (Join-Path $repoRoot 'tmp/o003') -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $drillRoot -Force | Out-Null

    $backupJson = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'backup.ps1') -BackupRoot $BackupRoot -FileStoreRoot $FileStoreRoot -PgBin $PgBin -DatabaseName $DatabaseName -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabaseUser $DatabaseUser
    Assert-Condition ($LASTEXITCODE -eq 0) 'backup.ps1 failed during O003 drill'
    $backup = $backupJson | ConvertFrom-Json

    & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'verify-backup.ps1') -ManifestPath $backup.manifest | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) 'verify-backup.ps1 failed during O003 drill'

    $manifest = Get-Content -LiteralPath $backup.manifest -Raw | ConvertFrom-Json

    $pgRestore = Join-Path $PgBin 'pg_restore.exe'
    Assert-Condition (Test-Path -LiteralPath $pgRestore) "pg_restore not found: $pgRestore"

    $dbDrillRoot = Join-Path $drillRoot 'database'
    $fsDrillRoot = Join-Path $drillRoot 'file_store'
    $cfgDrillRoot = Join-Path $drillRoot 'configs'
    $tplDrillRoot = Join-Path $drillRoot 'templates'
    $prefDrillRoot = Join-Path $drillRoot 'teacher-preference'

    New-Item -ItemType Directory -Path $dbDrillRoot, $fsDrillRoot, $cfgDrillRoot, $tplDrillRoot, $prefDrillRoot -Force | Out-Null

    $restorePlanPath = Join-Path $dbDrillRoot 'database.restore-plan.txt'
    & $pgRestore -l $backup.databaseDump | Set-Content -LiteralPath $restorePlanPath -Encoding UTF8
    Assert-Condition ($LASTEXITCODE -eq 0) 'pg_restore -l failed'

    $schemaOnlyPath = Join-Path $dbDrillRoot 'database.schema-only.sql'
    & $pgRestore --schema-only --file $schemaOnlyPath $backup.databaseDump
    Assert-Condition ($LASTEXITCODE -eq 0) 'pg_restore --schema-only failed'
    Assert-Condition ((Get-Item -LiteralPath $schemaOnlyPath).Length -gt 0) 'schema-only output is empty'

    foreach ($file in @($manifest.fileStore.files)) {
        $src = Join-Path $manifest.fileStore.root $file.path
        $dst = Join-Path $fsDrillRoot $file.path
        $dstDir = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }

    $restoredConfigPaths = @()
    foreach ($config in @($manifest.configs)) {
        $src = Join-Path $repoRoot $config.path
        if (Test-Path -LiteralPath $src) {
            $dst = Join-Path $cfgDrillRoot $config.path
            $dstDir = Split-Path -Parent $dst
            if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
            Copy-Item -LiteralPath $src -Destination $dst -Force
            $restoredConfigPaths += $dst
        }
    }

    $templateSource = Join-Path $repoRoot 'docs/templates'
    if (Test-Path -LiteralPath $templateSource) {
        Copy-Item -Path (Join-Path $templateSource '*') -Destination $tplDrillRoot -Recurse -Force
    }

    $teacherPreferenceSource = Join-Path $repoRoot 'configs/teacher_preference.defaults.yaml'
    $teacherPreferenceRestored = Copy-IfExists -Source $teacherPreferenceSource -DestinationRoot $prefDrillRoot

    $report = [ordered]@{
        status = 'pass'
        task = 'O003'
        mode = 'draft_test'
        productionEligible = $false
        backup = [ordered]@{
            manifest = Convert-ToRelative -Base $repoRoot -Path $backup.manifest
            backupDir = Convert-ToRelative -Base $repoRoot -Path $backup.backupDir
            databaseDump = Convert-ToRelative -Base $repoRoot -Path $backup.databaseDump
            fileCount = [int]$backup.fileCount
            configCount = [int]$backup.configCount
        }
        recoveryDrill = [ordered]@{
            isolatedRoot = Convert-ToRelative -Base $repoRoot -Path $drillRoot
            database = [ordered]@{
                restorePlan = Convert-ToRelative -Base $repoRoot -Path $restorePlanPath
                schemaOnlySql = Convert-ToRelative -Base $repoRoot -Path $schemaOnlyPath
                pgRestoreListOk = $true
                schemaExtractOk = $true
            }
            fileStore = [ordered]@{
                restoredFileCount = @($manifest.fileStore.files).Count
                targetRoot = Convert-ToRelative -Base $repoRoot -Path $fsDrillRoot
            }
            configs = [ordered]@{
                restoredConfigCount = @($restoredConfigPaths).Count
                targetRoot = Convert-ToRelative -Base $repoRoot -Path $cfgDrillRoot
            }
            templates = [ordered]@{
                source = 'docs/templates'
                targetRoot = Convert-ToRelative -Base $repoRoot -Path $tplDrillRoot
                restored = (Test-Path -LiteralPath $templateSource)
            }
            teacherPreference = [ordered]@{
                source = 'configs/teacher_preference.defaults.yaml'
                target = $(if ($teacherPreferenceRestored) { Convert-ToRelative -Base $repoRoot -Path $teacherPreferenceRestored } else { '' })
                restored = ($null -ne $teacherPreferenceRestored)
            }
        }
        rollback = [ordered]@{
            deleteBackupRoot = "Remove-Item -LiteralPath '$((Resolve-Path -LiteralPath $BackupRoot).Path)' -Recurse -Force"
            deleteDrillRoot = "Remove-Item -LiteralPath '$drillRoot' -Recurse -Force"
        }
        summaryChinese = [ordered]@{
            title = 'O003 恢复演练升级合同报告'
            result = '通过'
            boundary = '在隔离目录完成 backup manifest 恢复演练，不改生产数据库与正式资产。'
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

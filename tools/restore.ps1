param(
    [Parameter(Mandatory)]
    [string] $ManifestPath,
    [string] $TargetDataRoot = 'D:\KQG_Data',
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabaseUser = 'postgres',
    [switch] $ApplyDatabase,
    [switch] $ApplyFileStore,
    [switch] $ApplyConfigs,
    [switch] $AllowOverlay,
    [switch] $PreRestoreSnapshotTaken,
    [switch] $DryRun = $true
)

$ErrorActionPreference = 'Stop'

# 现场强制闸门:在任何 New-Item/Copy-Item/pg_restore 之前调用与 verify-backup.ps1
# 相同的共享 fail-closed 验证器。历史 verify receipt 只是旁证,不能替代本次校验;
# 绕过 verify-backup 无法让无效 manifest 进入任何恢复动作。
. (Join-Path $PSScriptRoot 'backup-manifest-policy.ps1')
$validated = Read-ValidatedBackupManifest -ManifestPath $ManifestPath

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-EmptyTargetOrOverlayAuthorized([string] $TargetRoot, [bool] $OverlayAuthorized) {
    if (-not (Test-Path -LiteralPath $TargetRoot)) {
        return
    }

    $hasEntries = $null -ne (Get-ChildItem -LiteralPath $TargetRoot -Force | Select-Object -First 1)
    Assert-Condition (-not $hasEntries -or $OverlayAuthorized) "restore target is not empty; use -AllowOverlay only after taking a pre-restore snapshot: $TargetRoot"
}

$manifestRoot = $validated.ManifestRoot

$actions = [System.Collections.Generic.List[object]]::new()

if ($ApplyFileStore) {
    $targetDataRootFull = [System.IO.Path]::GetFullPath($TargetDataRoot)
    $targetFileStoreRoot = Resolve-BackupContainedPath -Root $targetDataRootFull -RelativePath 'file_store' -Description 'file store target'
    $actions.Add([ordered]@{ area = 'file_store'; mode = $(if($DryRun){'dry_run'}else{'apply'}); target = $targetFileStoreRoot; fileCount = @($validated.FileStoreSources).Count }) | Out-Null
    if (-not $DryRun) {
        Assert-EmptyTargetOrOverlayAuthorized -TargetRoot $targetFileStoreRoot -OverlayAuthorized $AllowOverlay
        New-Item -ItemType Directory -Path $targetFileStoreRoot -Force | Out-Null
        foreach ($file in $validated.FileStoreSources) {
            $dst = Resolve-BackupContainedPath -Root $targetFileStoreRoot -RelativePath $file.RelativePath -Description 'file store destination'
            $dstDir = Split-Path -Parent $dst
            if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
            Copy-Item -LiteralPath $file.SourcePath -Destination $dst -Force
        }
    }
}

if ($ApplyConfigs) {
    $targetDataRootFull = [System.IO.Path]::GetFullPath($TargetDataRoot)
    $targetConfigRoot = Resolve-BackupContainedPath -Root $targetDataRootFull -RelativePath 'recovery/configs' -Description 'config target'
    $actions.Add([ordered]@{ area = 'configs'; mode = $(if($DryRun){'dry_run'}else{'apply'}); target = $targetConfigRoot; fileCount = @($validated.ConfigSources).Count }) | Out-Null
    if (-not $DryRun) {
        Assert-EmptyTargetOrOverlayAuthorized -TargetRoot $targetConfigRoot -OverlayAuthorized $AllowOverlay
        New-Item -ItemType Directory -Path $targetConfigRoot -Force | Out-Null
        foreach ($config in $validated.ConfigSources) {
            $dst = Resolve-BackupContainedPath -Root $targetConfigRoot -RelativePath $config.RelativePath -Description 'config destination'
            $dstDir = Split-Path -Parent $dst
            if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
            Copy-Item -LiteralPath $config.SourcePath -Destination $dst -Force
        }
    }
}

if ($ApplyDatabase) {
    $pgRestore = Join-Path $PgBin 'pg_restore.exe'
    Assert-Condition (Test-Path -LiteralPath $pgRestore) "pg_restore not found: $pgRestore"
    # 数据库恢复的破坏性闸门与 -AllowOverlay 对目录的作用等价:apply 前必须显式
    # 声明已做恢复前快照(如 backup.ps1);--single-transaction 保证 pg_restore
    # 中途失败时原库不会停在半恢复状态。
    Assert-Condition ($DryRun -or $PreRestoreSnapshotTaken) 'database restore requires -PreRestoreSnapshotTaken: take a pre-restore snapshot (tools/backup.ps1) before applying'
    $actions.Add([ordered]@{ area = 'database'; mode = $(if($DryRun){'dry_run'}else{'apply'}); host = $DatabaseHost; port = $DatabasePort; database = $DatabaseName; user = $DatabaseUser; dump = $validated.DatabaseDumpPath; singleTransaction = $true }) | Out-Null
    if (-not $DryRun) {
        & $pgRestore -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName --clean --if-exists --single-transaction $validated.DatabaseDumpPath
        if ($LASTEXITCODE -ne 0) {
            throw "pg_restore failed with exit code $LASTEXITCODE"
        }
    }
}

[ordered]@{
    status = 'ok'
    mode = $(if($DryRun){'dry_run'}else{'apply'})
    manifest = $ManifestPath
    validationReceipt = New-BackupValidationReceipt -Validated $validated -Result 'pass'
    validated = [ordered]@{
        databaseDump = $validated.DatabaseDumpPath
        fileStoreCount = @($validated.FileStoreSources).Count
        configCount = @($validated.ConfigSources).Count
        templateCount = @($validated.TemplateSources).Count
        evidenceCount = @($validated.EvidenceSources).Count
    }
    actions = $actions
    # 策略 (b):DataRoot/config 密文配置不随恢复重建。恢复后 AI 处于
    # disabled/pending_review(无密钥即阻断真实调用),管理员需重新录入 AI
    # 路由设置与 provider secret,或从受控 secret source 注入。
    runtimeConfigRecovery = [ordered]@{
        aiRoutingSettings = 'manual_re_entry_required'
        providerSecrets = 'manual_re_entry_or_controlled_secret_source'
        postRestoreAiState = 'disabled_pending_review'
    }
} | ConvertTo-Json -Depth 8

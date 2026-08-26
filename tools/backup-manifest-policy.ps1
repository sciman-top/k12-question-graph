# Shared fail-closed backup-manifest validator.
#
# Both tools/verify-backup.ps1 (auditable receipt) and tools/restore.ps1
# (mandatory re-validation before any destructive action) MUST call
# Read-ValidatedBackupManifest from this file. Verification and execution are
# structurally decoupled but never decoupled at the safety boundary: bypassing
# verify-backup cannot let an invalid manifest reach Copy-Item / pg_restore.
$ErrorActionPreference = 'Stop'

$script:BackupManifestValidatorContractVersion = '2026-08-27.shared-validator.v1'
$script:BackupManifestSchemaPath = Join-Path $PSScriptRoot '..\schemas\backup_manifest.schema.json'

function Assert-BackupManifestCondition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Get-FileContentSha256([string] $Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Resolve-BackupContainedPath(
    [string] $Root,
    [string] $RelativePath,
    [string] $Description
) {
    Assert-BackupManifestCondition (-not [string]::IsNullOrWhiteSpace($RelativePath)) "$Description is required"
    Assert-BackupManifestCondition (-not [System.IO.Path]::IsPathRooted($RelativePath)) "$Description must be a relative path: $RelativePath"

    $fullRoot = [System.IO.Path]::GetFullPath($Root)
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $fullRoot $RelativePath))
    $rootPrefix = $fullRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $comparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    Assert-BackupManifestCondition ($candidate.StartsWith($rootPrefix, $comparison)) "$Description escapes its allowed root: $RelativePath"

    $current = $fullRoot
    foreach ($segment in [System.IO.Path]::GetRelativePath($fullRoot, $candidate).Split([System.IO.Path]::DirectorySeparatorChar, [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $current = Join-Path $current $segment
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            Assert-BackupManifestCondition (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) "$Description traverses a reparse point: $current"
        }
    }
    return $candidate
}

function Resolve-BackupManifestGroupRoot($Manifest, [string] $ManifestRoot, [string] $SnapshotPropertyName) {
    return Resolve-BackupContainedPath -Root $ManifestRoot -RelativePath ([string]$Manifest.$SnapshotPropertyName) -Description $SnapshotPropertyName
}

function Get-BackupManifestEntries($Manifest, [string] $PropertyName) {
    if (-not ($Manifest.PSObject.Properties.Name -contains $PropertyName)) {
        return
    }

    $entries = @($Manifest.$PropertyName | Where-Object { $null -ne $_ })
    foreach ($entry in $entries) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.path) -or
            [string]::IsNullOrWhiteSpace([string]$entry.sha256)) {
            throw "invalid manifest entry in '$PropertyName': path and sha256 are required"
        }
    }

    # Entries are emitted individually so callers capture them with @(...) -
    # empty output then becomes an empty collection at every call shape.
    return $entries
}

function Assert-UniqueBackupEntryPaths($Entries, [string] $Description) {
    $paths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($null -eq $Entries) {
        throw "$Description contains no entries"
    }

    foreach ($entry in $Entries) {
        Assert-BackupManifestCondition ($null -ne $entry) "$Description contains a null entry"
        $path = [string]$entry.path
        Assert-BackupManifestCondition ($paths.Add($path.Replace('\', '/'))) "$Description contains a duplicate path: $path"
    }
}

function Assert-BackupFileMatchesHash([string] $Path, [string] $ExpectedHash, [string] $Description) {
    Assert-BackupManifestCondition (Test-Path -LiteralPath $Path) "missing $Description`: $Path"
    $actual = Get-FileContentSha256 -Path $Path
    Assert-BackupManifestCondition ($actual -eq [string]$ExpectedHash) "$Description hash mismatch: $Path"
}

# 策略 (b) 受控排除声明必须存在且形状正确:缺失意味着这份备份产生于策略定案前,
# 或备份脚本漂移,恢复后 AI 密文配置的处置将无从追溯,fail-closed。
function Test-BackupRuntimeConfigPolicy($Manifest) {
    if (-not ($Manifest.PSObject.Properties.Name -contains 'runtimeConfig')) {
        throw 'unsupported_legacy_manifest: runtimeConfig exclusion declaration missing; legacy manifests cannot enter the current restore contract - re-run backup.ps1 or follow the explicitly authorized legacy-manifest reissue process'
    }

    $runtimeConfig = $Manifest.runtimeConfig
    if ([string]$runtimeConfig.area -ne 'data_root_config' -or
        [string]$runtimeConfig.exclusionPolicy -ne 'manual_re_entry_required' -or
        [string]$runtimeConfig.aiRoutingSettings -ne 'manual_re_entry_required' -or
        @('manual_re_entry_required', 'controlled_secret_source_injection') -notcontains [string]$runtimeConfig.providerSecrets -or
        [string]$runtimeConfig.postRestoreAiState -ne 'disabled_pending_review') {
        throw 'unsupported_legacy_manifest: runtimeConfig exclusion declaration invalid - area/exclusionPolicy/aiRoutingSettings/providerSecrets/postRestoreAiState must follow policy b'
    }

    # Policy digest binds the receipt to the exact accepted policy values.
    $canonicalPolicy = 'data_root_config|manual_re_entry_required|manual_re_entry_required|' +
        [string]$runtimeConfig.providerSecrets + '|disabled_pending_review|' + $script:BackupManifestValidatorContractVersion
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonicalPolicy)
    return ([System.Security.Cryptography.SHA256]::HashData($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
}

# The single validation entrypoint. Returns a validated record or throws.
function Read-ValidatedBackupManifest([Parameter(Mandatory)] [string] $ManifestPath) {
    Assert-BackupManifestCondition (Test-Path -LiteralPath $ManifestPath) "manifest not found: $ManifestPath"
    $manifestItem = Get-Item -LiteralPath $ManifestPath
    $manifestRoot = $manifestItem.DirectoryName
    $manifestJson = Get-Content -LiteralPath $ManifestPath -Raw

    $manifestHash = Get-FileContentSha256 -Path $ManifestPath
    try {
        $manifest = $manifestJson | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "unsupported_legacy_manifest: manifest is not valid JSON ($($_.Exception.Message))"
    }

    Assert-BackupManifestCondition (Test-Path -LiteralPath $script:BackupManifestSchemaPath) "backup manifest schema not found: $($script:BackupManifestSchemaPath)"
    Assert-BackupManifestCondition (Test-Json -Json $manifestJson -SchemaFile $script:BackupManifestSchemaPath -ErrorAction SilentlyContinue) 'unsupported_legacy_manifest: backup manifest schema validation failed against the current contract'
    $runtimeConfigPolicyDigest = Test-BackupRuntimeConfigPolicy -Manifest $manifest

    # fileStore.files is nested and required by schema; the flat optional
    # groups go through Get-BackupManifestEntries so absent properties do not
    # turn into null entries.
    Assert-UniqueBackupEntryPaths -Entries (@($manifest.fileStore.files) | Where-Object { $null -ne $_ }) -Description 'fileStore.files'
    Assert-UniqueBackupEntryPaths -Entries (@(Get-BackupManifestEntries -Manifest $manifest -PropertyName 'configs')) -Description 'configs'
    Assert-UniqueBackupEntryPaths -Entries (@(Get-BackupManifestEntries -Manifest $manifest -PropertyName 'templates')) -Description 'templates'
    Assert-UniqueBackupEntryPaths -Entries (@(Get-BackupManifestEntries -Manifest $manifest -PropertyName 'evidence')) -Description 'evidence'

    $databaseDumpPath = Resolve-BackupContainedPath -Root $manifestRoot -RelativePath ([string]$manifest.database.dump) -Description 'database.dump'
    Assert-BackupFileMatchesHash -Path $databaseDumpPath -ExpectedHash $manifest.database.sha256 -Description 'database dump'

    $fileStoreBackupRoot = Resolve-BackupContainedPath -Root $manifestRoot -RelativePath ([string]$manifest.fileStore.snapshotRoot) -Description 'fileStore.snapshotRoot'
    $fileStoreSources = @()
    foreach ($file in @($manifest.fileStore.files | Where-Object { $null -ne $_ })) {
        $src = Resolve-BackupContainedPath -Root $fileStoreBackupRoot -RelativePath ([string]$file.path) -Description 'fileStore.files.path'
        Assert-BackupFileMatchesHash -Path $src -ExpectedHash $file.sha256 -Description 'file store source file'
        $fileStoreSources += [pscustomobject]@{ RelativePath = [string]$file.path; SourcePath = $src }
    }

    $configBackupRoot = Resolve-BackupManifestGroupRoot -Manifest $manifest -ManifestRoot $manifestRoot -SnapshotPropertyName 'configsSnapshotRoot'
    $configSources = @()
    foreach ($config in @(Get-BackupManifestEntries -Manifest $manifest -PropertyName 'configs')) {
        $src = Resolve-BackupContainedPath -Root $configBackupRoot -RelativePath ([string]$config.path) -Description 'configs.path'
        Assert-BackupFileMatchesHash -Path $src -ExpectedHash $config.sha256 -Description 'config source file'
        $configSources += [pscustomobject]@{ RelativePath = [string]$config.path; SourcePath = $src }
    }

    $templateBackupRoot = Resolve-BackupManifestGroupRoot -Manifest $manifest -ManifestRoot $manifestRoot -SnapshotPropertyName 'templatesSnapshotRoot'
    $templateSources = @()
    foreach ($template in @(Get-BackupManifestEntries -Manifest $manifest -PropertyName 'templates')) {
        $src = Resolve-BackupContainedPath -Root $templateBackupRoot -RelativePath ([string]$template.path) -Description 'templates.path'
        Assert-BackupFileMatchesHash -Path $src -ExpectedHash $template.sha256 -Description 'template source file'
        $templateSources += [pscustomobject]@{ RelativePath = [string]$template.path; SourcePath = $src }
    }

    $evidenceBackupRoot = $null
    $evidenceSources = @()
    $evidenceEntries = Get-BackupManifestEntries -Manifest $manifest -PropertyName 'evidence'
    if ($evidenceEntries.Count -gt 0) {
        $evidenceBackupRoot = Resolve-BackupManifestGroupRoot -Manifest $manifest -ManifestRoot $manifestRoot -SnapshotPropertyName 'evidenceSnapshotRoot'
        foreach ($evidence in $evidenceEntries) {
            $src = Resolve-BackupContainedPath -Root $evidenceBackupRoot -RelativePath ([string]$evidence.path) -Description 'evidence.path'
            Assert-BackupFileMatchesHash -Path $src -ExpectedHash $evidence.sha256 -Description 'evidence source file'
            $evidenceSources += [pscustomobject]@{ RelativePath = [string]$evidence.path; SourcePath = $src }
        }
    }

    return [pscustomobject]@{
        ManifestPath = $manifestItem.FullName
        ManifestRoot = $manifestRoot
        ManifestHash = $manifestHash
        ValidatorContractVersion = $script:BackupManifestValidatorContractVersion
        RuntimeConfigPolicyDigest = $runtimeConfigPolicyDigest
        ValidatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        DatabaseDumpPath = $databaseDumpPath
        FileStoreBackupRoot = $fileStoreBackupRoot
        FileStoreSources = $fileStoreSources
        ConfigBackupRoot = $configBackupRoot
        ConfigSources = $configSources
        TemplateBackupRoot = $templateBackupRoot
        TemplateSources = $templateSources
        EvidenceBackupRoot = $evidenceBackupRoot
        EvidenceSources = $evidenceSources
    }
}

# Receipt shape shared by both entrypoints. Pass/fail is decided by the caller;
# a receipt is audit evidence, never an authorization to execute a restore.
function New-BackupValidationReceipt($Validated, [string] $Result, [string] $Reason = '') {
    return [ordered]@{
        status = $Result
        reason = $Reason
        manifest = $(if ($null -ne $Validated) { $Validated.ManifestPath } else { $null })
        manifestHash = $(if ($null -ne $Validated) { $Validated.ManifestHash } else { $null })
        validatorContractVersion = $(if ($null -ne $Validated) { $Validated.ValidatorContractVersion } else { $script:BackupManifestValidatorContractVersion })
        runtimeConfigPolicyDigest = $(if ($null -ne $Validated) { $Validated.RuntimeConfigPolicyDigest } else { $null })
        validatedAtUtc = $(if ($null -ne $Validated) { $Validated.ValidatedAtUtc } else { (Get-Date).ToUniversalTime().ToString('o') })
    }
}

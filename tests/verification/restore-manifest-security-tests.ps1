$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$restoreScript = Join-Path $repoRoot 'tools\restore.ps1'
$testRoot = Join-Path $repoRoot 'tmp\restore-manifest-security-tests'

function Write-TestManifest([string] $Root, [string] $FilePath, [switch] $LegacyNoRuntimeConfig) {
    $dumpPath = Join-Path $Root 'database.dump'
    $fileStoreRoot = Join-Path $Root 'file_store'
    $configRoot = Join-Path $Root 'configs'
    New-Item -ItemType Directory -Path $fileStoreRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $configRoot -Force | Out-Null
    Set-Content -LiteralPath $dumpPath -Value 'synthetic-dump' -NoNewline
    $dumpHash = (Get-FileHash -LiteralPath $dumpPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $fileHash = '0' * 64
    if ($FilePath -eq 'safe.txt') {
        $safePath = Join-Path $fileStoreRoot $FilePath
        Set-Content -LiteralPath $safePath -Value 'x' -NoNewline
        $fileHash = (Get-FileHash -LiteralPath $safePath -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    $manifest = [ordered]@{
        version = 1
        createdAt = '2026-08-20T00:00:00Z'
        database = [ordered]@{
            engine = 'postgresql'
            databaseName = 'synthetic'
            dump = 'database.dump'
            sha256 = $dumpHash
        }
        fileStore = [ordered]@{
            snapshotRoot = 'file_store'
            sourceRoot = 'synthetic'
            root = 'synthetic'
            files = @([ordered]@{
                path = $FilePath
                bytes = 1
                sha256 = $fileHash
            })
        }
        configsSnapshotRoot = 'configs'
        configs = @()
        templatesSnapshotRoot = 'templates'
        templates = @()
    }
    if (-not $LegacyNoRuntimeConfig) {
        $manifest.runtimeConfig = [ordered]@{
            area = 'data_root_config'
            exclusionPolicy = 'manual_re_entry_required'
            aiRoutingSettings = 'manual_re_entry_required'
            providerSecrets = 'manual_re_entry_required'
            postRestoreAiState = 'disabled_pending_review'
        }
    }

    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Root 'manifest.json') -Encoding utf8
}

if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    Write-TestManifest -Root $testRoot -FilePath 'safe.txt'
    $validOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File $restoreScript `
        -ManifestPath (Join-Path $testRoot 'manifest.json') `
        -ApplyFileStore `
        -DryRun 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $validOutput -notmatch '"status":\s*"ok"') {
        throw "valid manifest dry-run failed: $validOutput"
    }
    if ($validOutput -notmatch 'validatorContractVersion' -or $validOutput -notmatch 'runtimeConfigPolicyDigest') {
        throw "restore output is missing the in-place validation receipt fields: $validOutput"
    }

    # verify-backup 的 receipt 是旁证;它绝不能替代 restore 的现场强制验证。
    # 缺 runtimeConfig 的 legacy manifest 即使 verify 曾"通过",restore 也必须拒绝。
    Write-TestManifest -Root $testRoot -FilePath 'safe.txt' -LegacyNoRuntimeConfig
    $legacyRestoreOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File $restoreScript `
        -ManifestPath (Join-Path $testRoot 'manifest.json') `
        -ApplyFileStore `
        -DryRun 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -or $legacyRestoreOutput -notmatch 'unsupported_legacy_manifest') {
        throw "legacy manifest without runtimeConfig was not rejected by restore: $legacyRestoreOutput"
    }

    $legacyVerifyOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'tools\verify-backup.ps1') `
        -ManifestPath (Join-Path $testRoot 'manifest.json') 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -or $legacyVerifyOutput -notmatch 'unsupported_legacy_manifest' -or $legacyVerifyOutput -notmatch '"status":\s*"fail"') {
        throw "verify-backup did not emit a fail receipt for the legacy manifest: $legacyVerifyOutput"
    }

    Write-TestManifest -Root $testRoot -FilePath 'safe.txt'
    $verifyPassOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'tools\verify-backup.ps1') `
        -ManifestPath (Join-Path $testRoot 'manifest.json') 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $verifyPassOutput -notmatch '"status":\s*"pass"' -or $verifyPassOutput -notmatch 'manifestHash') {
        throw "verify-backup pass receipt is missing required fields: $verifyPassOutput"
    }

    Write-TestManifest -Root $testRoot -FilePath '..\..\outside.txt'

    $output = & pwsh -NoProfile -ExecutionPolicy Bypass -File $restoreScript `
        -ManifestPath (Join-Path $testRoot 'manifest.json') `
        -ApplyFileStore `
        -DryRun 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -or $output -notmatch 'escapes its allowed root') {
        throw "path traversal manifest was not rejected as expected: $output"
    }

    Write-TestManifest -Root $testRoot -FilePath 'C:outside.txt'
    $driveRelativeOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File $restoreScript `
        -ManifestPath (Join-Path $testRoot 'manifest.json') `
        -ApplyFileStore `
        -DryRun 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        throw "drive-relative manifest path was not rejected: $driveRelativeOutput"
    }

    [pscustomobject]@{
        status = 'pass'
        validDryRunPassed = $true
        inPlaceValidationReceiptPresent = $true
        legacyManifestRejectedByRestore = $true
        legacyManifestFailReceiptEmittedByVerify = $true
        verifyPassReceiptPresent = $true
        traversalRejected = $true
        driveRelativePathRejected = $true
        applyPerformed = $false
    } | ConvertTo-Json -Compress
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

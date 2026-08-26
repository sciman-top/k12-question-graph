$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$reissueScript = Join-Path $repoRoot 'tools\reissue-legacy-backup-manifest.ps1'
$testRoot = Join-Path $repoRoot 'tmp\backup-manifest-reissue-tests'

function New-SnapshotFixture([string] $Root) {
    $fileStoreRoot = Join-Path $Root 'file_store'
    New-Item -ItemType Directory -Path $fileStoreRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $Root 'database.dump') -Value 'synthetic-dump' -NoNewline
    Set-Content -LiteralPath (Join-Path $fileStoreRoot 'safe.txt') -Value 'x' -NoNewline

    $dumpHash = (Get-FileHash -LiteralPath (Join-Path $Root 'database.dump') -Algorithm SHA256).Hash.ToLowerInvariant()
    $fileHash = (Get-FileHash -LiteralPath (Join-Path $fileStoreRoot 'safe.txt') -Algorithm SHA256).Hash.ToLowerInvariant()
    return [ordered]@{
        version = 1
        createdAt = '2026-01-01T00:00:00Z'
        database = [ordered]@{
            engine = 'postgresql'
            databaseName = 'synthetic'
            dump = 'database.dump'
            sha256 = $dumpHash
        }
        fileStore = [ordered]@{
            snapshotRoot = 'file_store'
            files = @([ordered]@{ path = 'safe.txt'; bytes = 1; sha256 = $fileHash })
        }
        configsSnapshotRoot = 'configs'
        configs = @()
        templatesSnapshotRoot = 'templates'
        templates = @()
    }
}

if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

    # Case 1: happy path. Legacy manifest reissues and the emitted file must
    # pass the shared validator without any post-write mutation.
    $legacyDir = Join-Path $testRoot 'case1'
    New-Item -ItemType Directory -Path $legacyDir | Out-Null
    $fixture = New-SnapshotFixture -Root $legacyDir
    ($fixture | ConvertTo-Json -Depth 8) |
        Set-Content -LiteralPath (Join-Path $legacyDir 'manifest.json') -Encoding utf8

    $missingAttestation = & pwsh -NoProfile -ExecutionPolicy Bypass -File $reissueScript `
        -ManifestPath (Join-Path $legacyDir 'manifest.json') `
        -OutputManifestPath (Join-Path $legacyDir 'manifest.reissued.json') 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -or $missingAttestation -notmatch '-ConfirmPayloadAndSensitiveReview') {
        throw "reissue without operator attestation was not rejected: $missingAttestation"
    }

    $output = & pwsh -NoProfile -ExecutionPolicy Bypass -File $reissueScript `
        -ManifestPath (Join-Path $legacyDir 'manifest.json') `
        -OutputManifestPath (Join-Path $legacyDir 'manifest.reissued.json') `
        -ConfirmPayloadAndSensitiveReview 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $output -notmatch '"action":\s*"legacy_manifest_reissue"' -or $output -notmatch 'runtimeConfigPolicyDigest') {
        throw "legacy reissue failed: $output"
    }
    $reissueReceipt = $output | ConvertFrom-Json
    if ($reissueReceipt.manifest -ne (Join-Path $legacyDir 'manifest.reissued.json') -or
        -not (Test-Path -LiteralPath $reissueReceipt.manifest)) {
        throw "legacy reissue receipt does not identify the durable output manifest: $output"
    }

    $verifyOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'tools\verify-backup.ps1') `
        -ManifestPath (Join-Path $legacyDir 'manifest.reissued.json') 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $verifyOutput -notmatch '"status":\s*"pass"') {
        throw "reissued manifest does not pass verify-backup: $verifyOutput"
    }

    # Case 2: an already-supported manifest is refused outright.
    $supportedDir = Join-Path $testRoot 'case2'
    New-Item -ItemType Directory -Path $supportedDir | Out-Null
    $fixture = New-SnapshotFixture -Root $supportedDir
    $fixture.runtimeConfig = [ordered]@{
        area = 'data_root_config'
        exclusionPolicy = 'manual_re_entry_required'
        aiRoutingSettings = 'manual_re_entry_required'
        providerSecrets = 'manual_re_entry_required'
        postRestoreAiState = 'disabled_pending_review'
    }
    ($fixture | ConvertTo-Json -Depth 8) |
        Set-Content -LiteralPath (Join-Path $supportedDir 'manifest.json') -Encoding utf8

    $alreadySupported = & pwsh -NoProfile -ExecutionPolicy Bypass -File $reissueScript `
        -ManifestPath (Join-Path $supportedDir 'manifest.json') `
        -OutputManifestPath (Join-Path $supportedDir 'manifest.reissued.json') `
        -ConfirmPayloadAndSensitiveReview 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -or $alreadySupported -notmatch 'do not reissue') {
        throw "already-supported manifest was not refused: $alreadySupported"
    }

    # Case 3: tampered payload aborts; no output file may appear.
    $tamperDir = Join-Path $testRoot 'case3'
    New-Item -ItemType Directory -Path $tamperDir | Out-Null
    $fixture = New-SnapshotFixture -Root $tamperDir
    ($fixture | ConvertTo-Json -Depth 8) |
        Set-Content -LiteralPath (Join-Path $tamperDir 'manifest.json') -Encoding utf8
    Set-Content -LiteralPath (Join-Path $tamperDir 'database.dump') -Value 'tampered-dump' -NoNewline

    $tampered = & pwsh -NoProfile -ExecutionPolicy Bypass -File $reissueScript `
        -ManifestPath (Join-Path $tamperDir 'manifest.json') `
        -OutputManifestPath (Join-Path $tamperDir 'manifest.reissued.json') `
        -ConfirmPayloadAndSensitiveReview 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -or $tampered -notmatch 'hash mismatch') {
        throw "tampered payload was not rejected during reissue: $tampered"
    }
    if ((Test-Path -LiteralPath (Join-Path $tamperDir 'manifest.reissued.json')) -or
        (Test-Path -LiteralPath (Join-Path $tamperDir 'manifest.reissued.json.reissue-pending'))) {
        throw "tampered reissue left output artifacts behind"
    }

    [pscustomobject]@{
        status = 'pass'
        attestationRequired = $true
        legacyReissuePassesSharedValidator = $true
        receiptPointsToDurableOutput = $true
        alreadySupportedRefused = $true
        tamperedPayloadAbortsCleanly = $true
    } | ConvertTo-Json -Compress
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

# Explicitly authorized migration entrypoint for pre-policy backup manifests.
#
# The current restore contract (tools/restore.ps1) rejects legacy manifests
# outright; this script is the ONLY sanctioned bridge. It requires an operator
# acknowledgment that payload contents and sensitive-config exclusions were
# manually reviewed, regenerates a policy-b runtimeConfig declaration, and
# runs the SAME shared fail-closed validator over the emitted file before it
# may be used as input to verify-backup / restore. It never silently fixes a
# payload: any hash or structural failure aborts the reissue.
param(
    [Parameter(Mandatory)]
    [string] $ManifestPath,
    [Parameter(Mandatory)]
    [string] $OutputManifestPath,
    # Operator attestation: the snapshot payload was reviewed and contains no
    # sensitive runtime ciphertext that policy b would exclude.
    [switch] $ConfirmPayloadAndSensitiveReview,
    [switch] $AllowOverwriteOutput
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'backup-manifest-policy.ps1')

if (-not $ConfirmPayloadAndSensitiveReview) {
    throw 'legacy manifest reissue requires -ConfirmPayloadAndSensitiveReview: review the snapshot payload, sensitive config exclusion, and current runtime policy before generating a supported manifest'
}

Assert-BackupManifestCondition (Test-Path -LiteralPath $ManifestPath) "source manifest not found: $ManifestPath"
$outputFull = [System.IO.Path]::GetFullPath($OutputManifestPath)
Assert-BackupManifestCondition ((Test-Path -LiteralPath ([System.IO.Path]::GetDirectoryName($outputFull)))) "output directory does not exist: $([System.IO.Path]::GetDirectoryName($outputFull))"
if (Test-Path -LiteralPath $outputFull) {
    Assert-BackupManifestCondition ($AllowOverwriteOutput) "output manifest already exists; pass -AllowOverwriteOutput only when replacing it intentionally: $outputFull"
}
Assert-BackupManifestCondition (
    [System.IO.Path]::GetFullPath($ManifestPath) -ne $outputFull) 'output manifest must differ from the source manifest'

$manifestJson = Get-Content -LiteralPath $ManifestPath -Raw
try {
    $legacy = $manifestJson | ConvertFrom-Json -ErrorAction Stop
} catch {
    throw "unsupported_legacy_manifest: source manifest is not valid JSON ($($_.Exception.Message))"
}

if ($legacy.PSObject.Properties.Name -contains 'runtimeConfig') {
    throw 'unsupported_legacy_manifest: source already declares runtimeConfig; do not reissue - run tools/verify-backup.ps1 against it instead'
}

# Structural floor before touching anything: everything except runtimeConfig
# must be present so the emitted file can only fail for hash-level reasons,
# which the final validator then proves exhaustively.
foreach ($requiredProperty in @('version', 'createdAt', 'database', 'fileStore', 'configsSnapshotRoot', 'configs', 'templatesSnapshotRoot', 'templates')) {
    Assert-BackupManifestCondition ($legacy.PSObject.Properties.Name -contains $requiredProperty) "unsupported_legacy_manifest: source manifest is missing required property '$requiredProperty'"
}
Assert-BackupManifestCondition ([int]$legacy.version -eq 1) "unsupported_legacy_manifest: unexpected manifest version $([int]$legacy.version)"

$supported = $legacy.PSObject.Copy()
# The source never declares runtimeConfig; add the policy-b declaration fresh.
$supported | Add-Member -NotePropertyName runtimeConfig -NotePropertyValue ([ordered]@{
    area = 'data_root_config'
    exclusionPolicy = 'manual_re_entry_required'
    aiRoutingSettings = 'manual_re_entry_required'
    providerSecrets = 'manual_re_entry_required'
    postRestoreAiState = 'disabled_pending_review'
    note = 'Reissued from a legacy manifest under explicitly authorized migration; DataRoot/config runtime ciphertext remains excluded by policy b.'
})
$supportedJson = $supported | ConvertTo-Json -Depth 12

# Write first to a sibling temp file, then validate the bytes that will ship;
# only a fully passing validation promotes the temp file onto the output path.
$tempOutputPath = "$outputFull.reissue-pending"
try {
    $supportedJson | Set-Content -LiteralPath $tempOutputPath -Encoding utf8
    $validated = Read-ValidatedBackupManifest -ManifestPath $tempOutputPath
    Move-Item -LiteralPath $tempOutputPath -Destination $outputFull -Force:$AllowOverwriteOutput.IsPresent
} catch {
    if (Test-Path -LiteralPath $tempOutputPath) {
        Remove-Item -LiteralPath $tempOutputPath -Force
    }
    throw
}

[ordered]@{
    status = 'pass'
    action = 'legacy_manifest_reissue'
    reason = ''
    sourceManifest = $ManifestPath
    sourceManifestHash = Get-FileContentSha256 -Path $ManifestPath
    manifest = $validated.ManifestPath
    manifestHash = $validated.ManifestHash
    validatorContractVersion = $validated.ValidatorContractVersion
    runtimeConfigPolicyDigest = $validated.RuntimeConfigPolicyDigest
    validatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    operatorAttestation = @{
        payloadAndSensitiveExclusionReviewed = $true
        restoredAiStateRemainsDisabledPendingReview = $true
    }
} | ConvertTo-Json -Depth 4 -Compress

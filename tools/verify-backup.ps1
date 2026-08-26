# Audit-only verification entrypoint. Produces a receipt; never authorizes
# execution. tools/restore.ps1 calls the same shared validator itself before
# any destructive action, so skipping this script cannot bypass validation.
param(
    [Parameter(Mandatory)]
    [string] $ManifestPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'backup-manifest-policy.ps1')

$validated = $null
try {
    $validated = Read-ValidatedBackupManifest -ManifestPath $ManifestPath
} catch {
    $failReceipt = New-BackupValidationReceipt -Validated $null -Result 'fail' -Reason $_.Exception.Message
    $failReceipt | ConvertTo-Json -Compress
    throw
}

[pscustomobject]$receipt = New-BackupValidationReceipt -Validated $validated -Result 'pass'
$receipt.fileCount = @($validated.FileStoreSources).Count
$receipt.configCount = @($validated.ConfigSources).Count
$receipt.templateCount = @($validated.TemplateSources).Count
$receipt.evidenceCount = @($validated.EvidenceSources).Count
# receipt 只作日志与交接旁证;restore 的执行授权由其自身现场强制验证决定。
$receipt.authorizationNote = 'audit evidence only; restore.ps1 re-validates in place before executing'

$receipt | ConvertTo-Json -Depth 4 -Compress

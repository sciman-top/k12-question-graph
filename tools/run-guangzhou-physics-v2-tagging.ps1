param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $BackupManifest = '',
    [switch] $Apply,
    [string] $ReportPath = '',
    [string] $MarkdownReportPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for Guangzhou physics v2 tagging'
}
if ($Apply) {
    if ([string]::IsNullOrWhiteSpace($BackupManifest) -or -not (Test-Path -LiteralPath $BackupManifest -PathType Leaf)) {
        throw 'Apply requires a verified prewrite BackupManifest'
    }
    $verify = & (Join-Path $PSScriptRoot 'verify-backup.ps1') -ManifestPath $BackupManifest | ConvertFrom-Json
    if ($verify.status -ne 'ok') { throw "Backup verification failed: $BackupManifest" }
}
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $suffix = if ($Apply) { 'tagging' } else { 'tagging-dry-run' }
    $ReportPath = ('docs/evidence/{0}-guangzhou-physics-v2-{1}.json' -f (Get-Date -Format 'yyyyMMdd'), $suffix)
}
if ([string]::IsNullOrWhiteSpace($MarkdownReportPath)) {
    $suffix = if ($Apply) { 'tagging' } else { 'tagging-dry-run' }
    $MarkdownReportPath = ('docs/evidence/{0}-guangzhou-physics-v2-{1}.md' -f (Get-Date -Format 'yyyyMMdd'), $suffix)
}

$previousPassword = $env:PGPASSWORD
try {
    $env:PGPASSWORD = $DatabasePassword
    Push-Location $repoRoot
    $arguments = @(
        'tools\guangzhou_physics_v2_tagging.py',
        '--host', $DatabaseHost,
        '--port', [string]$DatabasePort,
        '--database', $DatabaseName,
        '--user', $DatabaseUser,
        '--output', $ReportPath,
        '--markdown-output', $MarkdownReportPath
    )
    if ($Apply) {
        $arguments += @('--apply', '--backup-manifest', (Resolve-Path -LiteralPath $BackupManifest).Path)
    }
    & python @arguments
    if ($LASTEXITCODE -ne 0) { throw "Guangzhou physics v2 tagging failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
    $env:PGPASSWORD = $previousPassword
}

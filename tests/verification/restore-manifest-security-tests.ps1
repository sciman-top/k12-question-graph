$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$restoreScript = Join-Path $repoRoot 'tools\restore.ps1'
$testRoot = Join-Path $repoRoot 'tmp\restore-manifest-security-tests'

function Write-TestManifest([string] $Root, [string] $FilePath) {
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

    [ordered]@{
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
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Root 'manifest.json') -Encoding utf8
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

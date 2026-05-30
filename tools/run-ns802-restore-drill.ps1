param(
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $RestoreRoot = 'tmp\ns802-restore',
    [string] $ReportPath = 'docs/evidence/20260530-ns802-restore-drill-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Read-Json([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing report: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Compute-Sha256([string] $Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function To-RepoRelative([string] $Path) {
    return [System.IO.Path]::GetRelativePath($repoRoot, (Resolve-Path -LiteralPath $Path)).Replace('\', '/')
}

function Resolve-FileStoreBackupRoot($Manifest, [string] $ManifestPath) {
    if ($Manifest.fileStore.PSObject.Properties.Name -contains 'snapshotRoot' -and
        -not [string]::IsNullOrWhiteSpace([string]$Manifest.fileStore.snapshotRoot)) {
        $manifestRoot = (Get-Item -LiteralPath $ManifestPath).DirectoryName
        return Join-Path $manifestRoot ([string]$Manifest.fileStore.snapshotRoot)
    }

    return [string]$Manifest.fileStore.root
}

function Copy-ManifestGroup($Items, [string] $TargetRoot) {
    $restored = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($Items)) {
        $src = Join-Path $repoRoot $item.path
        Assert-Condition (Test-Path -LiteralPath $src) "missing manifest group source: $src"
        Assert-Condition ((Compute-Sha256 $src) -eq [string]$item.sha256) "source hash mismatch before restore: $($item.path)"
        $dst = Join-Path $TargetRoot $item.path
        $dstDir = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $dstDir)) {
            New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $src -Destination $dst -Force
        Assert-Condition ((Compute-Sha256 $dst) -eq [string]$item.sha256) "restored hash mismatch: $dst"
        $restored.Add([ordered]@{ path = $item.path; sha256 = [string]$item.sha256 }) | Out-Null
    }

    return $restored.ToArray()
}

Push-Location $repoRoot
try {
    $ns801 = Read-Json 'docs/evidence/20260530-ns801-backup-manifest-report.json'
    Assert-Condition ($ns801.status -eq 'pass') 'NS802 dependency NS801 report did not pass'
    $manifestPath = Join-Path $repoRoot ([string]$ns801.backup.manifest)
    Assert-Condition (Test-Path -LiteralPath $manifestPath) "NS802 backup manifest missing: $manifestPath"

    $verify = .\tools\verify-backup.ps1 -ManifestPath $manifestPath | ConvertFrom-Json
    Assert-Condition ($verify.status -eq 'ok') 'NS802 verify-backup did not pass before restore'

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifestRoot = (Get-Item -LiteralPath $manifestPath).DirectoryName
    $databaseDumpPath = Join-Path $manifestRoot $manifest.database.dump
    Assert-Condition (Test-Path -LiteralPath $databaseDumpPath) 'NS802 database dump missing'

    $pgRestore = Join-Path $PgBin 'pg_restore.exe'
    Assert-Condition (Test-Path -LiteralPath $pgRestore) "pg_restore not found: $pgRestore"

    Remove-Item -LiteralPath $RestoreRoot -Recurse -Force -ErrorAction SilentlyContinue
    $restoreFullRoot = Join-Path $repoRoot $RestoreRoot
    $dbRoot = Join-Path $restoreFullRoot 'database'
    $fileStoreRoot = Join-Path $restoreFullRoot 'file_store'
    $configRoot = Join-Path $restoreFullRoot 'configs'
    $templateRoot = Join-Path $restoreFullRoot 'templates'
    $evidenceRoot = Join-Path $restoreFullRoot 'evidence'
    New-Item -ItemType Directory -Path $dbRoot, $fileStoreRoot, $configRoot, $templateRoot, $evidenceRoot -Force | Out-Null

    $restorePlanPath = Join-Path $dbRoot 'database.restore-plan.txt'
    & $pgRestore -l $databaseDumpPath | Set-Content -LiteralPath $restorePlanPath -Encoding UTF8
    Assert-Condition ($LASTEXITCODE -eq 0) 'NS802 pg_restore -l failed'

    $schemaOnlyPath = Join-Path $dbRoot 'database.schema-only.sql'
    & $pgRestore --schema-only --file $schemaOnlyPath $databaseDumpPath
    Assert-Condition ($LASTEXITCODE -eq 0) 'NS802 pg_restore --schema-only failed'
    Assert-Condition ((Get-Item -LiteralPath $schemaOnlyPath).Length -gt 0) 'NS802 schema-only output is empty'

    $fileStoreBackupRoot = Resolve-FileStoreBackupRoot -Manifest $manifest -ManifestPath $manifestPath
    $restoredFileStoreCount = 0
    foreach ($file in @($manifest.fileStore.files)) {
        $src = Join-Path $fileStoreBackupRoot $file.path
        Assert-Condition (Test-Path -LiteralPath $src) "missing file store source: $src"
        Assert-Condition ((Compute-Sha256 $src) -eq [string]$file.sha256) "source file store hash mismatch: $src"
        $dst = Join-Path $fileStoreRoot $file.path
        $dstDir = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $dstDir)) {
            New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $src -Destination $dst -Force
        Assert-Condition ((Compute-Sha256 $dst) -eq [string]$file.sha256) "restored file store hash mismatch: $dst"
        $restoredFileStoreCount++
    }

    $restoredConfigs = Copy-ManifestGroup -Items $manifest.configs -TargetRoot $configRoot
    $restoredTemplates = Copy-ManifestGroup -Items $manifest.templates -TargetRoot $templateRoot
    $restoredEvidence = Copy-ManifestGroup -Items $manifest.evidence -TargetRoot $evidenceRoot

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS802'
        checkedAt = (Get-Date).ToString('s')
        mode = 'isolated_restore_drill'
        productionEligible = $false
        externalAiCalls = 0
        realStudentDataUsed = $false
        writesProductionHistory = $false
        activeAssetMutation = $false
        dependency = [ordered]@{
            ns801 = 'docs/evidence/20260530-ns801-backup-manifest-report.json'
        }
        restore = [ordered]@{
            sourceManifest = To-RepoRelative $manifestPath
            isolatedRoot = To-RepoRelative $restoreFullRoot
            databaseRestorePlan = To-RepoRelative $restorePlanPath
            databaseSchemaOnlySql = To-RepoRelative $schemaOnlyPath
            fileStoreRestoredCount = $restoredFileStoreCount
            configRestoredCount = @($restoredConfigs).Count
            templateRestoredCount = @($restoredTemplates).Count
            evidenceRestoredCount = @($restoredEvidence).Count
        }
        acceptance = [ordered]@{
            manifestVerifiedBeforeRestore = $true
            databaseRestorePlanGenerated = $true
            schemaOnlyExtracted = $true
            fileStoreRestoredToIsolatedRoot = $true
            configsRestoredToIsolatedRoot = $true
            templatesRestoredToIsolatedRoot = $true
            evidenceRestoredToIsolatedRoot = $true
            restoredHashesVerified = $true
            productionDatabaseUntouched = $true
            productionFileStoreUntouched = $true
        }
        verification = [ordered]@{
            build = 'gate_na: isolated restore drill script only; no code build required'
            test = 'tools/verify-backup.ps1 + pg_restore -l + pg_restore --schema-only + isolated file/config/template/evidence copy with sha256 checks'
            contractInvariant = 'restore uses NS801 manifest, validates source hashes, restores only to tmp/ns802-restore, and verifies restored hashes'
            hotspot = 'gate_na: no real disaster recovery operator session; isolated restore drill covers non-site restore mechanics'
        }
        boundary = 'NS802 proves the NS801 backup manifest can drive an isolated restore drill without overwriting the current database or production file store.'
        rollback = "delete $RestoreRoot if this isolated restore output is no longer needed; git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns802-restore-drill.ps1 $ReportPath"
        next = 'NS803 can continue installer/host diagnostic.'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}

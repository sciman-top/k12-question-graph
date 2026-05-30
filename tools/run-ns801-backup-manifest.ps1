param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [string] $BackupRoot = 'tmp\ns801-backups',
    [string] $ReportPath = 'docs/evidence/20260530-ns801-backup-manifest-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

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

function To-RepoRelative([string] $Path) {
    return [System.IO.Path]::GetRelativePath($repoRoot, (Resolve-Path -LiteralPath $Path)).Replace('\', '/')
}

Push-Location $repoRoot
try {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'DatabasePassword or PGPASSWORD is required for NS801 backup manifest drill.'

    $ns705 = Read-Json 'docs/evidence/20260530-ns705-student-data-privacy-report.json'
    Assert-Condition ($ns705.status -eq 'pass') 'NS801 dependency NS705 report did not pass'
    Assert-Condition (-not [bool]$ns705.realStudentDataUsed) 'NS801 requires privacy gate before backup drill'
    Assert-Condition ([int]$ns705.scan.blockingPiiHits -eq 0) 'NS801 requires zero blocking PII hits before backup drill'

    $backup = .\tools\backup.ps1 `
        -BackupRoot $BackupRoot `
        -FileStoreRoot $FileStoreRoot `
        -PgBin $PgBin `
        -DatabaseName $DatabaseName `
        -DatabaseHost $DatabaseHost `
        -DatabasePort $DatabasePort `
        -DatabaseUser $DatabaseUser | ConvertFrom-Json
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$backup.manifest)) 'NS801 backup did not return manifest path'

    $verify = .\tools\verify-backup.ps1 -ManifestPath $backup.manifest | ConvertFrom-Json
    Assert-Condition ($verify.status -eq 'ok') 'NS801 verify-backup did not pass'

    $manifest = Get-Content -LiteralPath $backup.manifest -Raw | ConvertFrom-Json
    Assert-Condition ([string]$manifest.database.engine -eq 'postgresql') 'NS801 manifest database engine mismatch'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$manifest.database.sha256)) 'NS801 database dump hash missing'
    Assert-Condition (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $backup.manifest) $manifest.database.dump)) 'NS801 database dump missing'
    Assert-Condition ($manifest.fileStore.PSObject.Properties.Name -contains 'files') 'NS801 fileStore manifest files missing'
    Assert-Condition ([int]$verify.configCount -ge 3) 'NS801 config manifest coverage too small'
    Assert-Condition ([int]$verify.templateCount -ge 2) 'NS801 template manifest coverage too small'
    Assert-Condition ([int]$verify.evidenceCount -ge 5) 'NS801 evidence manifest coverage too small'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS801'
        checkedAt = (Get-Date).ToString('s')
        mode = 'backup_manifest_drill'
        productionEligible = $false
        externalAiCalls = 0
        realStudentDataUsed = $false
        writesProductionHistory = $false
        activeAssetMutation = $false
        dependency = [ordered]@{
            ns705 = 'docs/evidence/20260530-ns705-student-data-privacy-report.json'
        }
        backup = [ordered]@{
            manifest = To-RepoRelative $backup.manifest
            backupDir = To-RepoRelative $backup.backupDir
            databaseDump = To-RepoRelative $backup.databaseDump
            databaseSha256 = [string]$manifest.database.sha256
            fileStoreSourceRoot = [string]$manifest.fileStore.sourceRoot
            fileCount = [int]$verify.fileCount
            configCount = [int]$verify.configCount
            templateCount = [int]$verify.templateCount
            evidenceCount = [int]$verify.evidenceCount
        }
        acceptance = [ordered]@{
            databaseDumpInManifest = $true
            fileStoreInManifest = $true
            configsInManifest = $true
            templatesInManifest = $true
            evidenceInManifest = $true
            sha256Verified = $true
            noPlaintextDatabasePasswordInManifest = (-not ((Get-Content -LiteralPath $backup.manifest -Raw) -match [regex]::Escape($DatabasePassword)))
            noMirrorDelete = $true
            noRealStudentData = $true
            noExternalAiCall = $true
        }
        verification = [ordered]@{
            build = 'gate_na: backup manifest script drill only; no code build required'
            test = 'tools/backup.ps1 + tools/verify-backup.ps1'
            contractInvariant = 'manifest contains database dump, file-store listing, configs, templates, evidence hashes, and verify-backup validates sha256'
            hotspot = 'gate_na: no isolated restore yet; NS802 owns restore drill from this or a fresh manifest'
        }
        boundary = 'NS801 proves a local draft/test backup manifest can be generated and hash-verified for database, file store, configs, templates, and evidence. Restore is intentionally deferred to NS802.'
        rollback = "delete $BackupRoot if this dry-run backup is no longer needed; git restore tools/backup.ps1 tools/verify-backup.ps1 tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns801-backup-manifest.ps1 $ReportPath"
        next = 'NS802 can continue isolated restore drill.'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}

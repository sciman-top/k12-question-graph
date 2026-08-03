param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [string] $JsonReportPath = 'tmp/verification/release-state-fingerprint.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

$migrationFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'apps/api/Data/Migrations') -File -ErrorAction SilentlyContinue | Sort-Object Name)
$migrationText = ($migrationFiles | ForEach-Object { "$($_.Name):$($_.Length)" }) -join "`n"
$migrationHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($migrationText))).ToLowerInvariant()

$fileStore = [ordered]@{ available = $false; fileCount = 0; totalBytes = 0; listingHash = $null }
if (Test-Path -LiteralPath $FileStoreRoot) {
    $files = @(Get-ChildItem -LiteralPath $FileStoreRoot -File -Recurse -ErrorAction Stop | Sort-Object FullName)
    $listing = ($files | ForEach-Object {
        '{0}|{1}|{2:o}' -f ([System.IO.Path]::GetRelativePath($FileStoreRoot, $_.FullName)), $_.Length, $_.LastWriteTimeUtc
    }) -join "`n"
    $fileStore.available = $true
    $fileStore.fileCount = $files.Count
    $fileStore.totalBytes = [long](($files | Measure-Object Length -Sum).Sum)
    $fileStore.listingHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($listing))).ToLowerInvariant()
}

$database = [ordered]@{ available = $false; schemaTableCount = $null; migrationCount = $null; error = $null }
$psql = Join-Path $PgBin 'psql.exe'
if ((Test-Path -LiteralPath $psql) -and -not [string]::IsNullOrWhiteSpace($DatabasePassword)) {
    $previousPassword = $env:PGPASSWORD
    $env:PGPASSWORD = $DatabasePassword
    try {
        $schemaTableCount = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c "select count(*) from information_schema.tables where table_schema='public';"
        if ($LASTEXITCODE -ne 0) { throw 'database table fingerprint query failed' }
        $migrationCount = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c 'select count(*) from "__EFMigrationsHistory";'
        if ($LASTEXITCODE -ne 0) { throw 'database migration fingerprint query failed' }
        $database.available = $true
        $database.schemaTableCount = [int]$schemaTableCount
        $database.migrationCount = [int]$migrationCount
    }
    catch {
        $database.error = $_.Exception.Message
    }
    finally {
        $env:PGPASSWORD = $previousPassword
    }
}

$report = [ordered]@{
    schemaVersion = 1
    checkedAt = (Get-Date).ToString('s')
    migrationFileCount = $migrationFiles.Count
    migrationListingHash = $migrationHash
    database = $database
    fileStore = $fileStore
}
$fullReportPath = Join-Path $repoRoot $JsonReportPath
New-Item -ItemType Directory -Path (Split-Path -Parent $fullReportPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $fullReportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 6

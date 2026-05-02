param(
    [string] $BackupRoot = 'D:\KQG_Backups',
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabaseUser = 'postgres'
)

$ErrorActionPreference = 'Stop'

function Get-RelativePath([string] $BasePath, [string] $Path) {
    return [System.IO.Path]::GetRelativePath((Resolve-Path -LiteralPath $BasePath), (Resolve-Path -LiteralPath $Path)).Replace('\', '/')
}

function Get-FileEntry([string] $BasePath, [string] $Path) {
    $item = Get-Item -LiteralPath $Path
    $hash = Get-FileHash -LiteralPath $Path -Algorithm SHA256
    [ordered]@{
        path = Get-RelativePath -BasePath $BasePath -Path $Path
        bytes = $item.Length
        sha256 = $hash.Hash.ToLowerInvariant()
    }
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $BackupRoot $timestamp
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

$pgDump = Join-Path $PgBin 'pg_dump.exe'
if (-not (Test-Path -LiteralPath $pgDump)) {
    throw "pg_dump not found: $pgDump"
}

$databaseDump = Join-Path $backupDir 'database.dump'
& $pgDump -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -Fc -f $databaseDump $DatabaseName
if ($LASTEXITCODE -ne 0) {
    throw "pg_dump failed with exit code $LASTEXITCODE"
}

$fileEntries = @()
if (Test-Path -LiteralPath $FileStoreRoot) {
    $fileEntries = Get-ChildItem -LiteralPath $FileStoreRoot -File -Recurse |
        ForEach-Object { Get-FileEntry -BasePath $FileStoreRoot -Path $_.FullName }
}

$configFiles = @(
    'apps/api/appsettings.json',
    'apps/api/appsettings.Development.json',
    'tasks/backlog.csv'
) | Where-Object { Test-Path -LiteralPath $_ } |
    ForEach-Object { Get-FileEntry -BasePath (Get-Location).Path -Path $_ }

$databaseHash = Get-FileHash -LiteralPath $databaseDump -Algorithm SHA256
$manifest = [ordered]@{
    version = 1
    createdAt = (Get-Date).ToUniversalTime().ToString('o')
    database = [ordered]@{
        engine = 'postgresql'
        databaseName = $DatabaseName
        dump = 'database.dump'
        sha256 = $databaseHash.Hash.ToLowerInvariant()
    }
    fileStore = [ordered]@{
        root = $FileStoreRoot
        files = $fileEntries
    }
    configs = $configFiles
}

$manifestPath = Join-Path $backupDir 'manifest.json'
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

[pscustomobject]@{
    backupDir = $backupDir
    manifest = $manifestPath
    databaseDump = $databaseDump
    fileCount = @($fileEntries).Count
    configCount = @($configFiles).Count
} | ConvertTo-Json -Compress

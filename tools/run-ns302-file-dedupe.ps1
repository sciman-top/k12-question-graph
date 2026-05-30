param(
    [string] $ReportPath = 'docs/evidence/20260530-ns302-file-dedupe-report.json',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store'
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

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse('127.0.0.1'), 0)
    try {
        $listener.Start()
        return $listener.LocalEndpoint.Port
    }
    finally {
        $listener.Stop()
    }
}

function Wait-ApiReady([System.Diagnostics.Process] $Process, [string] $ApiUrl, [string] $LogErr) {
    for ($i = 0; $i -lt 30; $i++) {
        if ($Process.HasExited) {
            throw "API exited before NS302 file dedupe smoke on $ApiUrl; see $LogErr"
        }

        try {
            $health = Invoke-RestMethod -Uri "$ApiUrl/health" -TimeoutSec 2
            if ($health.status -eq 'ok') {
                return
            }
        }
        catch {
            Start-Sleep -Seconds 1
        }
    }

    throw "API did not become ready for NS302 file dedupe smoke on $ApiUrl"
}

function Invoke-PsqlScalar([string] $Sql) {
    $psql = Join-Path $PgBin 'psql.exe'
    Assert-Condition (Test-Path -LiteralPath $psql) "psql.exe missing: $psql"
    $value = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -c $Sql
    if ($LASTEXITCODE -ne 0) {
        throw "psql query failed: $Sql"
    }

    return [string]$value
}

function Remove-FileStoreAsset([string] $RelativePath) {
    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        return $false
    }

    $root = (Resolve-Path -LiteralPath $FileStoreRoot).Path
    $fullPath = [System.IO.Path]::GetFullPath((Join-Path $root $RelativePath))
    Assert-Condition ($fullPath.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) "refusing to remove file outside FileStoreRoot: $fullPath"

    if (Test-Path -LiteralPath $fullPath) {
        Remove-Item -LiteralPath $fullPath -Force
        return $true
    }

    return $false
}

Push-Location $repoRoot
try {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'DatabasePassword or PGPASSWORD is required for NS302 file dedupe smoke'
    Assert-Condition (Test-Path -LiteralPath $FileStoreRoot) "FileStoreRoot missing: $FileStoreRoot"

    $buildOutput = dotnet build 'apps/api/K12QuestionGraph.Api.csproj' -c Release 2>&1
    Assert-Condition ($LASTEXITCODE -eq 0) 'dotnet build failed before NS302 file dedupe smoke'

    $runId = [Guid]::NewGuid().ToString('N')
    $sample = Join-Path $env:TEMP "kqg-ns302-dedupe-$runId.bin"
    $bytes = [byte[]]::new(1048576)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    [System.IO.File]::WriteAllBytes($sample, $bytes)

    $port = Get-FreeTcpPort
    $apiUrl = "http://127.0.0.1:$port"
    $logOut = Join-Path $repoRoot 'docs/evidence/ns302-api.out.log'
    $logErr = Join-Path $repoRoot 'docs/evidence/ns302-api.err.log'

    $previousConnectionString = $env:KQG_CONNECTION_STRING
    $previousFileStoreRoot = $env:KqgPaths__FileStoreRoot
    $env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
    $env:KqgPaths__FileStoreRoot = $FileStoreRoot

    $process = Start-Process -FilePath dotnet -ArgumentList @(
        'run',
        '--project',
        'apps\api\K12QuestionGraph.Api.csproj',
        '-c',
        'Release',
        '--no-build',
        '--urls',
        $apiUrl,
        '--no-launch-profile'
    ) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr

    try {
        Wait-ApiReady -Process $process -ApiUrl $apiUrl -LogErr $logErr

        $first = curl.exe -s `
            -F "file=@$sample;filename=ns302-large-fixture.bin;type=application/octet-stream" `
            -F 'sourceType=synthetic' `
            -F 'sourceTitle=NS302 Large Fixture' `
            -F "materialBatchKey=ns302_$runId" `
            -F 'ownerScope=teacher_private' `
            -F 'licenseOrPermission=synthetic_local_regression' `
            -F 'sharingAllowed=false' `
            -F 'containsStudentPii=false' `
            -F 'anonymizationStatus=synthetic' `
            "$apiUrl/files" | ConvertFrom-Json

        $second = curl.exe -s `
            -F "file=@$sample;filename=renamed-ns302-large-fixture.bin;type=application/octet-stream" `
            -F 'sourceType=synthetic' `
            -F 'sourceTitle=NS302 Large Fixture' `
            -F "materialBatchKey=ns302_$runId" `
            -F 'ownerScope=teacher_private' `
            -F 'licenseOrPermission=synthetic_local_regression' `
            -F 'sharingAllowed=false' `
            -F 'containsStudentPii=false' `
            -F 'anonymizationStatus=synthetic' `
            "$apiUrl/files" | ConvertFrom-Json

        Assert-Condition ($first.isDuplicate -eq $false) 'first NS302 upload was unexpectedly duplicate'
        Assert-Condition ($second.isDuplicate -eq $true) 'second NS302 upload was not marked duplicate'
        Assert-Condition ($first.id -eq $second.id) 'duplicate upload returned a different FileAsset id'
        Assert-Condition ($first.relativePath -eq $second.relativePath) 'duplicate upload returned a different relative path'
        Assert-Condition ([int64]$first.sizeBytes -eq 1048576) 'FileAsset sizeBytes did not preserve fixture size'
        Assert-Condition ($first.sourceDocument.id -eq $second.sourceDocument.id) 'same file and same source metadata created a duplicate SourceDocument'

        $fileAssetId = [string]$first.id
        $sourceDocumentId = [string]$first.sourceDocument.id
        $sha256 = [string]$first.sha256
        $relativePath = [string]$first.relativePath
        $safeRelativePath = $relativePath.Replace("'", "''")

        $fileAssetCount = [int](Invoke-PsqlScalar "select count(*) from file_assets where sha256 = '$sha256' and size_bytes = 1048576;")
        $sourceDocumentCount = [int](Invoke-PsqlScalar "select count(*) from source_documents where file_asset_id = '$fileAssetId' and material_batch_key = 'ns302_$runId';")
        $dbPayloadBytes = [int](Invoke-PsqlScalar "select octet_length(coalesce(source_metadata::text,'')) + octet_length(coalesce(original_file_name,'')) + octet_length(coalesce(relative_path,'')) from file_assets where id = '$fileAssetId';")
        $pathMatchCount = [int](Invoke-PsqlScalar "select count(*) from file_assets where id = '$fileAssetId' and relative_path = '$safeRelativePath' and sha256 = '$sha256';")

        Assert-Condition ($fileAssetCount -eq 1) 'duplicate file created more than one FileAsset row'
        Assert-Condition ($sourceDocumentCount -eq 1) 'same duplicate metadata created more than one SourceDocument row'
        Assert-Condition ($pathMatchCount -eq 1) 'DB did not preserve expected hash/path metadata'
        Assert-Condition ($dbPayloadBytes -lt 8192) 'FileAsset DB text metadata is too large; possible content-in-DB regression'

        $filePath = [System.IO.Path]::GetFullPath((Join-Path (Resolve-Path -LiteralPath $FileStoreRoot).Path $relativePath))
        Assert-Condition (Test-Path -LiteralPath $filePath) "deduped file was not present in FileStoreRoot: $filePath"
        $physicalSize = (Get-Item -LiteralPath $filePath).Length
        Assert-Condition ($physicalSize -eq 1048576) 'physical FileStore asset size mismatch'

        Invoke-PsqlScalar "delete from source_documents where id = '$sourceDocumentId';" | Out-Null
        Invoke-PsqlScalar "delete from file_assets where id = '$fileAssetId';" | Out-Null
        $uploadedFileRemoved = Remove-FileStoreAsset $relativePath
        $cleanupCount = [int](Invoke-PsqlScalar "select count(*) from file_assets where id = '$fileAssetId' or sha256 = '$sha256';")
        Assert-Condition ($cleanupCount -eq 0) 'NS302 cleanup left FileAsset rows behind'

        $report = [ordered]@{
            status = 'pass'
            taskId = 'NS302'
            checkedAt = (Get-Date).ToString('s')
            mode = 'api_duplicate_upload_plus_large_file_metadata_guard'
            productionEligible = $false
            upload = [ordered]@{
                fileAssetId = $fileAssetId
                sourceDocumentId = $sourceDocumentId
                sha256 = $sha256
                relativePath = $relativePath
                firstDuplicateFlag = [bool]$first.isDuplicate
                secondDuplicateFlag = [bool]$second.isDuplicate
                sameFileAssetId = $true
                sameRelativePath = $true
                sizeBytes = [int64]$first.sizeBytes
            }
            db = [ordered]@{
                fileAssetRowsForHash = $fileAssetCount
                sourceDocumentRowsForSameMetadata = $sourceDocumentCount
                pathHashMetadataMatched = $true
                dbTextPayloadBytes = $dbPayloadBytes
                contentStoredOutsideDb = $true
            }
            fileStore = [ordered]@{
                physicalFileExisted = $true
                physicalSizeBytes = $physicalSize
                uploadedFileRemoved = $uploadedFileRemoved
            }
            cleanup = [ordered]@{
                dbRowsRemoved = $true
                cleanupCount = $cleanupCount
            }
            acceptance = [ordered]@{
                duplicateUploadDoesNotCopyLargeFile = $true
                databaseStoresMetadataPathHashSizeOnly = $true
                sourceDocumentNotDuplicatedForSameMetadata = $true
                physicalFileProtectedByRelativePath = $true
            }
            boundary = 'NS302 proves duplicate upload reuses FileAsset and keeps large binary content in FileStore, while DB stores metadata/hash/path/size. It does not set a production data retention policy.'
            next = 'NS303 can continue worker profile diagnostic.'
            rollback = 'Test rows and uploaded file are removed by this script; if interrupted, delete the reported file_assets/source_documents ids or restore DB/FileStore snapshot.'
        }

        $reportFullPath = Join-Path $repoRoot $ReportPath
        New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
        $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
        $report | ConvertTo-Json -Depth 7
    }
    finally {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $env:KQG_CONNECTION_STRING = $previousConnectionString
        $env:KqgPaths__FileStoreRoot = $previousFileStoreRoot
        if (Test-Path -LiteralPath $sample) {
            Remove-Item -LiteralPath $sample -Force
        }
    }
}
finally {
    Pop-Location
}

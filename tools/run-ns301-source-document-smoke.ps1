param(
    [string] $ReportPath = 'docs/evidence/20260530-ns301-source-document-smoke-report.json',
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
            throw "API exited before NS301 source document smoke on $ApiUrl; see $LogErr"
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

    throw "API did not become ready for NS301 source document smoke on $ApiUrl"
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
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'DatabasePassword or PGPASSWORD is required for NS301 source document smoke'
    Assert-Condition (Test-Path -LiteralPath $FileStoreRoot) "FileStoreRoot missing: $FileStoreRoot"

    $buildOutput = dotnet build 'apps/api/K12QuestionGraph.Api.csproj' -c Release 2>&1
    Assert-Condition ($LASTEXITCODE -eq 0) 'dotnet build failed before NS301 source document smoke'

    $runId = [Guid]::NewGuid().ToString('N')
    $port = Get-FreeTcpPort
    $apiUrl = "http://127.0.0.1:$port"
    $logOut = Join-Path $repoRoot 'docs/evidence/ns301-api.out.log'
    $logErr = Join-Path $repoRoot 'docs/evidence/ns301-api.err.log'
    $sample = Join-Path $env:TEMP "kqg-ns301-source-$runId.txt"
    $sampleContent = "NS301 authorized anonymized source document fixture $runId"
    Set-Content -LiteralPath $sample -Value $sampleContent -Encoding UTF8

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

    $uploadedFileRemoved = $false
    try {
        Wait-ApiReady -Process $process -ApiUrl $apiUrl -LogErr $logErr

        $upload = curl.exe -s `
            -F "file=@$sample;filename=ns301-authorized-anonymized-source.txt;type=text/plain" `
            -F 'sourceType=school_paper' `
            -F 'sourceTitle=NS301 Authorized Anonymized Fixture' `
            -F 'region=guangzhou' `
            -F 'year=2026' `
            -F 'gradeOrScope=junior_middle_school' `
            -F 'editionOrVersion=synthetic-v1' `
            -F "materialBatchKey=ns301_$runId" `
            -F 'ownerScope=school' `
            -F 'licenseOrPermission=internal_authorized' `
            -F 'sharingAllowed=true' `
            -F 'containsStudentPii=false' `
            -F 'anonymizationStatus=anonymized' `
            -F 'mayUseForKnowledgeExtraction=true' `
            -F 'mayUseForExamPointExtraction=true' `
            -F 'mayUseForTrendAnalysis=false' `
            "$apiUrl/files" | ConvertFrom-Json

        Assert-Condition ($null -ne $upload.id) 'upload did not return FileAsset id'
        Assert-Condition ($null -ne $upload.sourceDocument.id) 'upload did not return SourceDocument id'
        Assert-Condition ($upload.sourceDocument.fileAssetId -eq $upload.id) 'SourceDocument did not reference uploaded FileAsset'
        Assert-Condition ($upload.sha256.Length -eq 64) 'FileAsset sha256 was not returned'
        Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$upload.relativePath)) 'FileAsset relativePath was not returned'
        Assert-Condition ($upload.sourceDocument.sourceType -eq 'school_paper') 'SourceDocument sourceType mismatch'
        Assert-Condition ($upload.sourceDocument.licenseOrPermission -eq 'internal_authorized') 'SourceDocument license mismatch'
        Assert-Condition ($upload.sourceDocument.containsStudentPii -eq $false) 'SourceDocument PII boundary mismatch'
        Assert-Condition ($upload.sourceDocument.anonymizationStatus -eq 'anonymized') 'SourceDocument anonymization status mismatch'
        Assert-Condition ($upload.sourceDocument.externalAiAllowed -eq $true) 'authorized anonymized fixture should be external-AI eligible by metadata'

        $list = Invoke-RestMethod -Uri "$apiUrl/source-documents?materialBatchKey=ns301_$runId" -TimeoutSec 30
        Assert-Condition ([int]$list.items.Count -eq 1) 'source document list did not return the uploaded material batch'

        $sourceDocumentId = [string]$upload.sourceDocument.id
        $fileAssetId = [string]$upload.id
        $dbCountSql = @"
select count(*)
from source_documents sd
join file_assets fa on fa.id = sd.file_asset_id
where sd.id = '$sourceDocumentId'
  and sd.file_asset_id = '$fileAssetId'
  and fa.sha256 = '$($upload.sha256)'
  and fa.relative_path = '$($upload.relativePath)'
  and sd.source_type = 'school_paper'
  and sd.license_or_permission = 'internal_authorized'
  and sd.contains_student_pii = false
  and sd.anonymization_status = 'anonymized'
  and sd.material_batch_key = 'ns301_$runId';
"@
        $dbMatchCount = [int](Invoke-PsqlScalar $dbCountSql)
        Assert-Condition ($dbMatchCount -eq 1) 'DB join did not prove SourceDocument/FileAsset metadata persistence'

        $filePath = [System.IO.Path]::GetFullPath((Join-Path (Resolve-Path -LiteralPath $FileStoreRoot).Path ([string]$upload.relativePath)))
        Assert-Condition (Test-Path -LiteralPath $filePath) "uploaded file was not present in FileStoreRoot: $filePath"

        Invoke-PsqlScalar "delete from source_documents where id = '$sourceDocumentId';" | Out-Null
        Invoke-PsqlScalar "delete from file_assets where id = '$fileAssetId';" | Out-Null
        $uploadedFileRemoved = Remove-FileStoreAsset ([string]$upload.relativePath)
        $cleanupCount = [int](Invoke-PsqlScalar "select count(*) from source_documents where id = '$sourceDocumentId' or file_asset_id = '$fileAssetId';")
        Assert-Condition ($cleanupCount -eq 0) 'NS301 cleanup left SourceDocument rows behind'

        $report = [ordered]@{
            status = 'pass'
            taskId = 'NS301'
            checkedAt = (Get-Date).ToString('s')
            mode = 'api_upload_smoke_plus_db_join'
            productionEligible = $false
            api = [ordered]@{
                url = $apiUrl
                uploadRoute = 'POST /files'
                listRoute = 'GET /source-documents?materialBatchKey=...'
                fileAssetId = $fileAssetId
                sourceDocumentId = $sourceDocumentId
                sha256 = [string]$upload.sha256
                relativePath = [string]$upload.relativePath
            }
            sourceDocument = [ordered]@{
                sourceType = [string]$upload.sourceDocument.sourceType
                sourceTitle = [string]$upload.sourceDocument.sourceTitle
                region = [string]$upload.sourceDocument.region
                year = [int]$upload.sourceDocument.year
                materialBatchKey = [string]$upload.sourceDocument.materialBatchKey
                ownerScope = [string]$upload.sourceDocument.ownerScope
                licenseOrPermission = [string]$upload.sourceDocument.licenseOrPermission
                piiBoundary = [ordered]@{
                    containsStudentPii = [bool]$upload.sourceDocument.containsStudentPii
                    anonymizationStatus = [string]$upload.sourceDocument.anonymizationStatus
                    sharingAllowed = [bool]$upload.sourceDocument.sharingAllowed
                    externalAiAllowed = [bool]$upload.sourceDocument.externalAiAllowed
                }
                usagePermissions = [ordered]@{
                    mayUseForKnowledgeExtraction = [bool]$upload.sourceDocument.mayUseForKnowledgeExtraction
                    mayUseForExamPointExtraction = [bool]$upload.sourceDocument.mayUseForExamPointExtraction
                    mayUseForTrendAnalysis = [bool]$upload.sourceDocument.mayUseForTrendAnalysis
                }
            }
            db = [ordered]@{
                joinMatched = $dbMatchCount
                fileAssetReferencePersisted = $true
                hashPathMetadataPersisted = $true
            }
            cleanup = [ordered]@{
                dbRowsRemoved = $true
                uploadedFileRemoved = $uploadedFileRemoved
                cleanupCount = $cleanupCount
            }
            acceptance = [ordered]@{
                authorizedOrAnonymizedUploadAccepted = $true
                hashPersisted = $true
                pathPersisted = $true
                sourceTypePersisted = $true
                licensePersisted = $true
                piiBoundaryPersisted = $true
                fileAssetReferencePersisted = $true
            }
            boundary = 'NS301 proves an authorized/anonymized fixture can enter the SourceDocument evidence layer and be joined back to FileAsset hash/path metadata. It does not import real copyrighted material or switch active assets.'
            next = 'NS302 can continue with duplicate upload and large-file database path protection.'
            rollback = 'Test rows and uploaded file are removed by this script; if interrupted, delete the reported source_documents/file_assets ids or restore DB/FileStore snapshot.'
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

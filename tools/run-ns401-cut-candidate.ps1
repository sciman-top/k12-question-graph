param(
    [string] $ReportPath = 'docs/evidence/20260530-ns401-cut-candidate-report.json',
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
            throw "API exited before NS401 cut candidate smoke on $ApiUrl; see $LogErr"
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

    throw "API did not become ready for NS401 cut candidate smoke on $ApiUrl"
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
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'DatabasePassword or PGPASSWORD is required for NS401 cut candidate smoke'
    Assert-Condition (Test-Path -LiteralPath $FileStoreRoot) "FileStoreRoot missing: $FileStoreRoot"

    $buildOutput = dotnet build 'apps/api/K12QuestionGraph.Api.csproj' -c Release 2>&1
    Assert-Condition ($LASTEXITCODE -eq 0) 'dotnet build failed before NS401 cut candidate smoke'

    $runId = [Guid]::NewGuid().ToString('N')
    $sample = Join-Path $env:TEMP "kqg-ns401-cut-$runId.txt"
    Set-Content -LiteralPath $sample -Value "NS401 cut candidate fixture $runId" -Encoding UTF8

    $port = Get-FreeTcpPort
    $apiUrl = "http://127.0.0.1:$port"
    $logOut = Join-Path $repoRoot 'docs/evidence/ns401-api.out.log'
    $logErr = Join-Path $repoRoot 'docs/evidence/ns401-api.err.log'

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

        $upload = curl.exe -s `
            -F "file=@$sample;filename=ns401-cut-source.txt;type=text/plain" `
            -F 'sourceType=synthetic' `
            -F 'sourceTitle=NS401 Cut Candidate Fixture' `
            -F "materialBatchKey=ns401_$runId" `
            -F 'ownerScope=teacher_private' `
            -F 'licenseOrPermission=synthetic_local_regression' `
            -F 'sharingAllowed=false' `
            -F 'containsStudentPii=false' `
            -F 'anonymizationStatus=synthetic' `
            "$apiUrl/files" | ConvertFrom-Json
        $sourceDocumentId = [string]$upload.sourceDocument.id
        $fileAssetId = [string]$upload.id

        $previewRegionBody = [ordered]@{
            pageNumber = 1
            x = 8
            y = 12
            width = 70
            height = 18
            coordinateUnit = 'percent'
            screenshotRelativePath = $null
            regionType = 'preview'
        } | ConvertTo-Json
        $questionRegionBody = [ordered]@{
            pageNumber = 2
            x = 10
            y = 20
            width = 68
            height = 22
            coordinateUnit = 'percent'
            screenshotRelativePath = $null
            regionType = 'question_stem'
        } | ConvertTo-Json
        $previewRegion = Invoke-RestMethod -Method Post -Uri "$apiUrl/source-documents/$sourceDocumentId/regions" -ContentType 'application/json' -Body $previewRegionBody -TimeoutSec 15
        $questionRegion = Invoke-RestMethod -Method Post -Uri "$apiUrl/source-documents/$sourceDocumentId/regions" -ContentType 'application/json' -Body $questionRegionBody -TimeoutSec 15

        $generation = Invoke-RestMethod -Method Post -Uri "$apiUrl/source-documents/$sourceDocumentId/cut-candidates/generate" -TimeoutSec 20
        $list = Invoke-RestMethod -Method Get -Uri "$apiUrl/source-documents/$sourceDocumentId/cut-candidates" -TimeoutSec 15
        $items = @($list.items)

        Assert-Condition ([int]$generation.generatedCount -eq 2) 'NS401 expected two generated cut candidates'
        Assert-Condition ([int]$generation.lowConfidenceReviewQueueCount -ge 1) 'NS401 expected at least one low-confidence review queue item'
        Assert-Condition ([decimal]$generation.lowConfidenceThreshold -eq 0.85) 'NS401 low confidence threshold mismatch'
        Assert-Condition ($items.Count -eq 2) 'NS401 list did not return two cut candidates'

        $previewCandidate = @($items | Where-Object { [string]$_.sourceRegionId -eq [string]$previewRegion.id })[0]
        $questionCandidate = @($items | Where-Object { [string]$_.sourceRegionId -eq [string]$questionRegion.id })[0]
        Assert-Condition ($null -ne $previewCandidate) 'NS401 preview sourceRegion candidate missing'
        Assert-Condition ($null -ne $questionCandidate) 'NS401 question sourceRegion candidate missing'
        Assert-Condition ([decimal]$previewCandidate.confidence -lt [decimal]$generation.lowConfidenceThreshold) 'NS401 preview candidate should be low confidence'
        Assert-Condition ([string]$previewCandidate.failureReason -eq 'low_confidence_requires_manual_takeover') 'NS401 low-confidence failureReason mismatch'
        Assert-Condition ([string]$previewCandidate.takeoverAction -eq 'manual_review') 'NS401 low-confidence takeoverAction mismatch'
        Assert-Condition ([decimal]$questionCandidate.confidence -gt [decimal]$generation.lowConfidenceThreshold) 'NS401 question candidate should be above threshold'
        Assert-Condition ([string]$questionCandidate.status -eq 'pending_review') 'NS401 candidate status must remain pending_review'

        $candidateCount = [int](Invoke-PsqlScalar "select count(*) from cut_candidates where source_document_id = '$sourceDocumentId';")
        $reviewCount = [int](Invoke-PsqlScalar "select count(*) from review_queue_items where status = 'open' and review_type = 'cut_candidate' and payload::text like '%$sourceDocumentId%';")
        Assert-Condition ($candidateCount -eq 2) 'NS401 DB candidate count mismatch'
        Assert-Condition ($reviewCount -ge 1) 'NS401 DB low-confidence review queue missing'

        Invoke-PsqlScalar "delete from review_queue_items where payload::text like '%$sourceDocumentId%';" | Out-Null
        Invoke-PsqlScalar "delete from cut_candidates where source_document_id = '$sourceDocumentId';" | Out-Null
        Invoke-PsqlScalar "delete from source_regions where source_document_id = '$sourceDocumentId';" | Out-Null
        Invoke-PsqlScalar "delete from source_documents where id = '$sourceDocumentId';" | Out-Null
        Invoke-PsqlScalar "delete from file_assets where id = '$fileAssetId';" | Out-Null
        $uploadedFileRemoved = Remove-FileStoreAsset ([string]$upload.relativePath)
        $cleanupCount = [int](Invoke-PsqlScalar "select count(*) from source_documents where id = '$sourceDocumentId';")
        Assert-Condition ($cleanupCount -eq 0) 'NS401 cleanup left SourceDocument behind'

        $report = [ordered]@{
            status = 'pass'
            taskId = 'NS401'
            checkedAt = (Get-Date).ToString('s')
            mode = 'api_cut_candidate_generation_plus_db_probe'
            productionEligible = $false
            sourceDocumentId = $sourceDocumentId
            generation = [ordered]@{
                generatedCount = [int]$generation.generatedCount
                lowConfidenceReviewQueueCount = [int]$generation.lowConfidenceReviewQueueCount
                lowConfidenceThreshold = [decimal]$generation.lowConfidenceThreshold
            }
            candidates = @(
                [ordered]@{
                    sourceRegionId = [string]$previewCandidate.sourceRegionId
                    confidence = [decimal]$previewCandidate.confidence
                    failureReason = [string]$previewCandidate.failureReason
                    takeoverAction = [string]$previewCandidate.takeoverAction
                    status = [string]$previewCandidate.status
                },
                [ordered]@{
                    sourceRegionId = [string]$questionCandidate.sourceRegionId
                    confidence = [decimal]$questionCandidate.confidence
                    failureReason = [string]$questionCandidate.failureReason
                    takeoverAction = [string]$questionCandidate.takeoverAction
                    status = [string]$questionCandidate.status
                }
            )
            db = [ordered]@{
                candidateCount = $candidateCount
                lowConfidenceReviewQueueCount = $reviewCount
            }
            cleanup = [ordered]@{
                dbRowsRemoved = $true
                uploadedFileRemoved = $uploadedFileRemoved
            }
            acceptance = [ordered]@{
                cutCandidatesGenerated = $true
                confidenceReported = $true
                sourceRegionLinked = $true
                failureReasonReported = $true
                takeoverRequiredViaManualReviewAction = $true
            }
            boundary = 'NS401 proves synthetic SourceRegions generate pending_review cut candidates with confidence, sourceRegion links, failureReason, and manual-review takeover routing. It does not claim automated cutting accuracy.'
            next = 'NS402 can continue ReviewQueue API filtering and audit evidence.'
            rollback = 'Test rows and uploaded file are removed by this script; if interrupted, delete rows by the reported sourceDocumentId or restore DB/FileStore snapshot.'
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

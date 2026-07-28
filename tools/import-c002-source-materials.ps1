param(
    [string] $SourceRoot = 'D:\KQG_Data\source_materials\imported\guangzhou_physics_2016_2025',
    [string] $ApiUrl = '',
    [switch] $StartApi,
    [switch] $Apply,
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [string] $MaterialBatchKey = 'guangzhou_physics_2016_2025',
    [string] $ManifestPath = '',
    [switch] $VerifyIdempotency,
    [string] $ReportPath = 'docs\evidence\c002-source-material-import-report.json',
    [string] $BackupManifest = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
$resolvedSourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$reportFullPath = Join-Path $repoRoot $ReportPath
$requestedMaterialBatchKey = $MaterialBatchKey
$MaterialBatchKey = $MaterialBatchKey.Trim().ToLowerInvariant().Replace('-', '_').Replace(' ', '_')
$resolvedManifestPath = ''
$manifestGuard = $null
$apiProcess = $null
$previousConnectionString = $env:KQG_CONNECTION_STRING
$previousFileStoreRoot = $env:KqgPaths__FileStoreRoot

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

function Wait-ApiReady([System.Diagnostics.Process] $Process, [string] $ReadyUrl, [string] $LogErr) {
    for ($i = 0; $i -lt 30; $i++) {
        if ($Process.HasExited) {
            throw "API exited before ready on $ReadyUrl; see $LogErr"
        }

        try {
            $health = Invoke-RestMethod -Uri "$ReadyUrl/health/ready" -TimeoutSec 2
            if ($health.status -eq 'ok') {
                return
            }
        }
        catch {
            Start-Sleep -Seconds 1
        }
    }

    throw "API did not become ready on $ReadyUrl"
}

function Get-YearFromName([string] $Name) {
    $match = [regex]::Match($Name, '(20\d{2})')
    if ($match.Success) {
        return [int]$match.Groups[1].Value
    }

    return $null
}

function Get-SourceMetadata([System.IO.FileInfo] $File, [string] $SourceType) {
    $relativePath = [System.IO.Path]::GetRelativePath($resolvedSourceRoot, $File.FullName)
    $relativeNormalized = $relativePath -replace '\\', '/'
    $name = $File.Name
    $parent = $File.DirectoryName
    $year = Get-YearFromName $name

    $gradeOrScope = 'junior_middle_school'
    $editionOrVersion = ''
    $mayKnowledge = $false
    $mayExamPoint = $false
    $mayTrend = $false

    if ($SourceType -eq 'textbook') {
        $mayKnowledge = $true
        if ($name -like '*八上*') {
            $gradeOrScope = 'grade_8_volume_1'
            $editionOrVersion = '2024_person_education_press_grade_8_volume_1'
        }
        elseif ($name -like '*八下*') {
            $gradeOrScope = 'grade_8_volume_2'
            $editionOrVersion = '2024_person_education_press_grade_8_volume_2'
        }
        elseif ($name -like '*九全*') {
            $gradeOrScope = 'grade_9_full'
            $editionOrVersion = '2025_fall_person_education_press_grade_9_full'
        }
        else {
            $editionOrVersion = 'person_education_press'
        }
    }
    elseif ($SourceType -eq 'exam_analysis_report') {
        $gradeOrScope = 'grade_9'
        $editionOrVersion = if ($year) { [string]$year } else { '' }
        $mayExamPoint = $true
        $mayTrend = $true
    }
    elseif ($SourceType -eq 'local_exam_paper') {
        $gradeOrScope = 'grade_9'
        $editionOrVersion = if ($year) { [string]$year } else { '' }
        $mayKnowledge = $true
        $mayExamPoint = $true
        $mayTrend = $true
    }
    elseif ($SourceType -eq 'answer_or_solution') {
        $gradeOrScope = 'grade_9'
        $editionOrVersion = if ($year) { [string]$year } else { '' }
    }
    elseif ($SourceType -eq 'curriculum_standard') {
        $year = if ($year) { $year } else { 2025 }
        $gradeOrScope = 'junior_middle_school'
        $editionOrVersion = '2022_2025_revision'
        $mayKnowledge = $true
    }

    [ordered]@{
        path = $File.FullName
        relativePath = $relativeNormalized
        sourceType = $SourceType
        sourceTitle = [System.IO.Path]::GetFileNameWithoutExtension($name)
        region = if ($SourceType -eq 'curriculum_standard') { 'China' } else { 'Guangzhou' }
        year = $year
        gradeOrScope = $gradeOrScope
        editionOrVersion = $editionOrVersion
        materialBatchKey = $MaterialBatchKey
        ownerScope = 'school'
        licenseOrPermission = 'pending_source_workbench_review'
        sharingAllowed = $false
        containsStudentPii = $false
        anonymizationStatus = 'not_applicable'
        mayUseForKnowledgeExtraction = $mayKnowledge
        mayUseForExamPointExtraction = $mayExamPoint
        mayUseForTrendAnalysis = $mayTrend
    }
}

function Get-AdmissionDatabaseSnapshot {
    $psql = Join-Path $PgBin 'psql.exe'
    if (-not (Test-Path -LiteralPath $psql)) {
        throw "psql not found: $psql"
    }
    $sql = @"
select json_build_object(
  'sourceDocumentCount', (select count(*) from source_documents),
  'fileAssetCount', (select count(*) from file_assets),
  'knowledgeNodeCount', (select count(*) from knowledge_nodes),
  'domainAssetVersionCount', (select count(*) from domain_asset_versions),
  'knowledgeMappingCount', (select count(*) from knowledge_mappings),
  'activeDomainAssetCount', (select count(*) from domain_asset_versions where status = 'active'),
  'activeDomainAssetFingerprint', (
    select md5(coalesce(string_agg(id::text, ',' order by id), ''))
    from domain_asset_versions
    where status = 'active'
  )
)::text;
"@
    $output = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -v ON_ERROR_STOP=1 -At -c $sql
    if ($LASTEXITCODE -ne 0) {
        throw "source admission database snapshot failed with exit code $LASTEXITCODE"
    }
    return $output | ConvertFrom-Json
}

function Get-SourceTypes([System.IO.FileInfo] $File) {
    $relativePath = [System.IO.Path]::GetRelativePath($resolvedSourceRoot, $File.FullName) -replace '\\', '/'
    $name = $File.Name
    $parent = $File.DirectoryName

    if ($relativePath -like '*/初中物理教材（人教版）/*' -or $parent -like '*初中物理教材*') {
        return @('textbook')
    }
    if ($name -like '*课程标准*') {
        return @('curriculum_standard')
    }
    if ($name -like '*年报*' -or $relativePath -like '*/广州中考年报/*' -or $parent -like '*广州中考年报*') {
        return @('exam_analysis_report')
    }
    if ($name -like '*含答案*') {
        return @('local_exam_paper', 'answer_or_solution')
    }
    if ($name -match '(?<!含)答案' -or $name -like '*解析版*') {
        return @('answer_or_solution')
    }
    if ($name -like '*广州中考*' -or $relativePath -like '*/广州中考真题/*' -or $parent -like '*广州中考真题*') {
        return @('local_exam_paper')
    }

    return @('unknown')
}

function Get-ManifestSourcePlan([string] $Path) {
    $manifest = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $plan = @($manifest.materials | ForEach-Object {
        $material = $_
        $file = Get-Item -LiteralPath $material.localPath
        $relativePath = [System.IO.Path]::GetRelativePath($resolvedSourceRoot, $file.FullName)
        if ([System.IO.Path]::IsPathRooted($relativePath) -or
            $relativePath -eq '..' -or
            $relativePath.StartsWith("..$([System.IO.Path]::DirectorySeparatorChar)")) {
            throw "Manifest material $($material.materialId) is outside SourceRoot: $($file.FullName)"
        }

        [ordered]@{
            materialId = $material.materialId
            path = $file.FullName
            relativePath = $relativePath -replace '\\', '/'
            sourceType = $material.sourceType
            sourceTitle = $material.title
            publisherOrAuthority = $material.publisherOrAuthority
            region = $material.region
            year = $material.year
            gradeOrScope = $material.gradeOrScope
            editionOrVersion = $material.editionOrVersion
            materialBatchKey = $MaterialBatchKey
            ownerScope = 'school'
            licenseOrPermission = $material.licenseOrPermission
            sharingAllowed = [bool]$material.sharingAllowed
            containsStudentPii = [bool]$material.containsStudentPii
            anonymizationStatus = $material.anonymizationStatus
            mayUseForKnowledgeExtraction = [bool]$material.mayUseForKnowledgeExtraction
            mayUseForExamPointExtraction = [bool]$material.mayUseForExamPointExtraction
            mayUseForTrendAnalysis = [bool]$material.mayUseForTrendAnalysis
            expectedSha256 = ([string]$material.sha256).ToLowerInvariant()
            expectedSizeBytes = if ($material.PSObject.Properties.Name -contains 'sizeBytes') { [long]$material.sizeBytes } else { $file.Length }
            pageCount = if ($material.PSObject.Properties.Name -contains 'pageCount') { [int]$material.pageCount } else { $null }
            textLayer = if ($material.PSObject.Properties.Name -contains 'textLayer') { $material.textLayer } else { $null }
        }
    })
    if ($plan.Count -lt 1) {
        throw 'Manifest source plan is empty'
    }
    return $plan
}

function ConvertTo-CurlBool([bool] $Value) {
    if ($Value) { return 'true' }
    return 'false'
}

function Upload-SourceMaterial([string] $BaseUrl, [object] $Metadata) {
    $args = @(
        '-fsS',
        '-F', "file=@$($Metadata.path);filename=$([System.IO.Path]::GetFileName($Metadata.path))",
        '-F', "sourceType=$($Metadata.sourceType)",
        '-F', "sourceTitle=$($Metadata.sourceTitle)",
        '-F', "region=$($Metadata.region)",
        '-F', "gradeOrScope=$($Metadata.gradeOrScope)",
        '-F', "editionOrVersion=$($Metadata.editionOrVersion)",
        '-F', "materialBatchKey=$($Metadata.materialBatchKey)",
        '-F', "ownerScope=$($Metadata.ownerScope)",
        '-F', "licenseOrPermission=$($Metadata.licenseOrPermission)",
        '-F', "sharingAllowed=$(ConvertTo-CurlBool $Metadata.sharingAllowed)",
        '-F', "containsStudentPii=$(ConvertTo-CurlBool $Metadata.containsStudentPii)",
        '-F', "anonymizationStatus=$($Metadata.anonymizationStatus)",
        '-F', "mayUseForKnowledgeExtraction=$(ConvertTo-CurlBool $Metadata.mayUseForKnowledgeExtraction)",
        '-F', "mayUseForExamPointExtraction=$(ConvertTo-CurlBool $Metadata.mayUseForExamPointExtraction)",
        '-F', "mayUseForTrendAnalysis=$(ConvertTo-CurlBool $Metadata.mayUseForTrendAnalysis)"
    )

    if ($null -ne $Metadata.year) {
        $args += @('-F', "year=$($Metadata.year)")
    }

    $args += "$BaseUrl/files"
    $json = & curl.exe @args
    if ($LASTEXITCODE -ne 0) {
        throw "curl upload failed for $($Metadata.path)"
    }

    return $json | ConvertFrom-Json
}

Push-Location $repoRoot
try {
    if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) {
        $manifestCandidate = if ([System.IO.Path]::IsPathRooted($ManifestPath)) { $ManifestPath } else { Join-Path $repoRoot $ManifestPath }
        $resolvedManifestPath = (Resolve-Path -LiteralPath $manifestCandidate).Path
        $guardOutput = & (Join-Path $PSScriptRoot 'run-c002-source-material-guard.ps1') -ManifestPath $resolvedManifestPath
        if ($LASTEXITCODE -ne 0) {
            throw "Source material manifest guard failed with exit code $LASTEXITCODE"
        }
        $manifestGuard = $guardOutput | ConvertFrom-Json
        if ($manifestGuard.status -ne 'pass' -or $manifestGuard.verifiedFileCount -lt 1) {
            throw 'Source material manifest did not pass real-file admission'
        }
        $plan = @(Get-ManifestSourcePlan -Path $resolvedManifestPath)
        $files = @($plan | ForEach-Object { Get-Item -LiteralPath $_.path } | Sort-Object FullName -Unique)
    }
    else {
        $files = @(Get-ChildItem -LiteralPath $resolvedSourceRoot -Recurse -File -Filter '*.pdf' | Sort-Object FullName)
        if ($files.Count -lt 1) {
            throw "No PDF files found under $resolvedSourceRoot"
        }
        $plan = @($files | ForEach-Object {
            $file = $_
            Get-SourceTypes -File $file | ForEach-Object { Get-SourceMetadata -File $file -SourceType $_ }
        })
    }
    if (@($plan | Where-Object { $_.sourceType -eq 'unknown' }).Count -gt 0) {
        throw 'Source plan contains unknown source types'
    }
    $baseUrl = $ApiUrl.TrimEnd('/')

    $backupVerified = $false
    $databaseSnapshotBefore = $null
    $databaseSnapshotAfter = $null
    if ($Apply) {
        if ([string]::IsNullOrWhiteSpace($BackupManifest)) {
            throw 'BackupManifest is required when applying source material import'
        }
        & (Join-Path $PSScriptRoot 'verify-backup.ps1') -ManifestPath $BackupManifest | Out-Null
        $backupVerified = $true
    }

    if ($Apply -and $StartApi) {
        if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
            throw "DatabasePassword or PGPASSWORD is required when using -StartApi with -Apply"
        }

        $port = Get-FreeTcpPort
        $baseUrl = "http://127.0.0.1:$port"
        $logOut = Join-Path $repoRoot 'docs\evidence\c002-source-import-api.out.log'
        $logErr = Join-Path $repoRoot 'docs\evidence\c002-source-import-api.err.log'
        $env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"
        $env:KqgPaths__FileStoreRoot = $FileStoreRoot

        dotnet ef database update --project apps\api\K12QuestionGraph.Api.csproj --startup-project apps\api\K12QuestionGraph.Api.csproj --configuration Release --no-build | Write-Host
        if ($LASTEXITCODE -ne 0) {
            throw "dotnet ef database update failed"
        }

        $apiProcess = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\api\K12QuestionGraph.Api.csproj','-c','Release','--no-build','--urls',$baseUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr
        Wait-ApiReady -Process $apiProcess -ReadyUrl $baseUrl -LogErr $logErr
    }
    elseif ($Apply -and [string]::IsNullOrWhiteSpace($baseUrl)) {
        throw "Use -ApiUrl or -StartApi with -Apply"
    }

    if ($Apply) {
        $databaseSnapshotBefore = Get-AdmissionDatabaseSnapshot
    }

    $uploaded = New-Object System.Collections.Generic.List[object]
    $idempotencyChecks = New-Object System.Collections.Generic.List[object]
    if ($Apply) {
        foreach ($item in $plan) {
            $response = Upload-SourceMaterial -BaseUrl $baseUrl -Metadata $item
            if ($response.sourceDocument.materialBatchKey -ne $MaterialBatchKey) {
                throw "API persisted an unexpected material batch key for $($item.path)"
            }
            if ($item.expectedSha256 -and $response.sha256 -ne $item.expectedSha256) {
                throw "API persisted an unexpected SHA-256 for $($item.path)"
            }
            if ($response.sourceDocument.sourceType -ne $item.sourceType -or
                $response.sourceDocument.sourceTitle -ne $item.sourceTitle -or
                $response.sourceDocument.region -ne $item.region -or
                $response.sourceDocument.year -ne $item.year -or
                $response.sourceDocument.gradeOrScope -ne $item.gradeOrScope -or
                $response.sourceDocument.editionOrVersion -ne $item.editionOrVersion -or
                $response.sourceDocument.ownerScope -ne $item.ownerScope -or
                $response.sourceDocument.licenseOrPermission -ne $item.licenseOrPermission -or
                $response.sourceDocument.sharingAllowed -ne $item.sharingAllowed -or
                $response.sourceDocument.containsStudentPii -ne $item.containsStudentPii -or
                $response.sourceDocument.anonymizationStatus -ne $item.anonymizationStatus -or
                $response.sourceDocument.mayUseForKnowledgeExtraction -ne $item.mayUseForKnowledgeExtraction -or
                $response.sourceDocument.mayUseForExamPointExtraction -ne $item.mayUseForExamPointExtraction -or
                $response.sourceDocument.mayUseForTrendAnalysis -ne $item.mayUseForTrendAnalysis) {
                throw "API persisted unexpected source metadata or use permissions for $($item.path)"
            }
            if ($item.sourceType -eq 'curriculum_standard' -and $response.sourceDocument.externalAiAllowed -ne $false) {
                throw "API unexpectedly allowed external AI for curriculum material $($item.path)"
            }
            $uploaded.Add([ordered]@{
                materialId = $item.materialId
                path = $item.path
                sourceType = $response.sourceDocument.sourceType
                sourceDocumentId = $response.sourceDocument.id
                fileAssetId = $response.id
                relativePath = $response.relativePath
                sha256 = $response.sha256
                materialBatchKey = $response.sourceDocument.materialBatchKey
                isDuplicate = $response.isDuplicate
            })

            if ($VerifyIdempotency) {
                $repeated = Upload-SourceMaterial -BaseUrl $baseUrl -Metadata $item
                if ($repeated.id -ne $response.id -or
                    $repeated.sourceDocument.id -ne $response.sourceDocument.id -or
                    $repeated.isDuplicate -ne $true) {
                    throw "SourceDocument/FileAsset idempotency failed for $($item.path)"
                }
                $idempotencyChecks.Add([ordered]@{
                    materialId = $item.materialId
                    fileAssetId = $response.id
                    sourceDocumentId = $response.sourceDocument.id
                    repeatedFileAssetId = $repeated.id
                    repeatedSourceDocumentId = $repeated.sourceDocument.id
                    repeatedIsDuplicate = $repeated.isDuplicate
                    pass = $true
                })
            }
        }
        $databaseSnapshotAfter = Get-AdmissionDatabaseSnapshot
        foreach ($field in @('knowledgeNodeCount', 'domainAssetVersionCount', 'knowledgeMappingCount', 'activeDomainAssetCount', 'activeDomainAssetFingerprint')) {
            if ($databaseSnapshotAfter.$field -ne $databaseSnapshotBefore.$field) {
                throw "Source admission unexpectedly changed knowledge or active field: $field"
            }
        }
    }

    $report = [ordered]@{
        status = if ($Apply) { 'uploaded' } else { 'dry_run' }
        sourceRoot = $resolvedSourceRoot
        requestedMaterialBatchKey = $requestedMaterialBatchKey
        materialBatchKey = $MaterialBatchKey
        manifestPath = $resolvedManifestPath
        manifestAdmissionProfile = if ($null -ne $manifestGuard) { $manifestGuard.admissionProfile } else { '' }
        manifestVerifiedFileCount = if ($null -ne $manifestGuard) { $manifestGuard.verifiedFileCount } else { 0 }
        apiUrl = $baseUrl
        backupManifest = if ($Apply) { $BackupManifest } else { '' }
        backupVerified = $backupVerified
        restoreCommand = if ($Apply) { "pwsh -NoProfile -ExecutionPolicy Bypass -File tools\restore.ps1 -ManifestPath '$BackupManifest' -ApplyDatabase -ApplyFileStore -DryRun:`$false" } else { '' }
        databaseSnapshotBefore = $databaseSnapshotBefore
        databaseSnapshotAfter = $databaseSnapshotAfter
        c002ActiveWrite = $false
        c002ActiveFingerprintUnchanged = if ($Apply) { $databaseSnapshotAfter.activeDomainAssetFingerprint -eq $databaseSnapshotBefore.activeDomainAssetFingerprint } else { $true }
        knowledgeAssetWrite = $false
        knowledgeAssetCountsUnchanged = if ($Apply) {
            $databaseSnapshotAfter.knowledgeNodeCount -eq $databaseSnapshotBefore.knowledgeNodeCount -and
            $databaseSnapshotAfter.domainAssetVersionCount -eq $databaseSnapshotBefore.domainAssetVersionCount -and
            $databaseSnapshotAfter.knowledgeMappingCount -eq $databaseSnapshotBefore.knowledgeMappingCount
        }
        else { $true }
        aiRun = $false
        sourceDocumentWrite = $Apply.IsPresent
        fileStoreWrite = $Apply.IsPresent
        sourceDocumentWriteAttempted = $Apply.IsPresent
        fileStoreWriteAttempted = $Apply.IsPresent
        sourceDocumentCountDelta = if ($Apply) { [long]$databaseSnapshotAfter.sourceDocumentCount - [long]$databaseSnapshotBefore.sourceDocumentCount } else { 0 }
        fileAssetCountDelta = if ($Apply) { [long]$databaseSnapshotAfter.fileAssetCount - [long]$databaseSnapshotBefore.fileAssetCount } else { 0 }
        idempotencyRequested = $VerifyIdempotency.IsPresent
        idempotencyVerified = $Apply.IsPresent -and $VerifyIdempotency.IsPresent -and $idempotencyChecks.Count -eq $plan.Count
        fileCount = $files.Count
        physicalFileCount = $files.Count
        logicalSourceCount = $plan.Count
        bySourceType = @($plan | Group-Object { $_.sourceType } | ForEach-Object {
            [ordered]@{ sourceType = $_.Name; count = $_.Count }
        })
        plan = $plan
        uploaded = $uploaded
        idempotencyChecks = $idempotencyChecks
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    if ($null -ne $apiProcess) {
        Stop-Process -Id $apiProcess.Id -Force -ErrorAction SilentlyContinue
    }
    $env:KQG_CONNECTION_STRING = $previousConnectionString
    $env:KqgPaths__FileStoreRoot = $previousFileStoreRoot
    Pop-Location
}

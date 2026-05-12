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
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [string] $MaterialBatchKey = 'guangzhou_physics_2016_2025',
    [string] $ReportPath = 'docs\evidence\c002-source-material-import-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
$resolvedSourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$reportFullPath = Join-Path $repoRoot $ReportPath

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

function Get-SourceMetadata([System.IO.FileInfo] $File) {
    $relativePath = [System.IO.Path]::GetRelativePath($resolvedSourceRoot, $File.FullName)
    $relativeNormalized = $relativePath -replace '\\', '/'
    $name = $File.Name
    $parent = $File.DirectoryName
    $year = Get-YearFromName $name

    $sourceType = 'unknown'
    $gradeOrScope = 'junior_middle_school'
    $editionOrVersion = ''
    $mayKnowledge = $false
    $mayExamPoint = $false
    $mayTrend = $false

    if ($relativeNormalized -like '*/初中物理教材（人教版）/*' -or $parent -like '*初中物理教材*') {
        $sourceType = 'textbook'
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
    elseif ($relativeNormalized -like '*/广州中考年报/*' -or $parent -like '*广州中考年报*') {
        $sourceType = 'exam_analysis_report'
        $gradeOrScope = 'grade_9'
        $editionOrVersion = if ($year) { [string]$year } else { '' }
        $mayExamPoint = $true
        $mayTrend = $true
    }
    elseif ($relativeNormalized -like '*/广州中考真题/*' -or $parent -like '*广州中考真题*') {
        $sourceType = 'local_exam_paper'
        $gradeOrScope = 'grade_9'
        $editionOrVersion = if ($year) { [string]$year } else { '' }
        $mayKnowledge = $true
        $mayExamPoint = $true
        $mayTrend = $true
    }
    elseif ($name -like '*课程标准*') {
        $sourceType = 'curriculum_standard'
        $year = if ($year) { $year } else { 2025 }
        $gradeOrScope = 'junior_middle_school'
        $editionOrVersion = '2022_2025_revision'
        $mayKnowledge = $true
    }

    [ordered]@{
        path = $File.FullName
        relativePath = $relativeNormalized
        sourceType = $sourceType
        sourceTitle = [System.IO.Path]::GetFileNameWithoutExtension($name)
        region = if ($sourceType -eq 'curriculum_standard') { 'China' } else { 'Guangzhou' }
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

function ConvertTo-CurlBool([bool] $Value) {
    if ($Value) { return 'true' }
    return 'false'
}

function Upload-SourceMaterial([string] $BaseUrl, [object] $Metadata) {
    $args = @(
        '-s',
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
    $files = @(Get-ChildItem -LiteralPath $resolvedSourceRoot -Recurse -File -Filter '*.pdf' | Sort-Object FullName)
    if ($files.Count -lt 1) {
        throw "No PDF files found under $resolvedSourceRoot"
    }

    $plan = @($files | ForEach-Object { Get-SourceMetadata $_ })
    $apiProcess = $null
    $previousConnectionString = $env:KQG_CONNECTION_STRING
    $previousFileStoreRoot = $env:KqgPaths__FileStoreRoot
    $baseUrl = $ApiUrl.TrimEnd('/')

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

    $uploaded = New-Object System.Collections.Generic.List[object]
    if ($Apply) {
        foreach ($item in $plan) {
            $response = Upload-SourceMaterial -BaseUrl $baseUrl -Metadata $item
            $uploaded.Add([ordered]@{
                path = $item.path
                sourceType = $response.sourceDocument.sourceType
                sourceDocumentId = $response.sourceDocument.id
                fileAssetId = $response.id
                sha256 = $response.sha256
                materialBatchKey = $response.sourceDocument.materialBatchKey
                isDuplicate = $response.isDuplicate
            })
        }
    }

    $report = [ordered]@{
        status = if ($Apply) { 'uploaded' } else { 'dry_run' }
        sourceRoot = $resolvedSourceRoot
        materialBatchKey = $MaterialBatchKey
        apiUrl = $baseUrl
        fileCount = $plan.Count
        bySourceType = @($plan | Group-Object { $_.sourceType } | ForEach-Object {
            [ordered]@{ sourceType = $_.Name; count = $_.Count }
        })
        plan = $plan
        uploaded = $uploaded
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

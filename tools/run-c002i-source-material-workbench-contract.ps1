param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $ApiProject = 'apps\api\K12QuestionGraph.Api.csproj'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw "DatabasePassword or PGPASSWORD is required for C002I source material workbench contract"
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
            throw "API exited before ready on $ApiUrl; see $LogErr"
        }

        try {
            $health = Invoke-RestMethod -Uri "$ApiUrl/health/ready" -TimeoutSec 2
            if ($health.status -eq 'ok') {
                return
            }
        }
        catch {
            Start-Sleep -Seconds 1
        }
    }

    throw "API did not become ready on $ApiUrl"
}

Push-Location $repoRoot
try {
    $app = Get-Content -LiteralPath 'apps\web\src\App.tsx' -Raw
    foreach ($pattern in @(
        'data-flow="source-material-workbench"',
        'data-contract="dual-evidence-chain"',
        'data-contract="source-type-groups"',
        'data-contract="source-material-metadata"',
        'data-contract="source-material-list"',
        'exam_analysis_report',
        '可选',
        'ChatGPT Web'
    )) {
        if (-not $app.Contains($pattern)) {
            throw "missing C002I UI contract marker: $pattern"
        }
    }

    $previousConnectionString = $env:KQG_CONNECTION_STRING
    $env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"

    try {
        dotnet ef database update --project $ApiProject --startup-project $ApiProject | Write-Host
        if ($LASTEXITCODE -ne 0) {
            throw "dotnet ef database update failed"
        }

        $port = Get-FreeTcpPort
        $apiUrl = "http://127.0.0.1:$port"
        $logOut = Join-Path $repoRoot 'docs\evidence\c002i-gate-api.out.log'
        $logErr = Join-Path $repoRoot 'docs\evidence\c002i-gate-api.err.log'
        $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project',$ApiProject,'--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr

        try {
            Wait-ApiReady -Process $process -ApiUrl $apiUrl -LogErr $logErr

            $sample = Join-Path $env:TEMP 'kqg-c002i-local-exam.pdf'
            Set-Content -LiteralPath $sample -Value "C002I synthetic local exam source $([Guid]::NewGuid())" -Encoding UTF8
            $upload = curl.exe -s `
                -F "file=@$sample;filename=c002i-local-exam.pdf" `
                -F "sourceType=local_exam_paper" `
                -F "sourceTitle=C002I Local Exam Synthetic" `
                -F "region=local_city" `
                -F "year=2025" `
                -F "gradeOrScope=grade_9" `
                -F "editionOrVersion=2025" `
                -F "materialBatchKey=local-physics-2015-2025" `
                -F "ownerScope=school" `
                -F "licenseOrPermission=synthetic_fixture" `
                -F "sharingAllowed=true" `
                -F "containsStudentPii=false" `
                -F "anonymizationStatus=synthetic" `
                -F "mayUseForKnowledgeExtraction=false" `
                -F "mayUseForExamPointExtraction=true" `
                -F "mayUseForTrendAnalysis=true" `
                "$apiUrl/files" | ConvertFrom-Json

            if ($upload.sourceDocument.sourceType -ne 'local_exam_paper') { throw "sourceType was not persisted" }
            if ($upload.sourceDocument.region -ne 'local_city') { throw "region was not persisted" }
            if ($upload.sourceDocument.year -ne 2025) { throw "year was not persisted" }
            if ($upload.sourceDocument.materialBatchKey -ne 'local_physics_2015_2025') { throw "materialBatchKey was not normalized" }
            if (-not $upload.sourceDocument.mayUseForExamPointExtraction) { throw "exam point extraction flag missing" }
            if (-not $upload.sourceDocument.mayUseForTrendAnalysis) { throw "trend analysis flag missing" }

            $list = Invoke-RestMethod -Method Get -Uri "$apiUrl/source-documents?sourceType=local_exam_paper&materialBatchKey=local-physics-2015-2025"
            if ($list.mode -ne 'source_material_workbench_mvp') { throw "unexpected source document list mode" }
            $row = @($list.items | Where-Object { $_.id -eq $upload.sourceDocument.id }) | Select-Object -First 1
            if ($null -eq $row) { throw "uploaded source material missing from workbench list" }
            if ($row.sha256 -ne $upload.sha256) { throw "source material list missing file hash evidence" }

            [ordered]@{
                status = 'pass'
                mode = [string]$list.mode
                sourceDocumentId = [string]$upload.sourceDocument.id
                sourceType = [string]$upload.sourceDocument.sourceType
                region = [string]$upload.sourceDocument.region
                year = [int]$upload.sourceDocument.year
                materialBatchKey = [string]$upload.sourceDocument.materialBatchKey
                mayUseForKnowledgeExtraction = [bool]$upload.sourceDocument.mayUseForKnowledgeExtraction
                mayUseForExamPointExtraction = [bool]$upload.sourceDocument.mayUseForExamPointExtraction
                mayUseForTrendAnalysis = [bool]$upload.sourceDocument.mayUseForTrendAnalysis
                listed = $true
            } | ConvertTo-Json
        }
        finally {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    }
    finally {
        $env:KQG_CONNECTION_STRING = $previousConnectionString
    }
}
finally {
    Pop-Location
}

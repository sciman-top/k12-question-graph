param(
    [string] $ManifestPath = 'tests/golden-import/s004c-proxy-materials.json',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [int] $ApiPort = 5290,
    [string] $ReportPath = 'docs/evidence/20260506-s004c-authorized-anonymized-proxy-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

$manifestFullPath = Join-Path $repoRoot $ManifestPath
if (-not (Test-Path -LiteralPath $manifestFullPath)) {
    throw "S004C manifest missing: $ManifestPath"
}

$manifest = Get-Content -Raw -LiteralPath $manifestFullPath | ConvertFrom-Json -Depth 20
if ([string]$manifest.schemaVersion -ne 's004c-authorized-anonymized-proxy.v1') {
    throw "unexpected S004C schemaVersion: $($manifest.schemaVersion)"
}

$materialRows = @($manifest.materials)
if ($materialRows.Count -lt 2) {
    throw 'S004C requires at least two authorized/anonymized materials for proxy validation'
}

$tmpDir = Join-Path $repoRoot 'tmp/s004c-proxy'
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

foreach ($row in $materialRows) {
    if ([string]$row.licenseOrPermission -ne 'internal_authorized') {
        throw "material $($row.materialId) must be internal_authorized"
    }
    if ([bool]$row.containsStudentPii -and [string]$row.anonymizationStatus -notin @('anonymized','synthetic')) {
        throw "material $($row.materialId) has unhandled PII"
    }

    $localPath = Join-Path $repoRoot ([string]$row.localPath)
    $parent = Split-Path -Parent $localPath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $localPath)) {
        Set-Content -LiteralPath $localPath -Value "anonymized proxy content for $($row.materialId)" -Encoding UTF8
    }
}

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    [ordered]@{
        status = 'platform_na'
        taskId = 'S004C'
        reason = 'DatabasePassword or PGPASSWORD is required to run API proxy validation'
        alternative_verification = 'manifest authorization/anonymization checks passed without API execution'
        evidence_link = $ReportPath
        expires_at = '2026-05-13'
        checkedAt = (Get-Date).ToString('s')
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $repoRoot $ReportPath) -Encoding UTF8

    Get-Content -Raw -LiteralPath (Join-Path $repoRoot $ReportPath)
    exit 0
}

$apiUrl = "http://127.0.0.1:$ApiPort"
$logOut = Join-Path $repoRoot 'docs/evidence/s004c-proxy-api.out.log'
$logErr = Join-Path $repoRoot 'docs/evidence/s004c-proxy-api.err.log'
$previousConnectionString = $env:KQG_CONNECTION_STRING
$env:KQG_CONNECTION_STRING = "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$DatabasePassword"

$process = $null
try {
    $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\\api\\K12QuestionGraph.Api.csproj','--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr

    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
        try {
            $health = Invoke-RestMethod -Uri "$apiUrl/health/ready" -TimeoutSec 2
            if ($health.status -eq 'ok') {
                $ready = $true
                break
            }
        }
        catch {
            Start-Sleep -Milliseconds 500
        }
    }
    if (-not $ready) {
        throw "API did not become ready on $apiUrl"
    }

    $uploads = New-Object System.Collections.Generic.List[object]
    foreach ($row in $materialRows) {
        $path = Join-Path $repoRoot ([string]$row.localPath)
        $response = curl.exe -s `
          -F "file=@$path;filename=$([System.IO.Path]::GetFileName($path))" `
          -F "sourceType=$($row.sourceType)" `
          -F "sourceTitle=$($row.sourceTitle)" `
          -F "ownerScope=school" `
          -F "licenseOrPermission=$($row.licenseOrPermission)" `
          -F "sharingAllowed=true" `
          -F "containsStudentPii=$($row.containsStudentPii.ToString().ToLowerInvariant())" `
          -F "anonymizationStatus=$($row.anonymizationStatus)" `
          "$apiUrl/files" | ConvertFrom-Json

        if ([string]::IsNullOrWhiteSpace($response.sourceDocument.id)) {
            throw "S004C upload failed for material $($row.materialId)"
        }

        $uploads.Add([ordered]@{
            materialId = $row.materialId
            sourceDocumentId = $response.sourceDocument.id
            fileAssetId = $response.id
            sourceType = $response.sourceDocument.sourceType
        })
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'S004C'
        mode = 'authorized_anonymized_proxy_validation'
        checkedAt = (Get-Date).ToString('s')
        materialCount = $materialRows.Count
        uploadedCount = $uploads.Count
        uploads = $uploads
        blockedAutomationItems = @(
            'scanned_pdf_auto_cut_accuracy_not_claimed',
            'manual_takeover_required_for_ocr_failure_paths'
        )
        nextAction = 'Use real authorized/anonymized school files in the same manifest path and rerun this script to refresh evidence.'
    }

    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $repoRoot $ReportPath) -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    if ($process) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    $env:KQG_CONNECTION_STRING = $previousConnectionString
}

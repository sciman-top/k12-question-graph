param(
    [int]$Port = 0
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$apiProject = Join-Path $repoRoot "apps/api/K12QuestionGraph.Api.csproj"
$fixturePath = Join-Path $repoRoot "configs/domain-assets/k004-historical-version-explanation.sample.json"
$evidenceDir = Join-Path $repoRoot "docs/evidence"
$reportPath = Join-Path $evidenceDir "k004-historical-version-explanation-report.json"
$stdoutPath = Join-Path $evidenceDir "k004-api-stdout.log"
$stderrPath = Join-Path $evidenceDir "k004-api-stderr.log"

New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null

if ($Port -le 0) {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $Port = $listener.LocalEndpoint.Port
    $listener.Stop()
}

$baseUrl = "http://127.0.0.1:$Port"
$env:ASPNETCORE_URLS = $baseUrl
$env:ASPNETCORE_ENVIRONMENT = "Development"

$process = Start-Process `
    -FilePath "dotnet" `
    -ArgumentList @("run", "--project", $apiProject, "-c", "Release", "--no-build", "--no-launch-profile") `
    -WorkingDirectory $repoRoot `
    -PassThru `
    -WindowStyle Hidden `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath

try {
    $ready = $false
    for ($i = 0; $i -lt 60; $i++) {
        if ($process.HasExited) {
            throw "API process exited before health check. See $stderrPath"
        }

        try {
            $health = Invoke-RestMethod -Uri "$baseUrl/health" -Method Get -TimeoutSec 2
            if ($health.status -eq "ok") {
                $ready = $true
                break
            }
        }
        catch {
            Start-Sleep -Milliseconds 500
        }
    }

    if (-not $ready) {
        throw "API health check timed out at $baseUrl/health"
    }

    $fixture = Get-Content -Raw -Path $fixturePath | ConvertFrom-Json
    $responses = @()
    $artifactTypes = New-Object System.Collections.Generic.HashSet[string]
    $mappingTypes = New-Object System.Collections.Generic.HashSet[string]

    foreach ($case in $fixture.cases) {
        $body = $case | ConvertTo-Json -Depth 8
        $response = Invoke-RestMethod `
            -Uri "$baseUrl/knowledge-version-explanations/resolve" `
            -Method Post `
            -ContentType "application/json" `
            -Body $body `
            -TimeoutSec 10

        if ($response.mode -ne "historical_version_explanation_contract") {
            throw "Unexpected mode for $($case.artifactId): $($response.mode)"
        }

        if ($response.productionEligible -ne $false -or $response.readOnly -ne $true) {
            throw "K004 must stay read-only and non-production for $($case.artifactId)"
        }

        if ($response.realStudentDataUsed -ne $false -or $response.writesProductionHistory -ne $false) {
            throw "K004 must not use real student data or write production history for $($case.artifactId)"
        }

        if ($response.frozenHistoricalView -ne $true) {
            throw "K004 must freeze historical view for $($case.artifactId)"
        }

        if ([string]::IsNullOrWhiteSpace($response.explanationText) -or
            -not $response.explanationText.Contains($case.historicalKnowledgeVersion) -or
            -not $response.explanationText.Contains($case.currentKnowledgeVersion)) {
            throw "Explanation text must mention historical and current versions for $($case.artifactId)"
        }

        foreach ($target in $case.currentKnowledgeStableIds) {
            if (-not $response.explanationText.Contains($target)) {
                throw "Explanation text must mention mapped target $target for $($case.artifactId)"
            }
        }

        if ([string]::IsNullOrWhiteSpace($response.teacherVisibleSummary)) {
            throw "Teacher-visible summary required for $($case.artifactId)"
        }

        [void]$artifactTypes.Add([string]$response.artifactType)
        [void]$mappingTypes.Add([string]$response.mappingType)
        $responses += $response
    }

    foreach ($requiredArtifactType in @("question", "paper", "analysis_report")) {
        if (-not $artifactTypes.Contains($requiredArtifactType)) {
            throw "Missing artifact type coverage: $requiredArtifactType"
        }
    }

    foreach ($requiredMappingType in @("renamed", "split", "deprecated")) {
        if (-not $mappingTypes.Contains($requiredMappingType)) {
            throw "Missing mapping type coverage: $requiredMappingType"
        }
    }

    $report = [ordered]@{
        rule_id = "K004"
        risk_level = "low"
        command = "pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-k004-historical-version-explanation-contract.ps1"
        api_base_url = $baseUrl
        fixture_path = "configs/domain-assets/k004-historical-version-explanation.sample.json"
        endpoint = "POST /knowledge-version-explanations/resolve"
        case_count = $responses.Count
        artifact_types = @($artifactTypes)
        mapping_types = @($mappingTypes)
        read_only = $true
        real_student_data_used = $false
        writes_production_history = $false
        rollback = "git revert the K004 commit; no database, active asset, or production history writes are performed"
        generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    }

    $report | ConvertTo-Json -Depth 8 | Set-Content -Path $reportPath -Encoding UTF8
    Write-Host "K004 historical version explanation contract passed: $reportPath"
}
finally {
    if ($process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit()
    }
}

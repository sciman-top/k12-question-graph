param(
    [ValidateSet('Ci', 'Release')]
    [string] $Mode = 'Ci',
    [string] $ReportRoot = 'tmp/repo-preflight',
    [switch] $InstallFrontendDependencies,
    [switch] $SkipFullGate,
    [string] $JsonReportPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$reportRootFullPath = Join-Path $repoRoot $ReportRoot
New-Item -ItemType Directory -Path $reportRootFullPath -Force | Out-Null
$referenceValidationMode = if ($Mode -eq 'Ci') { 'Ci' } else { 'Local' }

function Get-DefaultLocalApiProcess {
    $expectedPath = Join-Path $repoRoot 'apps\api\bin\Release\net10.0\K12QuestionGraph.Api.exe'
    $listener = Get-NetTCPConnection -LocalPort 5275 -State Listen -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($null -eq $listener) {
        return $null
    }

    $process = Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
    if ($null -eq $process) {
        return $null
    }

    $processPath = $null
    try {
        $processPath = $process.Path
    }
    catch {
        return $null
    }

    if ($process.ProcessName -ne 'K12QuestionGraph.Api') {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($processPath)) {
        return $null
    }

    if (-not $processPath.Equals($expectedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    return $process
}

function Get-DefaultLocalWebProcess {
    $repoWebPath = Join-Path $repoRoot 'apps\web'
    $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue)

    foreach ($process in $processes) {
        $commandLine = [string] $process.CommandLine
        if ([string]::IsNullOrWhiteSpace($commandLine)) {
            continue
        }

        if ($commandLine.IndexOf($repoWebPath, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
            continue
        }

        if ($commandLine.IndexOf('vite.js', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
            continue
        }

        if ($commandLine.IndexOf('--port 5173', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
            continue
        }

        return $process
    }

    return $null
}

function Get-HostLocalFrontendDebrisPaths {
    $webRoot = Join-Path $repoRoot 'apps\web'
    $debrisDirs = @(Get-ChildItem -Path $webRoot -Directory -Filter 'node_modules_broken_*' -ErrorAction SilentlyContinue)

    return @(
        $debrisDirs |
        ForEach-Object { [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName) -replace '\\', '/' } |
        Sort-Object -Unique
    )
}

function Invoke-PreflightStep {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][scriptblock] $Action
    )

    $startedAt = Get-Date
    & $Action
    $finishedAt = Get-Date

    return [ordered]@{
        name = $Name
        startedAt = $startedAt.ToString('s')
        finishedAt = $finishedAt.ToString('s')
        durationSeconds = [Math]::Round(($finishedAt - $startedAt).TotalSeconds, 3)
        status = 'pass'
    }
}

$steps = New-Object System.Collections.Generic.List[object]
$resumeDefaultLocalApi = $false

Push-Location $repoRoot
try {
    $defaultLocalApi = Get-DefaultLocalApiProcess
    $defaultLocalWeb = Get-DefaultLocalWebProcess

    if ($null -ne $defaultLocalApi) {
        Stop-Process -Id $defaultLocalApi.Id -Force
        Start-Sleep -Milliseconds 800

        if (Test-Path -LiteralPath 'logs\dev-api\api.pid') {
            Remove-Item -LiteralPath 'logs\dev-api\api.pid' -Force
        }

        $stillRunning = Get-Process -Id $defaultLocalApi.Id -ErrorAction SilentlyContinue
        if ($null -ne $stillRunning) {
            throw "failed to pause default local API process $($defaultLocalApi.Id) before repo preflight"
        }

        $resumeDefaultLocalApi = $true
    }

    if ($InstallFrontendDependencies) {
        if ($null -ne $defaultLocalWeb) {
            throw "frontend dependency install is blocked by the repo-local Vite dev server (pid $($defaultLocalWeb.ProcessId)). Stop the local web server or rerun preflight without -InstallFrontendDependencies."
        }

        $steps.Add((Invoke-PreflightStep 'frontend npm ci' {
            Push-Location 'apps\web'
            try {
                npm ci | Out-Host
                if ($LASTEXITCODE -ne 0) { throw 'npm ci failed' }
            }
            finally {
                Pop-Location
            }
        }))
    }

    $steps.Add((Invoke-PreflightStep 'backend build' {
        dotnet build apps\api\K12QuestionGraph.Api.csproj -c Release | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'dotnet build failed' }
    }))

    $steps.Add((Invoke-PreflightStep 'frontend host-local debris guard' {
        $debrisPaths = @(Get-HostLocalFrontendDebrisPaths)
        if ($debrisPaths.Count -gt 0) {
            throw ("host-local frontend debris blocks repo preflight: {0}. Remove or move these temporary directories outside apps/web before rerunning. This is host-local drift, not repo source lint failure." -f ($debrisPaths -join ', '))
        }
    }))

    $steps.Add((Invoke-PreflightStep 'frontend lint' {
        Push-Location 'apps\web'
        try {
            npm run lint | Out-Host
            if ($LASTEXITCODE -ne 0) { throw 'npm run lint failed' }
        }
        finally {
            Pop-Location
        }
    }))

    $steps.Add((Invoke-PreflightStep 'frontend build' {
        Push-Location 'apps\web'
        try {
            npm run build | Out-Host
            if ($LASTEXITCODE -ne 0) { throw 'npm run build failed' }
        }
        finally {
            Pop-Location
        }
    }))

    $steps.Add((Invoke-PreflightStep 'automation-first guard' {
        .\tools\run-automation-first-feature-contract-guard.ps1 `
            -JsonReportPath (Join-Path $ReportRoot 'automation-first-feature-contract-report.json') | Out-Null
    }))

    $steps.Add((Invoke-PreflightStep 'reference-basis guard' {
        .\tools\run-reference-basis-guard.ps1 `
            -ValidationMode $referenceValidationMode `
            -JsonReportPath (Join-Path $ReportRoot 'reference-basis-guard.json') `
            -MarkdownReportPath (Join-Path $ReportRoot 'reference-basis-guard.md') | Out-Null
    }))

    $steps.Add((Invoke-PreflightStep 'live-closeout guard' {
        .\tools\run-live-pilot-closeout-plan-guard.ps1 `
            -JsonReportPath (Join-Path $ReportRoot 'live-pilot-closeout-plan-guard.json') `
            -MarkdownReportPath (Join-Path $ReportRoot 'live-pilot-closeout-plan-guard.md') | Out-Null
    }))

    $steps.Add((Invoke-PreflightStep 'pqr preflight pack contract' {
        .\tools\run-pqr-preflight-pack-contract.ps1 `
            -ReportPath (Join-Path $ReportRoot 'pqr-preflight-pack-report.json') | Out-Null
    }))

    $steps.Add((Invoke-PreflightStep 'pqr preflight dashboard contract' {
        .\tools\run-pqr-preflight-dashboard-contract.ps1 `
            -DashboardJsonPath (Join-Path $ReportRoot 'pqr-preflight-dashboard.json') `
            -DashboardMarkdownPath (Join-Path $ReportRoot 'pqr-preflight-dashboard.md') | Out-Null
    }))

    $steps.Add((Invoke-PreflightStep 'pqr preflight freshness guard' {
        .\tools\run-pqr-preflight-freshness-guard.ps1 `
            -ReportPath (Join-Path $ReportRoot 'pqr-preflight-freshness-report.json') | Out-Null
    }))

    $steps.Add((Invoke-PreflightStep 'ns1308 release evidence pack contract' {
        .\tools\run-ns1308-release-evidence-pack-contract.ps1 `
            -ReportPath (Join-Path $ReportRoot 'ns1308-release-evidence-pack.json') | Out-Null
    }))

    $steps.Add((Invoke-PreflightStep 'roadmap guard' {
        $roadmapJson = .\tools\run-roadmap-guard.ps1
        Set-Content -LiteralPath (Join-Path $reportRootFullPath 'roadmap-guard.json') -Value $roadmapJson -Encoding UTF8
    }))

    if (($Mode -eq 'Release') -and (-not $SkipFullGate)) {
        $steps.Add((Invoke-PreflightStep 'full local gate' {
            .\tools\run-gates.ps1
        }))
    }

    $summary = [ordered]@{
        status = 'pass'
        checkedAt = (Get-Date).ToString('s')
        mode = $Mode
        referenceValidationMode = $referenceValidationMode
        reportRoot = $ReportRoot
        installFrontendDependencies = [bool]$InstallFrontendDependencies
        fullGateIncluded = (($Mode -eq 'Release') -and (-not $SkipFullGate))
        pausedDefaultLocalApi = $resumeDefaultLocalApi
        stepCount = $steps.Count
        steps = $steps
        boundary = if ($Mode -eq 'Ci') {
            'CI preflight validates repo-side build, lint, planning, reference-basis, closeout, and release-pack contracts without pretending to replace the local full gate.'
        }
        else {
            'Release-mode preflight validates the same repo-side contracts and then enters the local full gate unless SkipFullGate is explicitly supplied.'
        }
    }

    $summaryPath = Join-Path $reportRootFullPath 'repo-preflight-summary.json'
    $summaryJson = $summary | ConvertTo-Json -Depth 8
    $summaryJson | Set-Content -LiteralPath $summaryPath -Encoding UTF8

    if (-not [string]::IsNullOrWhiteSpace($JsonReportPath)) {
        $jsonFullPath = Join-Path $repoRoot $JsonReportPath
        New-Item -ItemType Directory -Path (Split-Path -Parent $jsonFullPath) -Force | Out-Null
        $summaryJson | Set-Content -LiteralPath $jsonFullPath -Encoding UTF8
    }

    $summaryJson
}
finally {
    if ($resumeDefaultLocalApi) {
        .\tools\start-local-api.ps1 | Out-Null
    }

    Pop-Location
}

param(
    [string]$Configuration = 'Release',
    [string]$Runtime = 'win-x64',
    [switch]$SelfContained,
    [string]$OutputRoot = 'tmp/o001/windows-service-package',
    [switch]$SkipWebBuild
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$packageRoot = Join-Path $repoRoot $OutputRoot
$apiPublishRoot = Join-Path $packageRoot 'api'
$webPublishRoot = Join-Path $packageRoot 'web'
$workerPublishRoot = Join-Path $apiPublishRoot 'worker/document'

function Assert-True([bool]$Condition, [string]$Message) {
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

function Wait-Health([System.Diagnostics.Process]$Process, [string]$HealthUrl, [int]$MaxSeconds = 40) {
    for ($i = 0; $i -lt $MaxSeconds; $i++) {
        if ($Process.HasExited) {
            throw "Published API exited early; see process logs."
        }

        try {
            $health = Invoke-RestMethod -Uri $HealthUrl -TimeoutSec 2
            if ($health.status -eq 'ok') {
                return $health
            }
        }
        catch {
            Start-Sleep -Seconds 1
        }
    }

    throw "Published API was not healthy within $MaxSeconds seconds"
}

Remove-Item -LiteralPath $packageRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null

Push-Location $repoRoot
try {
    if (-not $SkipWebBuild) {
        Push-Location (Join-Path $repoRoot 'apps/web')
        try {
            npm run build | Write-Host
            if ($LASTEXITCODE -ne 0) { throw 'npm run build failed' }
        }
        finally {
            Pop-Location
        }

        New-Item -ItemType Directory -Path $webPublishRoot -Force | Out-Null
        Copy-Item -Path (Join-Path $repoRoot 'apps/web/dist/*') -Destination $webPublishRoot -Recurse -Force
    }

    $publishArgs = @(
        'publish',
        'apps/api/K12QuestionGraph.Api.csproj',
        '-c', $Configuration,
        '-r', $Runtime,
        '-o', $apiPublishRoot,
        '/p:UseAppHost=true'
    )

    if ($SelfContained) {
        $publishArgs += '--self-contained'
        $publishArgs += 'true'
    }
    else {
        $publishArgs += '--self-contained'
        $publishArgs += 'false'
    }

    dotnet @publishArgs | Write-Host
    if ($LASTEXITCODE -ne 0) { throw 'dotnet publish failed' }

    New-Item -ItemType Directory -Path $workerPublishRoot -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'workers/document/worker.py') -Destination (Join-Path $workerPublishRoot 'worker.py') -Force

    $apiExe = Join-Path $apiPublishRoot 'K12QuestionGraph.Api.exe'
    Assert-True (Test-Path $apiExe) "publish output missing: $apiExe"

    $publishedAppSettings = Join-Path $apiPublishRoot 'appsettings.json'
    Assert-True (Test-Path $publishedAppSettings) 'publish output missing appsettings.json'
    $appSettings = Get-Content -LiteralPath $publishedAppSettings -Raw | ConvertFrom-Json

    $configuredWorkerScript = [string]$appSettings.PythonWorker.DocumentWorkerScript
    $normalizedWorkerScript = $configuredWorkerScript.Replace('/', '\').ToLowerInvariant()
    Assert-True ($normalizedWorkerScript -eq 'worker\document\worker.py') "PythonWorker.DocumentWorkerScript must point to package-local worker path, got: $configuredWorkerScript"
    foreach ($field in @('DataRoot', 'FileStoreRoot', 'BackupRoot', 'LogsRoot')) {
        $value = [string]$appSettings.KqgPaths.$field
        Assert-True ($value -match '^[A-Za-z]:\\') "KqgPaths.$field must be an absolute path, got: $value"
    }

    $port = Get-FreeTcpPort
    $apiUrl = "http://127.0.0.1:$port"
    $tempRunDir = Join-Path $env:TEMP ("kqg-o001-run-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempRunDir -Force | Out-Null

    $stdoutLog = Join-Path $packageRoot 'published-api.out.log'
    $stderrLog = Join-Path $packageRoot 'published-api.err.log'

    $process = Start-Process -FilePath $apiExe -ArgumentList @('--urls', $apiUrl, '--contentRoot', $apiPublishRoot) -WorkingDirectory $tempRunDir -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
    try {
        $health = Wait-Health -Process $process -HealthUrl "$apiUrl/health"
        $ready = Invoke-RestMethod -Uri "$apiUrl/health/ready" -TimeoutSec 5

        $workerCheck = @($ready.checks | Where-Object { $_.name -eq 'document_worker_script' })
        Assert-True ($workerCheck.Count -eq 1) 'missing document_worker_script readiness check'
        Assert-True ([bool]$workerCheck[0].ok) ('document worker script check failed: ' + [string]$workerCheck[0].detail)

        $healthContentRoot = [string]$health.contentRoot
        $healthDataRoot = [string]$health.dataRoot
        Assert-True ($healthContentRoot -eq (Resolve-Path -LiteralPath $apiPublishRoot).Path) "content root mismatch: $healthContentRoot"
        Assert-True ($healthDataRoot -ne $healthContentRoot) 'program and data roots must be separated'

        [ordered]@{
            status = 'pass'
            task = 'O001'
            packageRoot = $packageRoot
            apiPublishRoot = $apiPublishRoot
            webPublishRoot = $webPublishRoot
            workerScript = (Join-Path $workerPublishRoot 'worker.py')
            runtime = $Runtime
            selfContained = [bool]$SelfContained
            smoke = [ordered]@{
                apiUrl = $apiUrl
                runWorkingDirectory = $tempRunDir
                contentRoot = $healthContentRoot
                dataRoot = $healthDataRoot
                workerScriptCheck = $workerCheck[0]
            }
            evidence = [ordered]@{
                stdoutLog = $stdoutLog
                stderrLog = $stderrLog
            }
            rollback = [ordered]@{
                packageDelete = "Remove-Item -LiteralPath '$packageRoot' -Recurse -Force"
            }
        } | ConvertTo-Json -Depth 8
    }
    finally {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
}
finally {
    Pop-Location
}

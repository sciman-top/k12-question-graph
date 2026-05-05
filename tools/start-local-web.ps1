param(
    [switch] $Restart,
    [switch] $Stop,
    [switch] $Status,
    [string] $HostName = '127.0.0.1',
    [int] $Port = 5173
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$webRoot = Join-Path $repoRoot 'apps\web'
$logRoot = Join-Path $repoRoot 'logs\dev-web'
$pidPath = Join-Path $logRoot 'vite.pid'
$stdoutPath = Join-Path $logRoot 'vite.out.log'
$stderrPath = Join-Path $logRoot 'vite.err.log'

function Get-ListenerProcess {
    param(
        [int] $LocalPort
    )

    $connection = Get-NetTCPConnection -LocalPort $LocalPort -State Listen -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($null -eq $connection) {
        return $null
    }

    return Get-Process -Id $connection.OwningProcess -ErrorAction SilentlyContinue
}

function Test-WebReady {
    param(
        [string] $Url
    )

    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 2
        return $response.StatusCode -ge 200 -and $response.StatusCode -lt 500
    }
    catch {
        return $false
    }
}

function Stop-WebServer {
    $listener = Get-ListenerProcess -LocalPort $Port
    if ($null -ne $listener) {
        Stop-Process -Id $listener.Id -Force
        Start-Sleep -Milliseconds 500
    }

    if (Test-Path -LiteralPath $pidPath) {
        Remove-Item -LiteralPath $pidPath -Force
    }
}

New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

$url = "http://${HostName}:${Port}/"

if ($Stop -or $Restart) {
    Stop-WebServer
}

if ($Stop) {
    [pscustomobject]@{
        status = 'stopped'
        url = $url
        pidPath = $pidPath
    } | ConvertTo-Json -Depth 4
    exit 0
}

$listener = Get-ListenerProcess -LocalPort $Port
if ($Status) {
    [pscustomobject]@{
        status = if ($null -ne $listener) { 'running' } else { 'stopped' }
        url = $url
        listenerPid = if ($null -ne $listener) { $listener.Id } else { $null }
        listenerProcess = if ($null -ne $listener) { $listener.ProcessName } else { $null }
        ready = Test-WebReady -Url $url
        pidPath = $pidPath
        stdoutLog = $stdoutPath
        stderrLog = $stderrPath
    } | ConvertTo-Json -Depth 4
    exit 0
}

if ($null -ne $listener) {
    [pscustomobject]@{
        status = 'already_running'
        url = $url
        listenerPid = $listener.Id
        listenerProcess = $listener.ProcessName
        ready = Test-WebReady -Url $url
        pidPath = $pidPath
        stdoutLog = $stdoutPath
        stderrLog = $stderrPath
    } | ConvertTo-Json -Depth 4
    exit 0
}

if (-not (Test-Path -LiteralPath (Join-Path $webRoot 'package.json'))) {
    throw "Web package.json not found: $webRoot"
}

if (-not (Test-Path -LiteralPath (Join-Path $webRoot 'node_modules'))) {
    Push-Location $webRoot
    try {
        npm ci
    }
    finally {
        Pop-Location
    }
}

Set-Content -LiteralPath $stdoutPath -Value ''
Set-Content -LiteralPath $stderrPath -Value ''

$arguments = @(
    '/c',
    'npm',
    'run',
    'dev',
    '--',
    '--host',
    $HostName,
    '--port',
    [string] $Port,
    '--strictPort'
)

$process = Start-Process `
    -FilePath 'cmd.exe' `
    -ArgumentList $arguments `
    -WorkingDirectory $webRoot `
    -PassThru `
    -WindowStyle Hidden `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath

Set-Content -LiteralPath $pidPath -Value ([string] $process.Id)

$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 500
    $ready = Test-WebReady -Url $url
    if ($ready) {
        break
    }
}

$listener = Get-ListenerProcess -LocalPort $Port

[pscustomobject]@{
    status = if ($ready) { 'started' } else { 'starting_or_failed' }
    url = $url
    launcherPid = $process.Id
    listenerPid = if ($null -ne $listener) { $listener.Id } else { $null }
    listenerProcess = if ($null -ne $listener) { $listener.ProcessName } else { $null }
    ready = $ready
    pidPath = $pidPath
    stdoutLog = $stdoutPath
    stderrLog = $stderrPath
} | ConvertTo-Json -Depth 4

param(
    [switch] $Restart,
    [switch] $Stop,
    [switch] $Status,
    [string] $HostName = '127.0.0.1',
    [int] $Port = 5275,
    [string] $Environment = 'Development',
    [string] $Configuration = 'Release',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabasePassword = $env:PGPASSWORD
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$logRoot = Join-Path $repoRoot 'logs\dev-api'
$pidPath = Join-Path $logRoot 'api.pid'
$stdoutPath = Join-Path $logRoot 'api.out.log'
$stderrPath = Join-Path $logRoot 'api.err.log'
$apiBinaryDirectory = Join-Path $repoRoot "apps\api\bin\$Configuration\net10.0"
$apiDllPath = Join-Path $apiBinaryDirectory 'K12QuestionGraph.Api.dll'
$apiContentRoot = Join-Path $repoRoot 'apps\api'

. (Join-Path $PSScriptRoot 'database-env.ps1')

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

function Get-RepoApiProcesses {
    $processes = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        ($_.Name -eq 'dotnet.exe' -or $_.Name -eq 'K12QuestionGraph.Api.exe') -and
        $_.CommandLine -like '*K12QuestionGraph.Api*' -and
        $_.CommandLine -like '*k12-question-graph*'
    }

    foreach ($process in $processes) {
        Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
    }
}

function Test-ApiReady {
    param(
        [string] $Url
    )

    try {
        $response = Invoke-RestMethod -Uri "$Url/health/ready" -TimeoutSec 2
        return $response.status -eq 'ok'
    }
    catch {
        return $false
    }
}

function Stop-ApiServer {
    $listener = Get-ListenerProcess -LocalPort $Port
    if ($null -ne $listener) {
        Stop-Process -Id $listener.Id -Force
        Start-Sleep -Milliseconds 500
    }

    $repoProcesses = Get-RepoApiProcesses | Where-Object { $null -ne $_ }
    foreach ($process in $repoProcesses) {
        if ($null -ne $listener -and $process.Id -eq $listener.Id) {
            continue
        }

        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }

    if ($repoProcesses.Count -gt 0) {
        Start-Sleep -Milliseconds 500
    }

    if (Test-Path -LiteralPath $pidPath) {
        Remove-Item -LiteralPath $pidPath -Force
    }
}

function Ensure-ApiBinary {
    if (Test-Path -LiteralPath $apiDllPath) {
        return
    }

    dotnet build apps\api\K12QuestionGraph.Api.csproj -c $Configuration | Write-Host
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet build failed while preparing local API binary"
    }
}

function Resolve-ConnectionString {
    $resolvedConnectionString = Resolve-KqgConnectionString -ConnectionString $null
    if (-not [string]::IsNullOrWhiteSpace($resolvedConnectionString)) {
        return $resolvedConnectionString
    }

    $resolvedPassword = Resolve-KqgDatabasePassword -DatabasePassword $DatabasePassword
    if ([string]::IsNullOrWhiteSpace($resolvedPassword)) {
        throw 'KQG_CONNECTION_STRING or PGPASSWORD/DatabasePassword is required to start the local API.'
    }

    return "Host=$DatabaseHost;Port=$DatabasePort;Database=$DatabaseName;Username=$DatabaseUser;Password=$resolvedPassword"
}

function Redact-ConnectionString([string] $ConnectionString) {
    if ([string]::IsNullOrWhiteSpace($ConnectionString)) {
        return ''
    }

    return ($ConnectionString -replace 'Password=[^;]+', 'Password=<redacted>')
}

New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

$url = "http://${HostName}:${Port}"
$listener = Get-ListenerProcess -LocalPort $Port

if ($Stop -or $Restart) {
    Stop-ApiServer
    $listener = $null
}

if ($Stop) {
    [pscustomobject]@{
        status = 'stopped'
        url = $url
        pidPath = $pidPath
    } | ConvertTo-Json -Depth 4
    exit 0
}

if ($Status) {
    $resolvedPreview = ''
    try {
        $resolvedPreview = Redact-ConnectionString (Resolve-ConnectionString)
    }
    catch {
        $resolvedPreview = ''
    }

    [pscustomobject]@{
        status = if ($null -ne $listener) { 'running' } else { 'stopped' }
        url = $url
        listenerPid = if ($null -ne $listener) { $listener.Id } else { $null }
        listenerProcess = if ($null -ne $listener) { $listener.ProcessName } else { $null }
        ready = Test-ApiReady -Url $url
        connectionStringPreview = $resolvedPreview
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
        ready = Test-ApiReady -Url $url
        pidPath = $pidPath
        stdoutLog = $stdoutPath
        stderrLog = $stderrPath
    } | ConvertTo-Json -Depth 4
    exit 0
}

$resolvedConnectionString = Resolve-ConnectionString
$previousConnectionString = $env:KQG_CONNECTION_STRING
$previousEnvironment = $env:ASPNETCORE_ENVIRONMENT

try {
    Ensure-ApiBinary
    $env:KQG_CONNECTION_STRING = $resolvedConnectionString
    $env:ASPNETCORE_ENVIRONMENT = $Environment

    Set-Content -LiteralPath $stdoutPath -Value ''
    Set-Content -LiteralPath $stderrPath -Value ''

    $process = Start-Process `
        -FilePath 'dotnet' `
        -ArgumentList @(
            $apiDllPath,
            '--urls',
            $url,
            '--contentRoot',
            $apiContentRoot
        ) `
        -WorkingDirectory $repoRoot `
        -PassThru `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath

    Set-Content -LiteralPath $pidPath -Value ([string] $process.Id)

    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 500
        $ready = Test-ApiReady -Url $url
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
        connectionStringPreview = Redact-ConnectionString $resolvedConnectionString
        pidPath = $pidPath
        stdoutLog = $stdoutPath
        stderrLog = $stderrPath
    } | ConvertTo-Json -Depth 4
}
finally {
    $env:KQG_CONNECTION_STRING = $previousConnectionString
    $env:ASPNETCORE_ENVIRONMENT = $previousEnvironment
}

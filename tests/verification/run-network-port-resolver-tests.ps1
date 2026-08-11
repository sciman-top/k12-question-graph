$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$resolverPath = Join-Path $repoRoot 'tools\network-port.ps1'

if (-not (Test-Path -LiteralPath $resolverPath -PathType Leaf)) {
    throw 'dynamic port resolver is missing'
}

. $resolverPath

$port = Get-KqgFreeTcpPort
if ($port -lt 1 -or $port -gt 65535) {
    throw "dynamic port resolver returned an invalid port: $port"
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
try {
    $listener.Start()
}
finally {
    $listener.Stop()
}

[ordered]@{
    status = 'pass'
    taskId = 'NETWORK_PORT_RESOLVER_TESTS'
    resolvedPort = $port
    bindableAfterResolution = $true
} | ConvertTo-Json

param(
    [switch] $NoBrowser,
    [switch] $NoClipboard
)

# One-stop local dev entry: API + Web + open the login page with the admin
# key on the clipboard, so the only manual step is pasting the key.
# Reuses start-local-api/start-local-web, which are no-ops when already running.

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$loginUrl = 'http://127.0.0.1:5173/'

. (Join-Path $PSScriptRoot 'dotenv.ps1')
Import-KqgDotEnv -RepoRoot $repoRoot

function Get-StartScriptStatus {
    param(
        [string] $ScriptPath
    )

    $lines = @(& $ScriptPath | ForEach-Object { [string] $_ })
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i].TrimStart().StartsWith('{')) {
            return (($lines[$i..($lines.Count - 1)] -join "`n") | ConvertFrom-Json)
        }
    }

    throw "Start script produced no JSON status: $ScriptPath"
}

$apiStatus = Get-StartScriptStatus -ScriptPath (Join-Path $PSScriptRoot 'start-local-api.ps1')
$webStatus = Get-StartScriptStatus -ScriptPath (Join-Path $PSScriptRoot 'start-local-web.ps1')

$keyInClipboard = $false
$clipboardError = $null
if (-not $NoClipboard) {
    $adminKey = [string] $env:KQG_ADMIN_INTERNAL_KEY
    if (-not [string]::IsNullOrWhiteSpace($adminKey)) {
        try {
            Set-Clipboard -Value $adminKey
            $keyInClipboard = $true
        }
        catch {
            $clipboardError = $_.Exception.Message
        }
    }
}

$browserOpened = $false
$browserError = $null
if (-not $NoBrowser) {
    try {
        Start-Process $loginUrl
        $browserOpened = $true
    }
    catch {
        $browserError = $_.Exception.Message
    }
}

[pscustomobject]@{
    status = if ($apiStatus.ready -and $webStatus.ready) { 'ready' } else { 'degraded' }
    loginUrl = $loginUrl
    api = $apiStatus
    web = $webStatus
    keyInClipboard = $keyInClipboard
    clipboardError = $clipboardError
    browserOpened = $browserOpened
    browserError = $browserError
} | ConvertTo-Json -Depth 5

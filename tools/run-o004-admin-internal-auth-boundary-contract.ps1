$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
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

function Wait-HttpReady([string] $Url, [System.Diagnostics.Process] $Process, [string] $LogErr) {
    for ($i = 0; $i -lt 30; $i++) {
        if ($Process.HasExited) {
            throw "API exited before O004 auth boundary check on $Url; see $LogErr"
        }

        try {
            $response = Invoke-WebRequest -Uri $Url -TimeoutSec 2 -SkipHttpErrorCheck
            if ($response.StatusCode -eq 200) {
                return
            }
        }
        catch {
            Start-Sleep -Seconds 1
        }
    }

    throw "API did not become available for O004 auth boundary check on $Url"
}

function Invoke-ApiForStatus([string] $Uri, [string] $Method = 'GET', [hashtable] $Headers = @{}) {
    $request = @{
        Uri = $Uri
        Method = $Method
        TimeoutSec = 5
        SkipHttpErrorCheck = $true
    }
    if ($Headers.Count -gt 0) {
        $request.Headers = $Headers
    }

    return Invoke-WebRequest @request
}

Push-Location $repoRoot
try {
    $program = Get-Content -LiteralPath 'apps\api\Program.cs' -Raw
    foreach ($pattern in @(
        'UseAdminInternalEndpointGuard',
        'StartsWithSegments("/api/admin"',
        'StartsWithSegments("/internal/ai"',
        'X-KQG-Admin-Key',
        'admin_internal_guard_not_configured',
        'CryptographicOperations.FixedTimeEquals'
    )) {
        Assert-Condition ($program.Contains($pattern)) "missing O004 API guard marker: $pattern"
    }

    $appsettings = Get-Content -LiteralPath 'apps\api\appsettings.json' -Raw | ConvertFrom-Json
    Assert-Condition ($appsettings.AdminInternalGuard.AllowUnguardedDraftTest -eq $false) "default appsettings must not allow unguarded admin/internal endpoints"

    $development = Get-Content -LiteralPath 'apps\api\appsettings.Development.json' -Raw | ConvertFrom-Json
    Assert-Condition ($development.AdminInternalGuard.AllowUnguardedDraftTest -eq $true) "development appsettings must explicitly mark draft/test unguarded boundary"

    $backlog = Import-Csv -LiteralPath 'tasks\backlog.csv' -Encoding UTF8
    $o004 = $backlog | Where-Object { $_.id -eq 'O004' } | Select-Object -First 1
    Assert-Condition ($null -ne $o004) "missing O004 backlog task"
    foreach ($pattern in @('/api/admin/*', '/internal/ai/*', 'authentication', 'authorization', '试点', 'live')) {
        Assert-Condition ($o004.acceptance -match [regex]::Escape($pattern)) "O004 acceptance missing auth boundary: $pattern"
    }

    $port = Get-FreeTcpPort
    $apiUrl = "http://127.0.0.1:$port"
    $logOut = Join-Path $repoRoot 'docs\evidence\o004-auth-boundary-api.out.log'
    $logErr = Join-Path $repoRoot 'docs\evidence\o004-auth-boundary-api.err.log'

    $previousEnvironment = $env:ASPNETCORE_ENVIRONMENT
    $previousGuardKey = $env:AdminInternalGuard__ApiKey
    $previousBypass = $env:AdminInternalGuard__AllowUnguardedDraftTest
    $env:ASPNETCORE_ENVIRONMENT = 'Production'
    $env:AdminInternalGuard__ApiKey = 'o004-contract-secret'
    $env:AdminInternalGuard__AllowUnguardedDraftTest = 'false'

    $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\api\K12QuestionGraph.Api.csproj','--urls',$apiUrl,'--no-launch-profile') -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr
    try {
        Wait-HttpReady -Url "$apiUrl/health" -Process $process -LogErr $logErr

        $adminWithoutKey = Invoke-ApiForStatus -Uri "$apiUrl/api/admin/storage/summary"
        Assert-Condition ($adminWithoutKey.StatusCode -eq 401) "admin endpoint without key should return 401"

        $internalWrongKey = Invoke-ApiForStatus -Uri "$apiUrl/internal/ai/providers" -Headers @{ 'X-KQG-Admin-Key' = 'wrong' }
        Assert-Condition ($internalWrongKey.StatusCode -eq 403) "internal AI endpoint with wrong key should return 403"

        $internalWithKey = Invoke-ApiForStatus -Uri "$apiUrl/internal/ai/providers" -Headers @{
            'X-KQG-Admin-Key' = 'o004-contract-secret'
            'X-KQG-Operator-Role' = 'admin'
            'X-KQG-Operator-Id' = 'o004-contract'
        }
        Assert-Condition ($internalWithKey.StatusCode -eq 200) "internal AI endpoint with configured key should pass"
    }
    finally {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $env:ASPNETCORE_ENVIRONMENT = $previousEnvironment
        $env:AdminInternalGuard__ApiKey = $previousGuardKey
        $env:AdminInternalGuard__AllowUnguardedDraftTest = $previousBypass
    }

    [ordered]@{
        status = 'pass'
        task = 'O004'
        contract = 'admin-internal-auth-boundary'
        guardedPrefixes = @('/api/admin/*', '/internal/ai/*')
        requiredHeader = 'X-KQG-Admin-Key'
        productionWithoutKey = 'blocked'
        developmentDraftTestBypassRequiresExplicitConfig = $true
        pilotLiveNakedEndpointsBlocked = $true
    } | ConvertTo-Json -Depth 4
}
finally {
    Pop-Location
}

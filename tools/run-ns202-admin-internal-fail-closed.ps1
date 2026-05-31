param(
    [string] $ReportPath = 'docs/evidence/20260529-ns202-admin-internal-fail-closed-report.json'
)

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
            throw "API exited before NS202 fail-closed check on $Url; see $LogErr"
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

    throw "API did not become available for NS202 fail-closed check on $Url"
}

function Invoke-ApiForStatus([string] $Uri, [string] $Method = 'GET', [hashtable] $Headers = @{}, [string] $Body = '') {
    $request = @{
        Uri = $Uri
        Method = $Method
        TimeoutSec = 45
        SkipHttpErrorCheck = $true
    }
    if ($Headers.Count -gt 0) {
        $request.Headers = $Headers
    }
    if ($Method -ne 'GET' -and $Method -ne 'HEAD') {
        $request.ContentType = 'application/json'
        $request.Body = $Body
    }

    $maxAttempts = 3
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            return Invoke-WebRequest @request
        }
        catch {
            $message = $_.Exception.Message
            $isTransientTimeout = $message -match 'Timeout|timed out|canceled'
            if ($attempt -lt $maxAttempts -and $isTransientTimeout) {
                Start-Sleep -Seconds 2
                continue
            }

            throw
        }
    }
}

function Invoke-WithApi(
    [string] $Environment,
    [string] $ApiKey,
    [string] $AllowUnguardedDraftTest,
    [scriptblock] $Probe
) {
    $port = Get-FreeTcpPort
    $apiUrl = "http://127.0.0.1:$port"
    $safeEnvironment = $Environment.ToLowerInvariant()
    $logOut = Join-Path $repoRoot "docs/evidence/ns202-$safeEnvironment-api.out.log"
    $logErr = Join-Path $repoRoot "docs/evidence/ns202-$safeEnvironment-api.err.log"
    $logsRoot = Join-Path $repoRoot "tmp/ns202/$safeEnvironment/logs"
    New-Item -ItemType Directory -Path $logsRoot -Force | Out-Null

    $previousEnvironment = $env:ASPNETCORE_ENVIRONMENT
    $previousGuardKey = $env:AdminInternalGuard__ApiKey
    $previousBypass = $env:AdminInternalGuard__AllowUnguardedDraftTest
    $previousLogsRoot = $env:KqgPaths__LogsRoot
    $previousAuditEnabled = $env:AdminInternalRoleAudit__Enabled
    $previousRequireRole = $env:AdminInternalRoleAudit__RequireRoleHeader
    $previousRequireOperator = $env:AdminInternalRoleAudit__RequireOperatorIdHeader
    $previousEnableAudit = $env:AdminInternalRoleAudit__EnableAuditLog

    $env:ASPNETCORE_ENVIRONMENT = $Environment
    $env:AdminInternalGuard__ApiKey = $ApiKey
    $env:AdminInternalGuard__AllowUnguardedDraftTest = $AllowUnguardedDraftTest
    $env:KqgPaths__LogsRoot = $logsRoot
    $env:AdminInternalRoleAudit__Enabled = 'true'
    $env:AdminInternalRoleAudit__RequireRoleHeader = 'true'
    $env:AdminInternalRoleAudit__RequireOperatorIdHeader = 'true'
    $env:AdminInternalRoleAudit__EnableAuditLog = 'true'

    $process = Start-Process -FilePath dotnet -ArgumentList @(
        'run',
        '--project',
        'apps\api\K12QuestionGraph.Api.csproj',
        '-c',
        'Release',
        '--no-build',
        '--urls',
        $apiUrl,
        '--no-launch-profile'
    ) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr

    try {
        Wait-HttpReady -Url "$apiUrl/health" -Process $process -LogErr $logErr
        return & $Probe $apiUrl
    }
    finally {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $env:ASPNETCORE_ENVIRONMENT = $previousEnvironment
        $env:AdminInternalGuard__ApiKey = $previousGuardKey
        $env:AdminInternalGuard__AllowUnguardedDraftTest = $previousBypass
        $env:KqgPaths__LogsRoot = $previousLogsRoot
        $env:AdminInternalRoleAudit__Enabled = $previousAuditEnabled
        $env:AdminInternalRoleAudit__RequireRoleHeader = $previousRequireRole
        $env:AdminInternalRoleAudit__RequireOperatorIdHeader = $previousRequireOperator
        $env:AdminInternalRoleAudit__EnableAuditLog = $previousEnableAudit
    }
}

Push-Location $repoRoot
try {
    $program = Get-Content -LiteralPath 'apps/api/Program.cs' -Raw
    $appsettings = Get-Content -LiteralPath 'apps/api/appsettings.json' -Raw | ConvertFrom-Json
    $development = Get-Content -LiteralPath 'apps/api/appsettings.Development.json' -Raw | ConvertFrom-Json

    foreach ($marker in @(
        'admin_internal_guard_not_configured',
        'missing_admin_internal_key',
        'invalid_admin_internal_key',
        'missing_operator_role',
        'missing_operator_id',
        'role_not_authorized',
        'draft-test-unguarded-admin-internal',
        'CryptographicOperations.FixedTimeEquals'
    )) {
        Assert-Condition ($program.Contains($marker)) "NS202 marker missing from Program.cs: $marker"
    }

    Assert-Condition ([string]$appsettings.AdminInternalGuard.ApiKey -eq '') 'production default API key must be blank'
    Assert-Condition ($appsettings.AdminInternalGuard.AllowUnguardedDraftTest -eq $false) 'production default must not allow unguarded draft/test'
    Assert-Condition ($development.AdminInternalGuard.AllowUnguardedDraftTest -eq $true) 'development bypass must be explicit'

    $productionUnconfigured = Invoke-WithApi -Environment 'Production' -ApiKey '' -AllowUnguardedDraftTest 'false' -Probe {
        param([string] $apiUrl)
        $admin = Invoke-ApiForStatus -Uri "$apiUrl/api/admin/storage/summary"
        $internal = Invoke-ApiForStatus -Uri "$apiUrl/internal/ai/providers"
        [ordered]@{
            adminStorageStatus = [int]$admin.StatusCode
            internalAiStatus = [int]$internal.StatusCode
            adminError = (($admin.Content | ConvertFrom-Json).error)
            internalError = (($internal.Content | ConvertFrom-Json).error)
        }
    }
    Assert-Condition ($productionUnconfigured.adminStorageStatus -eq 503) 'unconfigured production admin endpoint must fail closed with 503'
    Assert-Condition ($productionUnconfigured.internalAiStatus -eq 503) 'unconfigured production internal AI endpoint must fail closed with 503'

    $productionConfigured = Invoke-WithApi -Environment 'Production' -ApiKey 'ns202-contract-secret' -AllowUnguardedDraftTest 'false' -Probe {
        param([string] $apiUrl)
        $missingKey = Invoke-ApiForStatus -Uri "$apiUrl/api/admin/storage/summary"
        $wrongKey = Invoke-ApiForStatus -Uri "$apiUrl/internal/ai/providers" -Headers @{ 'X-KQG-Admin-Key' = 'wrong' }
        $missingRole = Invoke-ApiForStatus -Uri "$apiUrl/internal/ai/providers" -Headers @{
            'X-KQG-Admin-Key' = 'ns202-contract-secret'
            'X-KQG-Operator-Id' = 'operator-001'
        }
        $missingOperator = Invoke-ApiForStatus -Uri "$apiUrl/internal/ai/providers" -Headers @{
            'X-KQG-Admin-Key' = 'ns202-contract-secret'
            'X-KQG-Operator-Role' = 'admin'
        }
        $teacherAdmin = Invoke-ApiForStatus -Uri "$apiUrl/api/admin/storage/summary" -Headers @{
            'X-KQG-Admin-Key' = 'ns202-contract-secret'
            'X-KQG-Operator-Role' = 'teacher'
            'X-KQG-Operator-Id' = 'teacher-001'
        }
        $adminInternal = Invoke-ApiForStatus -Uri "$apiUrl/internal/ai/providers" -Headers @{
            'X-KQG-Admin-Key' = 'ns202-contract-secret'
            'X-KQG-Operator-Role' = 'admin'
            'X-KQG-Operator-Id' = 'admin-001'
        }

        [ordered]@{
            missingKey = [int]$missingKey.StatusCode
            wrongKey = [int]$wrongKey.StatusCode
            missingRole = [int]$missingRole.StatusCode
            missingOperator = [int]$missingOperator.StatusCode
            teacherAdmin = [int]$teacherAdmin.StatusCode
            adminInternal = [int]$adminInternal.StatusCode
        }
    }
    Assert-Condition ($productionConfigured.missingKey -eq 401) 'configured production admin endpoint must reject missing key'
    Assert-Condition ($productionConfigured.wrongKey -eq 403) 'configured production internal endpoint must reject wrong key'
    Assert-Condition ($productionConfigured.missingRole -eq 401) 'configured production endpoint must reject missing role'
    Assert-Condition ($productionConfigured.missingOperator -eq 401) 'configured production endpoint must reject missing operator id'
    Assert-Condition ($productionConfigured.teacherAdmin -eq 403) 'teacher role must remain blocked from admin endpoint'
    Assert-Condition ($productionConfigured.adminInternal -eq 200) 'admin with full headers must pass internal AI endpoint'

    $developmentBypass = Invoke-WithApi -Environment 'Development' -ApiKey '' -AllowUnguardedDraftTest 'true' -Probe {
        param([string] $apiUrl)
        $admin = Invoke-ApiForStatus -Uri "$apiUrl/api/admin/storage/summary"
        $headerValue = $admin.Headers['X-KQG-Auth-Boundary'] | Select-Object -First 1
        [ordered]@{
            adminStorageStatus = [int]$admin.StatusCode
            draftTestHeader = [string]$headerValue
        }
    }
    Assert-Condition ($developmentBypass.adminStorageStatus -eq 200) 'development bypass must be explicitly usable for draft/test only'
    Assert-Condition ($developmentBypass.draftTestHeader -eq 'draft-test-unguarded-admin-internal') 'development bypass must expose boundary response header'

    $o004 = & pwsh -NoProfile -ExecutionPolicy Bypass -File 'tools/run-o004-admin-internal-auth-boundary-contract.ps1' | Out-String | ConvertFrom-Json
    Assert-Condition ($o004.status -eq 'pass') 'O004 dependency must pass for NS202'
    $o004b = & pwsh -NoProfile -ExecutionPolicy Bypass -File 'tools/run-o004b-role-audit-closure-contract.ps1' | Out-String | ConvertFrom-Json
    Assert-Condition ($o004b.status -eq 'pass') 'O004B dependency must pass for NS202'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS202'
        checkedAt = (Get-Date).ToString('s')
        mode = 'production_fail_closed_and_explicit_development_bypass_smoke'
        productionEligible = $false
        productionUnconfigured = $productionUnconfigured
        productionConfigured = $productionConfigured
        developmentBypass = $developmentBypass
        dependencies = [ordered]@{
            o004 = [ordered]@{
                status = $o004.status
                productionWithoutKey = $o004.productionWithoutKey
                guardedPrefixes = $o004.guardedPrefixes
            }
            o004b = [ordered]@{
                status = $o004b.status
                roleSplit = $o004b.roleSplit
                highRiskWriteRecorded = $o004b.auditLog.highRiskWriteRecorded
            }
        }
        acceptance = [ordered]@{
            productionWithoutConfiguredKeyFailsClosed = $true
            productionMissingKeyRejected = $true
            productionWrongKeyRejected = $true
            missingRoleOrOperatorRejected = $true
            unauthorizedTeacherRejected = $true
            explicitDevelopmentBypassMarked = $true
        }
        boundary = 'NS202 proves admin/internal fail closed for production defaults and credentials. Development unguarded access remains explicit, marked, and draft/test only.'
        next = 'NS203 can continue PII/source-license scanning without enabling live data or production writes.'
        rollback = 'git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns202-admin-internal-fail-closed.ps1 docs/evidence/20260529-ns202-admin-internal-fail-closed-report.json'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 6
}
finally {
    Pop-Location
}

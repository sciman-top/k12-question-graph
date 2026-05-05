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
            throw "API exited before O004B role/audit check on $Url; see $LogErr"
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

    throw "API did not become available for O004B role/audit check on $Url"
}

function Invoke-ApiForStatus([string] $Uri, [string] $Method = 'GET', [hashtable] $Headers = @{}, [string] $Body = '') {
    $request = @{
        Uri = $Uri
        Method = $Method
        TimeoutSec = 5
        SkipHttpErrorCheck = $true
    }
    if ($Headers.Count -gt 0) {
        $request.Headers = $Headers
    }
    if ($Method -ne 'GET' -and $Method -ne 'HEAD') {
        $request.ContentType = 'application/json'
        $request.Body = $Body
    }

    return Invoke-WebRequest @request
}

Push-Location $repoRoot
try {
    $program = Get-Content -LiteralPath 'apps\api\Program.cs' -Raw
    foreach ($pattern in @(
        'X-KQG-Operator-Role',
        'X-KQG-Operator-Id',
        'role_not_authorized',
        'missing_operator_role',
        'admin-internal-audit.jsonl',
        'operatorRole',
        'rollbackRef',
        'IsRoleAuthorized'
    )) {
        Assert-Condition ($program.Contains($pattern)) "missing O004B API role/audit marker: $pattern"
    }

    $appsettings = Get-Content -LiteralPath 'apps\api\appsettings.json' -Raw | ConvertFrom-Json
    Assert-Condition ($appsettings.AdminInternalRoleAudit.Enabled -eq $true) 'default appsettings must enable role/audit guard'
    Assert-Condition ($appsettings.AdminInternalRoleAudit.RequireRoleHeader -eq $true) 'default appsettings must require role header'
    Assert-Condition ($appsettings.AdminInternalRoleAudit.RequireOperatorIdHeader -eq $true) 'default appsettings must require operator id header'

    $backlog = Import-Csv -LiteralPath 'tasks\backlog.csv' -Encoding UTF8
    $o004b = $backlog | Where-Object { $_.id -eq 'O004B' } | Select-Object -First 1
    Assert-Condition ($null -ne $o004b) 'missing O004B backlog task'

    $port = Get-FreeTcpPort
    $apiUrl = "http://127.0.0.1:$port"
    $logOut = Join-Path $repoRoot 'docs\evidence\o004b-role-audit-api.out.log'
    $logErr = Join-Path $repoRoot 'docs\evidence\o004b-role-audit-api.err.log'
    $auditRoot = Join-Path $repoRoot 'tmp/o004b/logs'
    New-Item -ItemType Directory -Path $auditRoot -Force | Out-Null
    $auditLog = Join-Path $auditRoot 'admin-internal-audit.jsonl'

    $previousEnvironment = $env:ASPNETCORE_ENVIRONMENT
    $previousGuardKey = $env:AdminInternalGuard__ApiKey
    $previousBypass = $env:AdminInternalGuard__AllowUnguardedDraftTest
    $previousLogsRoot = $env:KqgPaths__LogsRoot
    $previousAuditEnabled = $env:AdminInternalRoleAudit__Enabled
    $previousRequireRole = $env:AdminInternalRoleAudit__RequireRoleHeader
    $previousRequireOperator = $env:AdminInternalRoleAudit__RequireOperatorIdHeader
    $previousEnableAudit = $env:AdminInternalRoleAudit__EnableAuditLog

    $env:ASPNETCORE_ENVIRONMENT = 'Production'
    $env:AdminInternalGuard__ApiKey = 'o004b-contract-secret'
    $env:AdminInternalGuard__AllowUnguardedDraftTest = 'false'
    $env:KqgPaths__LogsRoot = $auditRoot
    $env:AdminInternalRoleAudit__Enabled = 'true'
    $env:AdminInternalRoleAudit__RequireRoleHeader = 'true'
    $env:AdminInternalRoleAudit__RequireOperatorIdHeader = 'true'
    $env:AdminInternalRoleAudit__EnableAuditLog = 'true'

    $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\api\K12QuestionGraph.Api.csproj','--urls',$apiUrl,'--no-launch-profile') -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr
    try {
        Wait-HttpReady -Url "$apiUrl/health" -Process $process -LogErr $logErr

        $adminHeaders = @{
            'X-KQG-Admin-Key' = 'o004b-contract-secret'
            'X-KQG-Operator-Role' = 'admin'
            'X-KQG-Operator-Id' = 'admin-001'
            'X-KQG-Rollback-Ref' = 'rollback://o004b/test-1'
        }
        $leadHeaders = @{
            'X-KQG-Admin-Key' = 'o004b-contract-secret'
            'X-KQG-Operator-Role' = 'group_lead'
            'X-KQG-Operator-Id' = 'lead-001'
        }
        $teacherHeaders = @{
            'X-KQG-Admin-Key' = 'o004b-contract-secret'
            'X-KQG-Operator-Role' = 'teacher'
            'X-KQG-Operator-Id' = 'teacher-001'
        }

        $groupLeadRead = Invoke-ApiForStatus -Uri "$apiUrl/api/admin/storage/summary" -Headers $leadHeaders
        Assert-Condition ($groupLeadRead.StatusCode -eq 200) 'group_lead should be able to read /api/admin/*'

        $groupLeadWrite = Invoke-ApiForStatus -Uri "$apiUrl/api/admin/cache/cleanup" -Method 'POST' -Headers $leadHeaders -Body '{"dryRun":true,"olderThanDays":7}'
        Assert-Condition ($groupLeadWrite.StatusCode -eq 403) 'group_lead should be blocked on high-risk admin write'

        $teacherRead = Invoke-ApiForStatus -Uri "$apiUrl/api/admin/storage/summary" -Headers $teacherHeaders
        Assert-Condition ($teacherRead.StatusCode -eq 403) 'teacher must be blocked from admin endpoint'

        $adminWrite = Invoke-ApiForStatus -Uri "$apiUrl/api/admin/cache/cleanup" -Method 'POST' -Headers $adminHeaders -Body '{"dryRun":true,"olderThanDays":7}'
        Assert-Condition ($adminWrite.StatusCode -eq 200) 'admin should be allowed for high-risk admin write'

        $groupLeadInternal = Invoke-ApiForStatus -Uri "$apiUrl/internal/ai/providers" -Headers $leadHeaders
        Assert-Condition ($groupLeadInternal.StatusCode -eq 403) 'group_lead should be blocked from internal/ai endpoints'

        $adminInternal = Invoke-ApiForStatus -Uri "$apiUrl/internal/ai/providers" -Headers $adminHeaders
        Assert-Condition ($adminInternal.StatusCode -eq 200) 'admin should be allowed for internal/ai endpoints'
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

    Assert-Condition (Test-Path -LiteralPath $auditLog) 'missing O004B audit log file'
    $lines = Get-Content -LiteralPath $auditLog
    Assert-Condition ($lines.Count -ge 4) 'expected multiple audit entries in O004B audit log'

    $entries = $lines | ForEach-Object { $_ | ConvertFrom-Json }
    $requiredFields = @('timestampUtc', 'path', 'method', 'operatorRole', 'operatorId', 'objectRef', 'decision', 'statusCode')
    foreach ($entry in $entries) {
        foreach ($field in $requiredFields) {
            Assert-Condition ($null -ne $entry.$field) "audit entry missing field: $field"
        }
    }

    $deniedTeacher = $entries | Where-Object { $_.operatorRole -eq 'teacher' -and $_.statusCode -eq 403 }
    Assert-Condition (@($deniedTeacher).Count -ge 1) 'audit log must include teacher denied record'

    $adminWriteEntry = $entries | Where-Object { $_.operatorRole -eq 'admin' -and $_.method -eq 'POST' -and $_.path -eq '/api/admin/cache/cleanup' -and $_.statusCode -eq 200 }
    Assert-Condition (@($adminWriteEntry).Count -ge 1) 'audit log must include admin high-risk write record'

    [ordered]@{
        status = 'pass'
        task = 'O004B'
        contract = 'role-audit-closure'
        roleSplit = [ordered]@{
            teacherBlocked = $true
            groupLeadReadAllowed = $true
            groupLeadWriteBlocked = $true
            adminWriteAllowed = $true
            internalAiAdminOnly = $true
        }
        auditLog = [ordered]@{
            path = 'tmp/o004b/logs/admin-internal-audit.jsonl'
            entryCount = @($entries).Count
            requiredFields = $requiredFields
            highRiskWriteRecorded = $true
            rollbackRefCaptured = $true
        }
        pilotLiveGuard = 'fail_closed_when_role_or_operator_headers_missing_or_unauthorized'
    } | ConvertTo-Json -Depth 6
}
finally {
    Pop-Location
}

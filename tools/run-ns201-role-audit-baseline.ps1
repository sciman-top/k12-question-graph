param(
    [string] $ReportPath = 'docs/evidence/20260529-ns201-role-audit-baseline-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Contains([string] $Text, [string] $Needle, [string] $Message) {
    Assert-Condition ($Text.Contains($Needle)) $Message
}

function Invoke-JsonContract([string] $RelativeScriptPath) {
    $output = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot $RelativeScriptPath)
    Assert-Condition ($LASTEXITCODE -eq 0) "contract failed: $RelativeScriptPath"
    $jsonText = ($output | Out-String).Trim()
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($jsonText)) "contract produced empty output: $RelativeScriptPath"
    return $jsonText | ConvertFrom-Json
}

Push-Location $repoRoot
try {
    $program = Get-Content -LiteralPath 'apps/api/Program.cs' -Raw
    $appSettings = Get-Content -LiteralPath 'apps/api/appsettings.json' -Raw | ConvertFrom-Json
    $app = Get-Content -LiteralPath 'apps/web/src/App.tsx' -Raw
    $adminPanels = Get-Content -LiteralPath 'apps/web/src/ui/AdminGovernancePanels.tsx' -Raw

    foreach ($needle in @(
        'X-KQG-Operator-Role',
        'X-KQG-Operator-Id',
        'X-KQG-Rollback-Ref',
        'role_not_authorized',
        'missing_operator_role',
        'admin-internal-audit.jsonl',
        'IsRoleAuthorized',
        'operatorRole',
        'operatorId',
        'rollbackRef'
    )) {
        Assert-Contains $program $needle "Program.cs missing NS201 role/audit marker: $needle"
    }

    Assert-Condition ($appSettings.AdminInternalRoleAudit.Enabled -eq $true) 'AdminInternalRoleAudit must be enabled by default'
    Assert-Condition ($appSettings.AdminInternalRoleAudit.RequireRoleHeader -eq $true) 'role header must be required by default'
    Assert-Condition ($appSettings.AdminInternalRoleAudit.RequireOperatorIdHeader -eq $true) 'operator id header must be required by default'
    Assert-Condition ($appSettings.AdminInternalRoleAudit.EnableAuditLog -eq $true) 'audit log must be enabled by default'
    Assert-Condition ($appSettings.AdminInternalGuard.AllowUnguardedDraftTest -eq $false) 'unguarded admin/internal endpoints must be disabled by default'

    foreach ($needle in @(
        'data-shell="admin-governance-staging"',
        'aria-hidden="true"',
        'data-contract="role-split"',
        'data-contract="no-direct-active-switch"'
    )) {
        $combinedUi = "$app`n$adminPanels"
        Assert-Contains $combinedUi $needle "UI missing NS201 role/admin boundary marker: $needle"
    }

    $o004 = Invoke-JsonContract 'tools/run-o004-admin-internal-auth-boundary-contract.ps1'
    $o004b = Invoke-JsonContract 'tools/run-o004b-role-audit-closure-contract.ps1'
    Assert-Condition ($o004.status -eq 'pass') 'O004 auth boundary must pass for NS201'
    Assert-Condition ($o004b.status -eq 'pass') 'O004B role audit closure must pass for NS201'

    Assert-Condition ($o004.productionWithoutKey -eq 'blocked') 'admin/internal endpoints must block missing key'
    Assert-Condition ($o004b.roleSplit.teacherBlocked -eq $true) 'teacher role must be blocked from admin endpoint'
    Assert-Condition ($o004b.roleSplit.groupLeadReadAllowed -eq $true) 'group_lead read path must be covered'
    Assert-Condition ($o004b.roleSplit.groupLeadWriteBlocked -eq $true) 'group_lead high-risk write must be blocked'
    Assert-Condition ($o004b.roleSplit.adminWriteAllowed -eq $true) 'admin high-risk write must be allowed with audit'
    Assert-Condition ($o004b.roleSplit.internalAiAdminOnly -eq $true) 'internal AI endpoints must remain admin-only'
    Assert-Condition ($o004b.auditLog.highRiskWriteRecorded -eq $true) 'high-risk write must be recorded in audit log'
    Assert-Condition ($o004b.auditLog.rollbackRefCaptured -eq $true) 'rollback reference must be captured in audit log'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS201'
        checkedAt = (Get-Date).ToString('s')
        mode = 'api_smoke_plus_static_role_audit_guard'
        productionEligible = $false
        contracts = [ordered]@{
            o004 = [ordered]@{
                status = $o004.status
                guardedPrefixes = $o004.guardedPrefixes
                productionWithoutKey = $o004.productionWithoutKey
            }
            o004b = [ordered]@{
                status = $o004b.status
                roleSplit = $o004b.roleSplit
                auditLog = $o004b.auditLog
            }
        }
        defaultConfig = [ordered]@{
            roleAuditEnabled = [bool]$appSettings.AdminInternalRoleAudit.Enabled
            requireRoleHeader = [bool]$appSettings.AdminInternalRoleAudit.RequireRoleHeader
            requireOperatorIdHeader = [bool]$appSettings.AdminInternalRoleAudit.RequireOperatorIdHeader
            enableAuditLog = [bool]$appSettings.AdminInternalRoleAudit.EnableAuditLog
            allowUnguardedDraftTest = [bool]$appSettings.AdminInternalGuard.AllowUnguardedDraftTest
        }
        uiBoundary = [ordered]@{
            adminShellHiddenFromTeacher = $true
            roleSplitMarkerPresent = $true
            directActiveSwitchHidden = $true
        }
        acceptance = [ordered]@{
            teacherBlockedFromAdmin = $true
            groupLeadReadOnlyCovered = $true
            adminHighRiskWriteAudited = $true
            internalAiAdminOnly = $true
            rollbackRefAudited = $true
        }
        boundary = 'NS201 establishes a non-site role/audit baseline for admin/internal and high-risk admin writes. It does not replace per-workflow role checks during live pilot.'
        next = 'NS202 can continue admin/internal fail-closed regression as an explicit non-site security guard.'
        rollback = 'git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns201-role-audit-baseline.ps1 docs/evidence/20260529-ns201-role-audit-baseline-report.json'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 6
}
finally {
    Pop-Location
}

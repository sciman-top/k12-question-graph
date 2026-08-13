param(
    [string] $ContractPath = 'tasks/automation-first-contract.csv',
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ScopeFreezePolicyPath = 'configs/verification/scope-freeze.rules.json',
    [string] $JsonReportPath = 'tmp/verification/automation-first.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Resolve-RepoPath([string] $Path) { Join-Path $repoRoot $Path }
function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

$contractRows = @(Import-Csv -LiteralPath (Resolve-RepoPath $ContractPath) -Encoding UTF8)
$backlogRows = @(Import-Csv -LiteralPath (Resolve-RepoPath $BacklogPath) -Encoding UTF8)
$freeze = Get-Content -LiteralPath (Resolve-RepoPath $ScopeFreezePolicyPath) -Raw -Encoding UTF8 | ConvertFrom-Json

$requiredColumns = @(
    'task_id',
    'scope',
    'deterministic_precheck',
    'dedicated_surface',
    'ai_agent_allowed_scope',
    'exception_policy',
    'evidence_command'
)
Assert-True ($contractRows.Count -gt 0) 'automation-first contract must not be empty'
foreach ($column in $requiredColumns) {
    Assert-True ($contractRows[0].PSObject.Properties.Name -contains $column) "automation-first contract missing column: $column"
}

$byId = @{}
foreach ($row in $contractRows) {
    Assert-True (-not $byId.ContainsKey($row.task_id)) "duplicate automation-first task_id: $($row.task_id)"
    $byId[$row.task_id] = $row
    foreach ($column in $requiredColumns) {
        Assert-True (-not [string]::IsNullOrWhiteSpace($row.$column)) "automation-first row $($row.task_id) missing $column"
    }
    Assert-True ($row.ai_agent_allowed_scope -match 'only|N/A|no AI|candidate|draft|review|human|outer|suggestion|不') "automation-first row $($row.task_id) must limit AI scope"
    Assert-True ($row.exception_policy -match 'block|fail|N/A|human|阻断|missing|without|unclear|untriaged') "automation-first row $($row.task_id) must define a blocking exception policy"
}
Assert-True ($byId.ContainsKey('GLOBAL')) 'automation-first contract must include GLOBAL'

$activation = @($backlogRows | Where-Object id -eq $freeze.activationTaskId)
Assert-True ($activation.Count -eq 1) 'scope-freeze activation task must exist exactly once'
$freezeActive = [string]$activation[0].status -ne '已完成'
$frozenIds = @{}
foreach ($id in @($freeze.frozenTaskIds)) { $frozenIds[[string]$id] = $true }

$openRows = @($backlogRows | Where-Object {
    $_.status -ne '已完成' -and
    (-not $freezeActive -or -not $frozenIds.ContainsKey($_.id))
})
$expectedIds = @('GLOBAL') + @($openRows.id)
$missing = @($expectedIds | Where-Object { -not $byId.ContainsKey($_) })
$stale = @($contractRows.task_id | Where-Object { $expectedIds -notcontains $_ })
Assert-True ($missing.Count -eq 0) ('automation-first contract missing current open tasks: ' + ($missing -join ','))
Assert-True ($stale.Count -eq 0) ('automation-first contract contains completed or frozen tasks: ' + ($stale -join ','))

$report = [ordered]@{
    status = 'pass'
    schemaVersion = 2
    contractPath = $ContractPath
    currentOpenTaskIds = @($openRows.id)
    frozenFutureTaskIds = if ($freezeActive) { @($freeze.frozenTaskIds) } else { @() }
    contractRowCount = $contractRows.Count
    boundary = 'Only current admitted work is governed. Completed tasks and frozen future work do not retain permanent contract rows.'
}
$fullReportPath = Resolve-RepoPath $JsonReportPath
New-Item -ItemType Directory -Path (Split-Path -Parent $fullReportPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $fullReportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 5

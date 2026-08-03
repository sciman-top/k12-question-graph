param(
    [string] $PolicyPath = 'configs/verification/scope-freeze.rules.json',
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $AutomationContractPath = 'tasks/automation-first-contract.csv',
    [string] $JsonReportPath = 'tmp/verification/scope-freeze.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Resolve-RepoPath([string] $Path) { return Join-Path $repoRoot $Path }
function Assert-True([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }

$policy = Get-Content -LiteralPath (Resolve-RepoPath $PolicyPath) -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ($policy.schemaVersion -eq 1) 'unknown scope-freeze policy schema version'
$backlogRows = @(Import-Csv -LiteralPath (Resolve-RepoPath $BacklogPath) -Encoding UTF8)
$automationRows = @(Import-Csv -LiteralPath (Resolve-RepoPath $AutomationContractPath) -Encoding UTF8)
$backlogById = @{}
foreach ($row in $backlogRows) {
    Assert-True (-not $backlogById.ContainsKey($row.id)) "duplicate backlog id: $($row.id)"
    $backlogById[$row.id] = $row
}

$activationTaskId = [string]$policy.activationTaskId
Assert-True ($backlogById.ContainsKey($activationTaskId)) "scope-freeze activation task missing: $activationTaskId"
$freezeActive = [string]$backlogById[$activationTaskId].status -ne '已完成'
$frozenTaskIds = @($policy.frozenTaskIds | ForEach-Object { [string]$_ })
$frozenSet = @{}
foreach ($taskId in $frozenTaskIds) {
    Assert-True (-not $frozenSet.ContainsKey($taskId)) "duplicate frozen task id: $taskId"
    $frozenSet[$taskId] = $true
}

$frozenBacklogRows = @($backlogRows | Where-Object { $frozenSet.ContainsKey($_.id) })
Assert-True ($frozenBacklogRows.Count -eq $frozenTaskIds.Count) 'scope-freeze policy and backlog task sets differ'
$unexpectedFutureRows = @($backlogRows | Where-Object { $_.phase -in @('Q0', 'R0') -and -not $frozenSet.ContainsKey($_.id) })
$unexpectedFutureTaskIds = @($unexpectedFutureRows | ForEach-Object { [string]$_.id })
Assert-True ($unexpectedFutureRows.Count -eq 0) ('unregistered future tasks bypass scope freeze: ' + ($unexpectedFutureTaskIds -join ','))

if ($freezeActive) {
    foreach ($row in $frozenBacklogRows) {
        Assert-True ([string]$row.status -eq [string]$policy.requiredFrozenStatus) "frozen task advanced before P006: $($row.id) status=$($row.status)"
        Assert-True ([string]$row.verification -eq [string]$policy.backlogVerificationMarker) "frozen task must use the single activation marker: $($row.id)"
    }
    $prematureAutomationRows = @($automationRows | Where-Object { $frozenSet.ContainsKey($_.task_id) })
    $prematureAutomationTaskIds = @($prematureAutomationRows | ForEach-Object { [string]$_.task_id })
    Assert-True ($prematureAutomationRows.Count -eq 0) ('frozen tasks must not prebuild automation contracts: ' + ($prematureAutomationTaskIds -join ','))

    $retiredMatches = New-Object System.Collections.Generic.List[string]
    foreach ($path in @(git -C $repoRoot ls-files)) {
        if (-not (Test-Path -LiteralPath (Resolve-RepoPath $path))) { continue }
        foreach ($pattern in @($policy.retiredPathRegexes)) {
            if ([string]$path -match [string]$pattern) { $retiredMatches.Add([string]$path); break }
        }
    }
    Assert-True ($retiredMatches.Count -eq 0) ('premature future-task artifacts must stay retired until P006: ' + (($retiredMatches.ToArray()) -join ','))
}

$report = [ordered]@{
    schemaVersion = 1
    status = 'pass'
    activationTaskId = $activationTaskId
    activationTaskStatus = [string]$backlogById[$activationTaskId].status
    freezeActive = $freezeActive
    frozenTaskCount = $frozenTaskIds.Count
    frozenTaskIds = $frozenTaskIds
    decision = if ($freezeActive) { 'future task implementation and prebuilt governance artifacts are blocked' } else { 'P006 is complete; future tasks require fresh activation inputs and task-local design' }
}
$fullReportPath = Resolve-RepoPath $JsonReportPath
New-Item -ItemType Directory -Path (Split-Path -Parent $fullReportPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $fullReportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 5

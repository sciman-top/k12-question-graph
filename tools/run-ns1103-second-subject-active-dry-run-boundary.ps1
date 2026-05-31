param(
    [string] $ReportPath = 'docs/evidence/20260531-ns1103-second-subject-active-dry-run.json',
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $NonSitePlanPath = 'tasks/non-site-implementation-plan.csv',
    [string] $Q003ReportPath = 'docs/evidence/20260523-q003-second-subject-active-drill-report.json',
    [string] $Q003ChecklistPath = 'docs/templates/q003-second-subject-active-drill-checklist.md',
    [string] $Q003PreflightEvidencePath = 'docs/evidence/20260505-q003-second-subject-active-drill-preflight.md',
    [string] $NS1102ReportPath = 'docs/evidence/20260530-ns1102-second-subject-review-template.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Resolve-InRepoPath([string] $RelativePath) {
    return Join-Path $repoRoot ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
}

function Read-Json([string] $Path) {
    $fullPath = Resolve-InRepoPath $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing json report: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Get-RequiredRow([object[]] $Rows, [string] $Id, [string] $Column = 'id') {
    $matches = @($Rows | Where-Object { [string]$_.$Column -eq $Id })
    Assert-Condition ($matches.Count -eq 1) "expected exactly one $Column=$Id row"
    return $matches[0]
}

function Assert-TextContains([string] $Text, [string[]] $Needles, [string] $Label) {
    foreach ($needle in $Needles) {
        Assert-Condition ($Text.Contains($needle)) "$Label missing text: $needle"
    }
}

Push-Location $repoRoot
try {
    $backlogFullPath = Resolve-InRepoPath $BacklogPath
    $planFullPath = Resolve-InRepoPath $NonSitePlanPath
    $checklistFullPath = Resolve-InRepoPath $Q003ChecklistPath
    $preflightEvidenceFullPath = Resolve-InRepoPath $Q003PreflightEvidencePath

    Assert-Condition (Test-Path -LiteralPath $backlogFullPath) "missing backlog: $BacklogPath"
    Assert-Condition (Test-Path -LiteralPath $planFullPath) "missing non-site plan: $NonSitePlanPath"
    Assert-Condition (Test-Path -LiteralPath $checklistFullPath) "missing Q003 checklist: $Q003ChecklistPath"
    Assert-Condition (Test-Path -LiteralPath $preflightEvidenceFullPath) "missing Q003 preflight evidence: $Q003PreflightEvidencePath"

    $backlogRows = @(Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8)
    $planRows = @(Import-Csv -LiteralPath $planFullPath -Encoding UTF8)
    Assert-Condition ($backlogRows.Count -gt 0) 'backlog must not be empty'
    Assert-Condition ($planRows.Count -gt 0) 'non-site plan must not be empty'

    $ns1102Report = Read-Json $NS1102ReportPath
    Assert-Condition ($ns1102Report.status -eq 'pass') 'NS1103 requires NS1102 boundary report to pass'
    Assert-Condition (-not [bool]$ns1102Report.acceptance.q002CanClose) 'NS1102 must keep q002CanClose=false'
    Assert-Condition (-not [bool]$ns1102Report.acceptance.q003CanAdvance) 'NS1102 must keep q003CanAdvance=false before teacher review evidence closes'
    Assert-Condition (-not [bool]$ns1102Report.acceptance.teacherReviewExecuted) 'NS1102 must not execute teacher review'
    Assert-Condition (-not [bool]$ns1102Report.acceptance.activeAssetMutation) 'NS1102 must not mutate active assets'

    $q003Report = Read-Json $Q003ReportPath
    Assert-Condition ($q003Report.status -eq 'pass') 'Q003 preflight report must pass before NS1103 boundary pack'
    Assert-Condition ($q003Report.mode -eq 'preflight_only') 'Q003 report must remain preflight_only'
    Assert-Condition (-not [bool]$q003Report.closeTaskAllowed) 'Q003 closeTaskAllowed must remain false'
    Assert-Condition ($q003Report.q002Status -eq '待办') 'Q003 report must keep Q002 as todo'
    Assert-Condition ($q003Report.q003Status -eq '待办') 'Q003 report must keep Q003 as todo'

    $q002 = Get-RequiredRow $backlogRows 'Q002'
    $q003 = Get-RequiredRow $backlogRows 'Q003'
    $q004 = Get-RequiredRow $backlogRows 'Q004'
    Assert-Condition ($q002.status -eq '待办') 'Q002 backlog task must remain todo'
    Assert-Condition ($q003.status -eq '待办') 'Q003 backlog task must remain todo'
    Assert-Condition ($q004.status -eq '待办') 'Q004 backlog task must remain todo'
    Assert-Condition ($q003.depends_on -eq 'Q002') 'Q003 must continue to depend on Q002'
    Assert-Condition ($q004.depends_on -eq 'Q003') 'Q004 must continue to depend on Q003'

    $ns1102Row = Get-RequiredRow $planRows 'NS1102'
    $ns1103Row = Get-RequiredRow $planRows 'NS1103'
    $ns1104Row = Get-RequiredRow $planRows 'NS1104'
    Assert-Condition ($ns1102Row.status -eq 'runtime_verified') 'NS1103 requires NS1102 runtime_verified boundary evidence'
    Assert-Condition ($ns1103Row.depends_on -eq 'NS1102') 'NS1103 must continue to depend on NS1102'
    Assert-Condition ($ns1103Row.status -in @('planned','runtime_verified')) "NS1103 has unsupported status for boundary verification: $($ns1103Row.status)"
    Assert-Condition ($ns1104Row.depends_on -eq 'NS1103') 'NS1104 must continue to depend on NS1103'

    $checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
    Assert-TextContains $checklistText @(
        'Q002',
        'backup',
        'readiness',
        'reviewed',
        'active',
        'rollback snapshot',
        'dry-run'
    ) 'Q003 checklist'

    $preflightEvidenceText = Get-Content -LiteralPath $preflightEvidenceFullPath -Raw
    Assert-TextContains $preflightEvidenceText @(
        'preflight',
        'Q003',
        'platform_na',
        'gate_na',
        'active 演练',
        '下一步'
    ) 'Q003 preflight evidence'

    $blockers = @($q003Report.blockers | ForEach-Object { [string]$_ })
    Assert-Condition ($blockers -contains 'Q002 teacher review evidence is not closed.') 'Q003 blockers must include Q002 teacher review evidence'
    Assert-Condition ($blockers -contains 'Second-subject backup readiness, reviewed state, active switch dry-run, and rollback snapshot are not recorded.') 'Q003 blockers must include missing backup/reviewed/active/rollback evidence'
    Assert-Condition ($blockers -contains 'No active write is allowed from this preflight contract.') 'Q003 blockers must include no active write'

    $checkedAt = (Get-Date).ToString('s')
    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS1103'
        checkedAt = $checkedAt
        mode = 'second_subject_active_dry_run_boundary'
        reportPath = $ReportPath
        backlogPath = $BacklogPath
        nonSitePlanPath = $NonSitePlanPath
        sourceReports = [ordered]@{
            ns1102BoundaryReport = $NS1102ReportPath
            q003PreflightReport = $Q003ReportPath
            q003Checklist = $Q003ChecklistPath
            q003PreflightEvidence = $Q003PreflightEvidencePath
        }
        backlog = [ordered]@{
            q002Status = [string]$q002.status
            q003Status = [string]$q003.status
            q004Status = [string]$q004.status
            q003DependsOn = [string]$q003.depends_on
            q004DependsOn = [string]$q004.depends_on
            q003CanClose = $false
        }
        nonSitePlan = [ordered]@{
            ns1102Status = [string]$ns1102Row.status
            ns1103StatusAtCheck = [string]$ns1103Row.status
            ns1103DependsOn = [string]$ns1103Row.depends_on
            ns1104DependsOn = [string]$ns1104Row.depends_on
        }
        q003Preflight = [ordered]@{
            status = [string]$q003Report.status
            mode = [string]$q003Report.mode
            closeTaskAllowed = [bool]$q003Report.closeTaskAllowed
            currentDecision = [string]$q003Report.currentDecision
            blockers = $blockers
        }
        acceptance = [ordered]@{
            q002RemainsTodo = $true
            q003RemainsTodo = $true
            q004RemainsTodo = $true
            backupReadinessRecorded = $false
            reviewedStateRecorded = $false
            activeDryRunExecuted = $false
            activeSwitchPerformed = $false
            rollbackSnapshotRecorded = $false
            productionEligible = $false
            activeAssetMutation = $false
            q003CanClose = $false
            q004CanAdvance = $false
        }
        teacherEfficiencyBoundary = 'ordinary teacher flow is not changed; NS1103 only verifies active dry-run prerequisites and keeps real activation evidence as a future prerequisite'
        boundary = 'NS1103 verifies the second-subject active dry-run boundary only. It does not execute an active dry-run, does not switch active assets, does not record rollback snapshots, does not advance Q004, and does not close Q003 or Q002.'
        riskLevel = 'medium'
        rollback = 'git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1 tools/README.md; git clean -f -- tools/run-ns1103-second-subject-active-dry-run-boundary.ps1 docs/evidence/20260531-ns1103-second-subject-active-dry-run.json'
    }

    $reportFullPath = Resolve-InRepoPath $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 12
}
finally {
    Pop-Location
}

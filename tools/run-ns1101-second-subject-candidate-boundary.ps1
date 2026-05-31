param(
    [string] $ReportPath = 'docs/evidence/20260530-ns1101-second-subject-candidate.json',
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $NonSitePlanPath = 'tasks/non-site-implementation-plan.csv',
    [string] $Q001ReportPath = 'docs/evidence/20260523-q001-second-subject-candidate-admission-report.json',
    [string] $Q001ChecklistPath = 'docs/templates/q001-second-subject-candidate-admission-checklist.md',
    [string] $Q001PreflightEvidencePath = 'docs/evidence/20260505-q001-second-subject-candidate-admission-preflight.md',
    [string] $NS905ReportPath = 'docs/evidence/20260530-ns905-status-sync.md'
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
    $checklistFullPath = Resolve-InRepoPath $Q001ChecklistPath
    $preflightEvidenceFullPath = Resolve-InRepoPath $Q001PreflightEvidencePath
    $ns905FullPath = Resolve-InRepoPath $NS905ReportPath

    Assert-Condition (Test-Path -LiteralPath $backlogFullPath) "missing backlog: $BacklogPath"
    Assert-Condition (Test-Path -LiteralPath $planFullPath) "missing non-site plan: $NonSitePlanPath"
    Assert-Condition (Test-Path -LiteralPath $checklistFullPath) "missing Q001 checklist: $Q001ChecklistPath"
    Assert-Condition (Test-Path -LiteralPath $preflightEvidenceFullPath) "missing Q001 preflight evidence: $Q001PreflightEvidencePath"
    Assert-Condition (Test-Path -LiteralPath $ns905FullPath) "missing NS905 status sync report: $NS905ReportPath"

    $backlogRows = @(Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8)
    $planRows = @(Import-Csv -LiteralPath $planFullPath -Encoding UTF8)
    Assert-Condition ($backlogRows.Count -gt 0) 'backlog must not be empty'
    Assert-Condition ($planRows.Count -gt 0) 'non-site plan must not be empty'

    $q001Report = Read-Json $Q001ReportPath
    Assert-Condition ($q001Report.status -eq 'pass') 'Q001 preflight report must pass before NS1101 boundary pack'
    Assert-Condition ($q001Report.mode -eq 'preflight_only') 'Q001 report must remain preflight_only'
    Assert-Condition (-not [bool]$q001Report.closeTaskAllowed) 'Q001 closeTaskAllowed must remain false'
    Assert-Condition ($q001Report.p006Status -eq '待办') 'Q001 report must keep P006 as todo'
    Assert-Condition ($q001Report.q001Status -eq '待办') 'Q001 report must keep Q001 as todo'

    $p006 = Get-RequiredRow $backlogRows 'P006'
    $q001 = Get-RequiredRow $backlogRows 'Q001'
    Assert-Condition ($p006.status -eq '待办') 'P006 backlog task must remain todo'
    Assert-Condition ($q001.status -eq '待办') 'Q001 backlog task must remain todo'
    Assert-Condition ($q001.depends_on -eq 'P006') 'Q001 must continue to depend on P006'

    $nsRows = [ordered]@{}
    foreach ($id in @('NS1001','NS1002','NS1003','NS1004','NS1005','NS1101')) {
        $nsRows[$id] = Get-RequiredRow $planRows $id
    }

    foreach ($id in @('NS1001','NS1002','NS1003','NS1004','NS1005')) {
        Assert-Condition ($nsRows[$id].status -eq 'blocked_by_onsite') "$id must remain blocked_by_onsite before second-subject admission"
    }
    Assert-Condition ($nsRows['NS1101'].depends_on -eq 'NS1005') 'NS1101 must continue to depend on NS1005 release decision'
    Assert-Condition ($nsRows['NS1101'].status -in @('planned','runtime_verified')) "NS1101 has unsupported status for boundary verification: $($nsRows['NS1101'].status)"

    $ns905Text = Get-Content -LiteralPath $ns905FullPath -Raw
    Assert-TextContains $ns905Text @(
        'status: pass',
        'P006: 待办',
        'ns1001: blocked_by_onsite',
        'real005_not_closed: true',
        'next_planned_task_after_this_sync:'
    ) 'NS905 status sync report'

    $checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
    Assert-TextContains $checklistText @(
        'P006',
        '来源资料',
        'candidate',
        '不直接 active'
    ) 'Q001 checklist'

    $preflightEvidenceText = Get-Content -LiteralPath $preflightEvidenceFullPath -Raw
    Assert-TextContains $preflightEvidenceText @(
        'preflight',
        'Q001',
        'platform_na',
        'gate_na',
        '多学科'
    ) 'Q001 preflight evidence'

    $blockers = @($q001Report.blockers | ForEach-Object { [string]$_ })
    Assert-Condition ($blockers -contains 'P006 release decision is not closed.') 'Q001 blockers must include P006 release decision'
    Assert-Condition ($blockers -contains 'Second-subject source package and authorization evidence is not recorded.') 'Q001 blockers must include missing source package evidence'
    Assert-Condition ($blockers -contains 'Candidate admission manifest is not recorded; no second-subject active switch is allowed.') 'Q001 blockers must include no active switch'

    $onsiteBlockers = [ordered]@{}
    foreach ($id in @('NS1001','NS1002','NS1003','NS1004','NS1005')) {
        $onsiteBlockers[$id] = [ordered]@{
            status = [string]$nsRows[$id].status
            task = [string]$nsRows[$id].task
            acceptance = [string]$nsRows[$id].acceptance
        }
    }

    $checkedAt = (Get-Date).ToString('s')
    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS1101'
        checkedAt = $checkedAt
        mode = 'second_subject_candidate_boundary_preflight'
        reportPath = $ReportPath
        backlogPath = $BacklogPath
        nonSitePlanPath = $NonSitePlanPath
        sourceReports = [ordered]@{
            q001PreflightReport = $Q001ReportPath
            q001Checklist = $Q001ChecklistPath
            q001PreflightEvidence = $Q001PreflightEvidencePath
            ns905StatusSync = $NS905ReportPath
        }
        backlog = [ordered]@{
            p006Status = [string]$p006.status
            q001Status = [string]$q001.status
            q001DependsOn = [string]$q001.depends_on
            q001CanClose = $false
        }
        nonSitePlan = [ordered]@{
            ns1101StatusAtCheck = [string]$nsRows['NS1101'].status
            ns1101DependsOn = [string]$nsRows['NS1101'].depends_on
            ns1001ToNs1005 = $onsiteBlockers
        }
        q001Preflight = [ordered]@{
            status = [string]$q001Report.status
            mode = [string]$q001Report.mode
            closeTaskAllowed = [bool]$q001Report.closeTaskAllowed
            currentDecision = [string]$q001Report.currentDecision
            blockers = $blockers
        }
        acceptance = [ordered]@{
            p006RemainsTodo = $true
            q001RemainsTodo = $true
            ns1005RemainsBlockedByOnsite = $true
            sourcePackageAuthorized = $false
            candidateAdmissionManifestRecorded = $false
            secondSubjectAdmissionExecuted = $false
            productionEligible = $false
            activeAssetMutation = $false
            q001CanClose = $false
            q002CanAdvance = $false
        }
        teacherEfficiencyBoundary = 'ordinary teacher flow is not changed; NS1101 only records the missing release/source/candidate evidence before any second-subject work can proceed'
        boundary = 'NS1101 verifies the second-subject candidate admission boundary only. It does not import source material, does not create a candidate manifest, does not switch active assets, and does not close Q001 or P006.'
        riskLevel = 'medium'
        rollback = 'git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1 tools/README.md; git clean -f -- tools/run-ns1101-second-subject-candidate-boundary.ps1 docs/evidence/20260530-ns1101-second-subject-candidate.json'
    }

    $reportFullPath = Resolve-InRepoPath $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 12
}
finally {
    Pop-Location
}

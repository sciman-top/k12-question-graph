param(
    [string] $ReportPath = 'docs/evidence/20260531-ns1104-cross-subject-ui.json',
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $NonSitePlanPath = 'tasks/non-site-implementation-plan.csv',
    [string] $Q004ReportPath = 'docs/evidence/20260523-q004-cross-subject-diff-report.json',
    [string] $Q004ChecklistPath = 'docs/templates/q004-cross-subject-diff-report-checklist.md',
    [string] $Q004PreflightEvidencePath = 'docs/evidence/20260505-q004-cross-subject-diff-report-preflight.md',
    [string] $Q005ReportPath = 'docs/evidence/20260523-q005-multi-subject-ui-simplification-report.json',
    [string] $Q005ChecklistPath = 'docs/templates/q005-multi-subject-ui-simplification-checklist.md',
    [string] $Q005PreflightEvidencePath = 'docs/evidence/20260505-q005-multi-subject-ui-simplification-preflight.md',
    [string] $NS1103ReportPath = 'docs/evidence/20260531-ns1103-second-subject-active-dry-run.json'
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
    $q004ChecklistFullPath = Resolve-InRepoPath $Q004ChecklistPath
    $q004EvidenceFullPath = Resolve-InRepoPath $Q004PreflightEvidencePath
    $q005ChecklistFullPath = Resolve-InRepoPath $Q005ChecklistPath
    $q005EvidenceFullPath = Resolve-InRepoPath $Q005PreflightEvidencePath

    Assert-Condition (Test-Path -LiteralPath $backlogFullPath) "missing backlog: $BacklogPath"
    Assert-Condition (Test-Path -LiteralPath $planFullPath) "missing non-site plan: $NonSitePlanPath"
    Assert-Condition (Test-Path -LiteralPath $q004ChecklistFullPath) "missing Q004 checklist: $Q004ChecklistPath"
    Assert-Condition (Test-Path -LiteralPath $q004EvidenceFullPath) "missing Q004 preflight evidence: $Q004PreflightEvidencePath"
    Assert-Condition (Test-Path -LiteralPath $q005ChecklistFullPath) "missing Q005 checklist: $Q005ChecklistPath"
    Assert-Condition (Test-Path -LiteralPath $q005EvidenceFullPath) "missing Q005 preflight evidence: $Q005PreflightEvidencePath"

    $backlogRows = @(Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8)
    $planRows = @(Import-Csv -LiteralPath $planFullPath -Encoding UTF8)
    Assert-Condition ($backlogRows.Count -gt 0) 'backlog must not be empty'
    Assert-Condition ($planRows.Count -gt 0) 'non-site plan must not be empty'

    $ns1103Report = Read-Json $NS1103ReportPath
    Assert-Condition ($ns1103Report.status -eq 'pass') 'NS1104 requires NS1103 boundary report to pass'
    Assert-Condition (-not [bool]$ns1103Report.acceptance.q003CanClose) 'NS1103 must keep q003CanClose=false'
    Assert-Condition (-not [bool]$ns1103Report.acceptance.q004CanAdvance) 'NS1103 must keep q004CanAdvance=false before active dry-run evidence closes'
    Assert-Condition (-not [bool]$ns1103Report.acceptance.activeSwitchPerformed) 'NS1103 must not perform active switch'
    Assert-Condition (-not [bool]$ns1103Report.acceptance.activeAssetMutation) 'NS1103 must not mutate active assets'

    $q004Report = Read-Json $Q004ReportPath
    Assert-Condition ($q004Report.status -eq 'pass') 'Q004 preflight report must pass before NS1104 boundary pack'
    Assert-Condition ($q004Report.mode -eq 'preflight_only') 'Q004 report must remain preflight_only'
    Assert-Condition (-not [bool]$q004Report.closeTaskAllowed) 'Q004 closeTaskAllowed must remain false'
    Assert-Condition ($q004Report.q003Status -eq '待办') 'Q004 report must keep Q003 as todo'
    Assert-Condition ($q004Report.q004Status -eq '待办') 'Q004 report must keep Q004 as todo'

    $q005Report = Read-Json $Q005ReportPath
    Assert-Condition ($q005Report.status -eq 'pass') 'Q005 preflight report must pass before NS1104 boundary pack'
    Assert-Condition ($q005Report.mode -eq 'preflight_only') 'Q005 report must remain preflight_only'
    Assert-Condition (-not [bool]$q005Report.closeTaskAllowed) 'Q005 closeTaskAllowed must remain false'
    Assert-Condition ($q005Report.q004Status -eq '待办') 'Q005 report must keep Q004 as todo'
    Assert-Condition ($q005Report.q005Status -eq '待办') 'Q005 report must keep Q005 as todo'

    $q003 = Get-RequiredRow $backlogRows 'Q003'
    $q004 = Get-RequiredRow $backlogRows 'Q004'
    $q005 = Get-RequiredRow $backlogRows 'Q005'
    Assert-Condition ($q003.status -eq '待办') 'Q003 backlog task must remain todo'
    Assert-Condition ($q004.status -eq '待办') 'Q004 backlog task must remain todo'
    Assert-Condition ($q005.status -eq '待办') 'Q005 backlog task must remain todo'
    Assert-Condition ($q004.depends_on -eq 'Q003') 'Q004 must continue to depend on Q003'
    Assert-Condition ($q005.depends_on -eq 'Q004') 'Q005 must continue to depend on Q004'

    $ns1103Row = Get-RequiredRow $planRows 'NS1103'
    $ns1104Row = Get-RequiredRow $planRows 'NS1104'
    Assert-Condition ($ns1103Row.status -eq 'runtime_verified') 'NS1104 requires NS1103 runtime_verified boundary evidence'
    Assert-Condition ($ns1104Row.depends_on -eq 'NS1103') 'NS1104 must continue to depend on NS1103'
    Assert-Condition ($ns1104Row.status -in @('planned','runtime_verified')) "NS1104 has unsupported status for boundary verification: $($ns1104Row.status)"

    $q004ChecklistText = Get-Content -LiteralPath $q004ChecklistFullPath -Raw
    Assert-TextContains $q004ChecklistText @(
        '题型',
        '标签',
        '评分',
        '导出',
        '分析',
        'docs/58'
    ) 'Q004 checklist'

    $q004EvidenceText = Get-Content -LiteralPath $q004EvidenceFullPath -Raw
    Assert-TextContains $q004EvidenceText @(
        'preflight',
        'Q004',
        'platform_na',
        'gate_na',
        '差异报告',
        '下一步'
    ) 'Q004 preflight evidence'

    $q005ChecklistText = Get-Content -LiteralPath $q005ChecklistFullPath -Raw
    Assert-TextContains $q005ChecklistText @(
        '四个入口',
        '学科切换',
        '默认值',
        '模板',
        'UI smoke',
        'teacher efficiency'
    ) 'Q005 checklist'

    $q005EvidenceText = Get-Content -LiteralPath $q005EvidenceFullPath -Raw
    Assert-TextContains $q005EvidenceText @(
        'preflight',
        'Q005',
        'platform_na',
        'gate_na',
        'UI 简化复核',
        '下一步'
    ) 'Q005 preflight evidence'

    $q004Blockers = @($q004Report.blockers | ForEach-Object { [string]$_ })
    Assert-Condition ($q004Blockers -contains 'Q003 second-subject active drill evidence is not closed.') 'Q004 blockers must include Q003 active drill evidence'
    Assert-Condition ($q004Blockers -contains 'Cross-subject differences for question types, tags, scoring, export, and analysis are not recorded.') 'Q004 blockers must include missing cross-subject diff report'
    Assert-Condition ($q004Blockers -contains 'Dynamic-element updates are not mapped back to docs/58 and rollback evidence.') 'Q004 blockers must include docs/58 dynamic-element mapping'

    $q005Blockers = @($q005Report.blockers | ForEach-Object { [string]$_ })
    Assert-Condition ($q005Blockers -contains 'Q004 cross-subject diff report is not closed.') 'Q005 blockers must include Q004 diff report'
    Assert-Condition ($q005Blockers -contains 'Four teacher entry points with multi-subject defaults/templates are not smoke-tested.') 'Q005 blockers must include missing four-entry UI smoke'
    Assert-Condition ($q005Blockers -contains 'Teacher-efficiency evidence is not recorded for any subject switch UI.') 'Q005 blockers must include missing teacher-efficiency evidence'

    $checkedAt = (Get-Date).ToString('s')
    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS1104'
        checkedAt = $checkedAt
        mode = 'cross_subject_diff_and_ui_simplification_boundary'
        reportPath = $ReportPath
        backlogPath = $BacklogPath
        nonSitePlanPath = $NonSitePlanPath
        sourceReports = [ordered]@{
            ns1103BoundaryReport = $NS1103ReportPath
            q004PreflightReport = $Q004ReportPath
            q004Checklist = $Q004ChecklistPath
            q004PreflightEvidence = $Q004PreflightEvidencePath
            q005PreflightReport = $Q005ReportPath
            q005Checklist = $Q005ChecklistPath
            q005PreflightEvidence = $Q005PreflightEvidencePath
        }
        backlog = [ordered]@{
            q003Status = [string]$q003.status
            q004Status = [string]$q004.status
            q005Status = [string]$q005.status
            q004DependsOn = [string]$q004.depends_on
            q005DependsOn = [string]$q005.depends_on
            q004CanClose = $false
            q005CanClose = $false
        }
        nonSitePlan = [ordered]@{
            ns1103Status = [string]$ns1103Row.status
            ns1104StatusAtCheck = [string]$ns1104Row.status
            ns1104DependsOn = [string]$ns1104Row.depends_on
        }
        q004Preflight = [ordered]@{
            status = [string]$q004Report.status
            mode = [string]$q004Report.mode
            closeTaskAllowed = [bool]$q004Report.closeTaskAllowed
            currentDecision = [string]$q004Report.currentDecision
            blockers = $q004Blockers
        }
        q005Preflight = [ordered]@{
            status = [string]$q005Report.status
            mode = [string]$q005Report.mode
            closeTaskAllowed = [bool]$q005Report.closeTaskAllowed
            currentDecision = [string]$q005Report.currentDecision
            blockers = $q005Blockers
        }
        acceptance = [ordered]@{
            q003RemainsTodo = $true
            q004RemainsTodo = $true
            q005RemainsTodo = $true
            crossSubjectDiffReportExecuted = $false
            dynamicElementMappingUpdated = $false
            multiSubjectUiChanged = $false
            fourEntryUiSmokeExecuted = $false
            teacherEfficiencyEvidenceRecorded = $false
            hardCodedSubjectDifferences = $false
            teacherFacingComplexityIncreased = $false
            ordinaryTeacherEntryCountPreserved = $true
            productionEligible = $false
            activeAssetMutation = $false
            q004CanClose = $false
            q005CanClose = $false
        }
        teacherEfficiencyBoundary = 'ordinary teacher flow is not changed; NS1104 only verifies that Q004/Q005 remain blocked until diff and UI evidence exist'
        boundary = 'NS1104 verifies the cross-subject diff and multi-subject UI simplification boundary only. It does not execute the diff report, does not update dynamic element mappings, does not change teacher-facing UI, and does not close Q004 or Q005.'
        riskLevel = 'medium'
        rollback = 'git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1 tools/README.md; git clean -f -- tools/run-ns1104-cross-subject-ui-boundary.ps1 docs/evidence/20260531-ns1104-cross-subject-ui.json'
    }

    $reportFullPath = Resolve-InRepoPath $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 12
}
finally {
    Pop-Location
}

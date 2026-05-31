param(
    [string] $ReportPath = 'docs/evidence/20260530-ns1102-second-subject-review-template.json',
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $NonSitePlanPath = 'tasks/non-site-implementation-plan.csv',
    [string] $Q002ReportPath = 'docs/evidence/20260523-q002-second-subject-teacher-review-template-report.json',
    [string] $Q002ChecklistPath = 'docs/templates/q002-second-subject-teacher-review-template-checklist.md',
    [string] $Q002PreflightEvidencePath = 'docs/evidence/20260505-q002-second-subject-teacher-review-template-preflight.md',
    [string] $NS1101ReportPath = 'docs/evidence/20260530-ns1101-second-subject-candidate.json'
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
    $checklistFullPath = Resolve-InRepoPath $Q002ChecklistPath
    $preflightEvidenceFullPath = Resolve-InRepoPath $Q002PreflightEvidencePath

    Assert-Condition (Test-Path -LiteralPath $backlogFullPath) "missing backlog: $BacklogPath"
    Assert-Condition (Test-Path -LiteralPath $planFullPath) "missing non-site plan: $NonSitePlanPath"
    Assert-Condition (Test-Path -LiteralPath $checklistFullPath) "missing Q002 checklist: $Q002ChecklistPath"
    Assert-Condition (Test-Path -LiteralPath $preflightEvidenceFullPath) "missing Q002 preflight evidence: $Q002PreflightEvidencePath"

    $backlogRows = @(Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8)
    $planRows = @(Import-Csv -LiteralPath $planFullPath -Encoding UTF8)
    Assert-Condition ($backlogRows.Count -gt 0) 'backlog must not be empty'
    Assert-Condition ($planRows.Count -gt 0) 'non-site plan must not be empty'

    $ns1101Report = Read-Json $NS1101ReportPath
    Assert-Condition ($ns1101Report.status -eq 'pass') 'NS1102 requires NS1101 boundary report to pass'
    Assert-Condition (-not [bool]$ns1101Report.acceptance.q001CanClose) 'NS1101 must keep q001CanClose=false'
    Assert-Condition (-not [bool]$ns1101Report.acceptance.q002CanAdvance) 'NS1101 must keep q002CanAdvance=false before Q001 closes'
    Assert-Condition (-not [bool]$ns1101Report.acceptance.secondSubjectAdmissionExecuted) 'NS1101 must not execute second-subject admission'
    Assert-Condition (-not [bool]$ns1101Report.acceptance.activeAssetMutation) 'NS1101 must not mutate active assets'

    $q002Report = Read-Json $Q002ReportPath
    Assert-Condition ($q002Report.status -eq 'pass') 'Q002 preflight report must pass before NS1102 boundary pack'
    Assert-Condition ($q002Report.mode -eq 'preflight_only') 'Q002 report must remain preflight_only'
    Assert-Condition (-not [bool]$q002Report.closeTaskAllowed) 'Q002 closeTaskAllowed must remain false'
    Assert-Condition ($q002Report.q001Status -eq '待办') 'Q002 report must keep Q001 as todo'
    Assert-Condition ($q002Report.q002Status -eq '待办') 'Q002 report must keep Q002 as todo'

    $q001 = Get-RequiredRow $backlogRows 'Q001'
    $q002 = Get-RequiredRow $backlogRows 'Q002'
    $q003 = Get-RequiredRow $backlogRows 'Q003'
    Assert-Condition ($q001.status -eq '待办') 'Q001 backlog task must remain todo'
    Assert-Condition ($q002.status -eq '待办') 'Q002 backlog task must remain todo'
    Assert-Condition ($q003.status -eq '待办') 'Q003 backlog task must remain todo'
    Assert-Condition ($q002.depends_on -eq 'Q001') 'Q002 must continue to depend on Q001'
    Assert-Condition ($q003.depends_on -eq 'Q002') 'Q003 must continue to depend on Q002'

    $ns1101Row = Get-RequiredRow $planRows 'NS1101'
    $ns1102Row = Get-RequiredRow $planRows 'NS1102'
    $ns1103Row = Get-RequiredRow $planRows 'NS1103'
    Assert-Condition ($ns1101Row.status -eq 'runtime_verified') 'NS1102 requires NS1101 runtime_verified boundary evidence'
    Assert-Condition ($ns1102Row.depends_on -eq 'NS1101') 'NS1102 must continue to depend on NS1101'
    Assert-Condition ($ns1102Row.status -in @('planned','runtime_verified')) "NS1102 has unsupported status for boundary verification: $($ns1102Row.status)"
    Assert-Condition ($ns1103Row.depends_on -eq 'NS1102') 'NS1103 must continue to depend on NS1102'

    $checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
    Assert-TextContains $checklistText @(
        'Q001',
        '教师复核',
        '候选知识点',
        '教材章节',
        '课标',
        '考点',
        'review evidence'
    ) 'Q002 checklist'

    $preflightEvidenceText = Get-Content -LiteralPath $preflightEvidenceFullPath -Raw
    Assert-TextContains $preflightEvidenceText @(
        'preflight',
        'Q002',
        'platform_na',
        'gate_na',
        '复核模板',
        '下一步'
    ) 'Q002 preflight evidence'

    $blockers = @($q002Report.blockers | ForEach-Object { [string]$_ })
    Assert-Condition ($blockers -contains 'Q001 second-subject candidate admission is not closed.') 'Q002 blockers must include Q001 not closed'
    Assert-Condition ($blockers -contains 'Teacher review template has not been applied to real candidate knowledge points, textbook chapters, curriculum standards, and exam points.') 'Q002 blockers must include missing real teacher review application'
    Assert-Condition ($blockers -contains 'Review evidence and teacher-efficiency impact are not recorded.') 'Q002 blockers must include missing review evidence and teacher-efficiency impact'

    $checkedAt = (Get-Date).ToString('s')
    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS1102'
        checkedAt = $checkedAt
        mode = 'second_subject_teacher_review_template_boundary'
        reportPath = $ReportPath
        backlogPath = $BacklogPath
        nonSitePlanPath = $NonSitePlanPath
        sourceReports = [ordered]@{
            ns1101BoundaryReport = $NS1101ReportPath
            q002PreflightReport = $Q002ReportPath
            q002Checklist = $Q002ChecklistPath
            q002PreflightEvidence = $Q002PreflightEvidencePath
        }
        backlog = [ordered]@{
            q001Status = [string]$q001.status
            q002Status = [string]$q002.status
            q003Status = [string]$q003.status
            q002DependsOn = [string]$q002.depends_on
            q003DependsOn = [string]$q003.depends_on
            q002CanClose = $false
        }
        nonSitePlan = [ordered]@{
            ns1101Status = [string]$ns1101Row.status
            ns1102StatusAtCheck = [string]$ns1102Row.status
            ns1102DependsOn = [string]$ns1102Row.depends_on
            ns1103DependsOn = [string]$ns1103Row.depends_on
        }
        q002Preflight = [ordered]@{
            status = [string]$q002Report.status
            mode = [string]$q002Report.mode
            closeTaskAllowed = [bool]$q002Report.closeTaskAllowed
            currentDecision = [string]$q002Report.currentDecision
            blockers = $blockers
        }
        acceptance = [ordered]@{
            q001RemainsTodo = $true
            q002RemainsTodo = $true
            q003RemainsTodo = $true
            teacherReviewTemplatePresent = $true
            teacherReviewExecuted = $false
            realCandidateAssetsReviewed = $false
            teacherEfficiencyImpactRecorded = $false
            productionEligible = $false
            activeAssetMutation = $false
            q002CanClose = $false
            q003CanAdvance = $false
        }
        teacherEfficiencyBoundary = 'ordinary teacher flow is not changed; NS1102 only verifies the review template and keeps real teacher review evidence as a future prerequisite'
        boundary = 'NS1102 verifies the second-subject teacher review template boundary only. It does not execute teacher review, does not review real candidate assets, does not advance Q003, and does not close Q002 or Q001.'
        riskLevel = 'medium'
        rollback = 'git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1 tools/README.md; git clean -f -- tools/run-ns1102-second-subject-review-template-boundary.ps1 docs/evidence/20260530-ns1102-second-subject-review-template.json'
    }

    $reportFullPath = Resolve-InRepoPath $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 12
}
finally {
    Pop-Location
}

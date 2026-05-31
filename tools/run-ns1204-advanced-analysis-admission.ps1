param(
    [string] $ReportPath = 'docs/evidence/20260531-ns1204-advanced-analysis-admission.json',
    [string] $NonSitePlanPath = 'tasks/non-site-implementation-plan.csv',
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $R004ReportPath = 'docs/evidence/20260519-r004-advanced-analysis-admission-report.json',
    [string] $R004DecisionPath = 'docs/decisions/ADR-006-advanced-analysis-admission.md',
    [string] $R004ChecklistPath = 'docs/templates/r004-advanced-analysis-eval-checklist.md',
    [string] $R004PreflightEvidencePath = 'docs/evidence/20260505-r004-advanced-analysis-eval-preflight.md',
    [string] $NS704ReportPath = 'docs/evidence/20260530-ns704-commentary-report.json',
    [string] $CompletionDashboardPath = 'tasks/completion-state-dashboard.csv'
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

function Find-CodePatternHits([string[]] $RelativeRoots, [string[]] $Patterns) {
    $hits = @()
    foreach ($relativeRoot in $RelativeRoots) {
        $fullRoot = Resolve-InRepoPath $relativeRoot
        if (-not (Test-Path -LiteralPath $fullRoot)) { continue }

        $files = @(Get-ChildItem -LiteralPath $fullRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $_.FullName -notmatch '\\(bin|obj|node_modules)\\'
        })
        foreach ($file in $files) {
            foreach ($pattern in $Patterns) {
                $matches = @(Select-String -LiteralPath $file.FullName -Pattern $pattern -CaseSensitive:$false -ErrorAction SilentlyContinue)
                foreach ($match in $matches) {
                    $hits += [ordered]@{
                        path = $file.FullName.Substring($repoRoot.Length + 1)
                        line = $match.LineNumber
                        pattern = $pattern
                    }
                }
            }
        }
    }

    return @($hits)
}

Push-Location $repoRoot
try {
    $planFullPath = Resolve-InRepoPath $NonSitePlanPath
    $backlogFullPath = Resolve-InRepoPath $BacklogPath
    $decisionFullPath = Resolve-InRepoPath $R004DecisionPath
    $checklistFullPath = Resolve-InRepoPath $R004ChecklistPath
    $preflightEvidenceFullPath = Resolve-InRepoPath $R004PreflightEvidencePath
    $completionDashboardFullPath = Resolve-InRepoPath $CompletionDashboardPath

    foreach ($requiredPath in @($planFullPath, $backlogFullPath, $decisionFullPath, $checklistFullPath, $preflightEvidenceFullPath, $completionDashboardFullPath)) {
        Assert-Condition (Test-Path -LiteralPath $requiredPath) "missing required file: $requiredPath"
    }

    $planRows = @(Import-Csv -LiteralPath $planFullPath -Encoding UTF8)
    $backlogRows = @(Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8)
    $dashboardRows = @(Import-Csv -LiteralPath $completionDashboardFullPath -Encoding UTF8)

    $ns704 = Get-RequiredRow $planRows 'NS704'
    $ns1204 = Get-RequiredRow $planRows 'NS1204'
    Assert-Condition ($ns704.status -eq 'runtime_verified') 'NS1204 requires NS704 commentary report runtime evidence'
    Assert-Condition ($ns1204.depends_on -eq 'NS704') 'NS1204 must continue to depend on NS704'
    Assert-Condition ($ns1204.status -in @('planned','runtime_verified')) "NS1204 has unsupported status: $($ns1204.status)"
    Assert-Condition ($ns1204.acceptance -match 'IRT' -and $ns1204.acceptance -match '样本量' -and $ns1204.acceptance -match '解释责任边界') 'NS1204 acceptance must keep advanced-analysis admission boundary'

    $n004 = Get-RequiredRow $backlogRows 'N004'
    $r004 = Get-RequiredRow $backlogRows 'R004'
    Assert-Condition ($n004.status -eq '已完成') 'N004 must remain completed before NS1204 boundary verification'
    Assert-Condition ($r004.status -eq '待办') 'NS1204 must not close R004 without post-ADR feature admission evidence'
    Assert-Condition ($r004.depends_on -eq 'N004') 'R004 must continue to depend on N004'

    $r004Report = Read-Json $R004ReportPath
    $ns704Report = Read-Json $NS704ReportPath
    Assert-Condition ($r004Report.status -eq 'pass') 'NS1204 requires R004 admission report to pass'
    Assert-Condition (-not [bool]$r004Report.closeTaskAllowed) 'R004 closeTaskAllowed must remain false'
    Assert-Condition ($r004Report.currentDecision -eq 'keep_R004_todo_fail_closed_for_advanced_methods') 'R004 decision must remain fail-closed for advanced methods'
    Assert-Condition ($ns704Report.status -eq 'pass') 'NS704 commentary report must pass before NS1204'
    Assert-Condition (-not [bool]$ns704Report.productionEligible) 'NS704 must remain non-production eligible'
    Assert-Condition (-not [bool]$ns704Report.realStudentDataUsed) 'NS704 must not use real student data'
    Assert-Condition (-not [bool]$ns704Report.writesProductionHistory) 'NS704 must not write production history'

    $matrixByKind = @{}
    foreach ($entry in @($r004Report.admissionMatrix)) {
        $matrixByKind[[string]$entry.analysisKind] = $entry
    }
    foreach ($kind in @('basic_ctt_commentary', 'irt_calibration', 'form_equating', 'longitudinal_growth')) {
        Assert-Condition ($matrixByKind.ContainsKey($kind)) "R004 admission matrix missing: $kind"
    }
    Assert-Condition ($matrixByKind['basic_ctt_commentary'].currentDecision -eq 'allowed_in_draft_test') 'basic CTT commentary must remain allowed only in draft/test'
    Assert-Condition ($matrixByKind['irt_calibration'].currentDecision -eq 'blocked') 'IRT must remain blocked'
    Assert-Condition ($matrixByKind['form_equating'].currentDecision -eq 'blocked') 'form equating must remain blocked'
    Assert-Condition ($matrixByKind['longitudinal_growth'].currentDecision -eq 'blocked') 'longitudinal growth must remain blocked'
    Assert-Condition ([int]$r004Report.samplePolicy.irtPilotMinimum -ge 500) 'IRT pilot minimum must stay at least 500'
    Assert-Condition ([int]$r004Report.samplePolicy.operationalEquatingMinimum -ge 1000) 'operational equating minimum must stay at least 1000'
    Assert-Condition ([int]$r004Report.samplePolicy.longitudinalMinimumCohorts -ge 3) 'longitudinal minimum cohorts must stay at least 3'

    $decisionText = Get-Content -LiteralPath $decisionFullPath -Raw
    Assert-TextContains $decisionText @(
        'ADR-006',
        'fail-closed',
        'CTT baseline',
        'IRT calibration',
        'form equating',
        'longitudinal growth',
        'teacher explanation boundary'
    ) 'ADR-006'

    $checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
    Assert-TextContains $checklistText @(
        'IRT',
        '等值',
        '长期成长',
        '样本量',
        '解释责任边界',
        'fail-closed'
    ) 'R004 checklist'

    $preflightText = Get-Content -LiteralPath $preflightEvidenceFullPath -Raw
    Assert-TextContains $preflightText @(
        'R004',
        'platform_na',
        'gate_na',
        '高级分析',
        'fail-closed'
    ) 'R004 preflight evidence'

    $analysisReportArea = Get-RequiredRow $dashboardRows 'analysis-report' 'area_id'
    $advancedPlatformArea = Get-RequiredRow $dashboardRows 'advanced-platform' 'area_id'
    Assert-Condition ($analysisReportArea.current_state -eq 'teacher_validated') 'analysis-report dashboard state must remain teacher_validated'
    Assert-Condition ($analysisReportArea.blocking_gap -match '正式历史口径|现场学情发布') 'analysis-report must retain formal-history/pilot boundary'
    Assert-Condition ($advancedPlatformArea.usable_today -eq '不可使用') 'advanced-platform must remain unavailable before advanced-analysis admission'

    $codePatternHits = Find-CodePatternHits @('apps/api', 'apps/web/src', 'schemas', 'workers') @(
        '\bIRT\b',
        'item\s+response\s+theory',
        'form\s+equating',
        'longitudinal\s+growth',
        'ability\s+scale',
        'growth\s+score',
        'DIF\s+diagnostic'
    )
    Assert-Condition ($codePatternHits.Count -eq 0) 'NS1204 found product code that appears to enable IRT/equating/growth analysis'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS1204'
        checkedAt = (Get-Date).ToString('s')
        mode = 'advanced_analysis_admission_boundary'
        productionEligible = $false
        nonSiteValidated = $false
        releaseReady = $false
        externalAiCalls = 0
        realStudentDataUsed = $false
        containsStudentPii = $false
        writesProductionHistory = $false
        activeAssetMutation = $false
        dependency = [ordered]@{
            ns704 = $NS704ReportPath
            r004Report = $R004ReportPath
            r004Decision = $R004DecisionPath
            r004Checklist = $R004ChecklistPath
            r004PreflightEvidence = $R004PreflightEvidencePath
            completionDashboard = $CompletionDashboardPath
        }
        backlog = [ordered]@{
            n004Status = [string]$n004.status
            r004Status = [string]$r004.status
            r004CloseTaskAllowed = $false
            ns704Status = [string]$ns704.status
            ns1204StatusAtCheck = [string]$ns1204.status
            ns1204DependsOn = [string]$ns1204.depends_on
        }
        currentBaseline = [ordered]@{
            basicCttCommentary = [string]$matrixByKind['basic_ctt_commentary'].currentDecision
            f003StudentCount = [int]$r004Report.currentSample.f003StudentCount
            f003MinimumKnowledgeSampleSize = [int]$r004Report.currentSample.f003MinimumKnowledgeSampleSize
            real012AnalysisReady = [bool]$r004Report.currentSample.real012AnalysisReady
            real005ClosureStatus = [string]$r004Report.currentSample.real005ClosureStatus
        }
        admissionDecision = [ordered]@{
            basicCttCommentary = [string]$matrixByKind['basic_ctt_commentary'].currentDecision
            irtCalibration = [string]$matrixByKind['irt_calibration'].currentDecision
            formEquating = [string]$matrixByKind['form_equating'].currentDecision
            longitudinalGrowth = [string]$matrixByKind['longitudinal_growth'].currentDecision
            currentDecision = [string]$r004Report.currentDecision
        }
        samplePolicy = $r004Report.samplePolicy
        codeScan = [ordered]@{
            searchedRoots = @('apps/api', 'apps/web/src', 'schemas', 'workers')
            blockedPatterns = @('IRT', 'item response theory', 'form equating', 'longitudinal growth', 'ability scale', 'growth score', 'DIF diagnostic')
            hitCount = [int]$codePatternHits.Count
            noIrtEndpointOrMetric = $true
            noEquatingOutput = $true
            noLongitudinalGrowthRoute = $true
            noFormalHistoryMetric = $true
        }
        acceptance = [ordered]@{
            r004AdmissionReportPassed = $true
            adr006FailClosedAccepted = $true
            basicCttKeptDraftTest = $true
            irtBlocked = $true
            equatingBlocked = $true
            longitudinalGrowthBlocked = $true
            explanationDutyRecorded = $true
            ns704RemainsNonProduction = $true
            r004RemainsTodo = $true
            noRealStudentData = $true
            noProductionHistoryWrite = $true
            noAdvancedAnalysisRouteEnabled = $true
        }
        nextRequiredEvidence = @(
            'post-ADR feature admission with explicit owner, rollback, sample plan, and teacher explanation card',
            'authorized/anonymized multi-class score sample after P001/P006 boundary is clear',
            'CTT baseline benchmark showing why current descriptive reports are insufficient',
            'independent review of IRT/equating/growth interpretation risk before any production UI'
        )
        verification = [ordered]@{
            build = 'gate_na: admission boundary script only; no product code build required'
            test = 'tools/run-r004-advanced-analysis-eval-preflight-contract.ps1 + tools/run-ns1204-advanced-analysis-admission.ps1'
            contractInvariant = 'NS1204 keeps only basic CTT/commentary in draft/test, leaves R004 blocked, and verifies no IRT/equating/growth route or formal-history metric was enabled'
            hotspot = 'gate_na: advanced-analysis admission requires real authorized sample, psychometric owner, explanation card, and rollback evidence'
        }
        teacherEfficiencyBoundary = 'ordinary teacher commentary remains descriptive and explainable; NS1204 prevents high-risk measurement claims from increasing teacher explanation burden prematurely'
        boundary = 'NS1204 verifies the advanced-analysis admission boundary only. It does not process real student data, does not compute IRT/equating/growth metrics, does not add teacher-facing advanced-analysis UI, and does not write formal history.'
        rollback = "git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1 tools/README.md; git clean -f -- tools/run-ns1204-advanced-analysis-admission.ps1 $ReportPath"
        next = 'NS1205 can continue public/multischool deploy admission boundary; advanced analysis remains blocked until sample, owner, explanation, and rollback evidence exist.'
    }

    $jsonText = $report | ConvertTo-Json -Depth 12
    $reportFullPath = Resolve-InRepoPath $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $jsonText | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $jsonText
}
finally {
    Pop-Location
}

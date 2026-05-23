param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ChecklistPath = 'docs/templates/r004-advanced-analysis-eval-checklist.md',
    [string] $EvidencePath = 'docs/evidence/20260505-r004-advanced-analysis-eval-preflight.md',
    [string] $CompletionDashboardPath = 'tasks/completion-state-dashboard.csv',
    [string] $AutomationFirstPath = 'tasks/automation-first-contract.csv',
    [string] $F003ReportPath = 'docs/evidence/f003-knowledge-mastery-analysis-report.json',
    [string] $N004EvidencePath = 'docs/evidence/20260505-n004-class-commentary-report-mvp.md',
    [string] $Real012ReportPath = 'docs/evidence/20260518-real012-production-flow-quality-report.json',
    [string] $DecisionPath = 'docs/decisions/ADR-006-advanced-analysis-admission.md',
    [string] $ReportPath = 'docs/evidence/20260519-r004-advanced-analysis-admission-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Resolve-RepoPath([string] $Path) {
    return Join-Path $repoRoot ($Path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
}

function Read-JsonFile([string] $Path) {
    $fullPath = Resolve-RepoPath $Path
    Assert-True (Test-Path -LiteralPath $fullPath) "R004 required JSON evidence missing: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Write-ContentIfChanged([string] $Path, [string] $Content) {
    $fullPath = Resolve-RepoPath $Path
    $parent = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (Test-Path -LiteralPath $fullPath) {
        $existing = Get-Content -LiteralPath $fullPath -Raw
        if ($existing -eq $Content) { return }
    }

    Set-Content -LiteralPath $fullPath -Value $Content -Encoding UTF8
}

$rows = Import-Csv -LiteralPath (Resolve-RepoPath $BacklogPath) -Encoding UTF8
$byId = @{}
foreach ($row in $rows) { $byId[$row.id] = $row }
foreach ($id in @('N004', 'R004')) {
    Assert-True ($byId.ContainsKey($id)) "R004 prerequisite task missing: $id"
}

$n004 = $byId['N004']
$r004 = $byId['R004']
Assert-True ($r004.depends_on -eq 'N004') 'R004 must depend on N004'
Assert-True ($n004.status -eq '已完成') 'N004 must be completed before R004 preflight can pass'
Assert-True ($r004.status -eq '待办') 'R004 must remain todo until advanced-analysis research/admission evidence is completed'
Assert-True ($r004.acceptance -match '样本量' -and $r004.acceptance -match '解释责任边界') 'R004 acceptance must require sample size and explanation responsibility boundaries'

$checklist = Get-Content -LiteralPath (Resolve-RepoPath $ChecklistPath) -Raw
foreach ($keyword in @('IRT', '等值', '长期成长', '样本量', '解释责任边界', 'feature admission', 'fail-closed', 'CTT baseline')) {
    Assert-True ($checklist.Contains($keyword)) "R004 checklist missing keyword: $keyword"
}

$evidence = Get-Content -LiteralPath (Resolve-RepoPath $EvidencePath) -Raw
foreach ($keyword in @('preflight', 'R004', 'platform_na', 'gate_na', '高级分析', '下一步')) {
    Assert-True ($evidence.Contains($keyword)) "R004 evidence missing keyword: $keyword"
}

$n004Evidence = Get-Content -LiteralPath (Resolve-RepoPath $N004EvidencePath) -Raw
foreach ($keyword in @('draft/test', '不写正式历史口径', '无真实学生数据')) {
    Assert-True ($n004Evidence.Contains($keyword)) "N004 evidence must preserve draft/test boundary: $keyword"
}

$decision = Get-Content -LiteralPath (Resolve-RepoPath $DecisionPath) -Raw
foreach ($keyword in @('ADR-006', 'fail-closed', 'CTT baseline', 'IRT calibration', 'form equating', 'longitudinal growth', 'teacher explanation boundary', 'rollback or disable switch')) {
    Assert-True ($decision.Contains($keyword)) "R004 ADR missing keyword: $keyword"
}

$dashboardRows = Import-Csv -LiteralPath (Resolve-RepoPath $CompletionDashboardPath) -Encoding UTF8
$dashboardByArea = @{}
foreach ($row in $dashboardRows) { $dashboardByArea[$row.area_id] = $row }
foreach ($areaId in @('analysis-report', 'advanced-platform')) {
    Assert-True ($dashboardByArea.ContainsKey($areaId)) "completion dashboard missing area: $areaId"
}

$analysisDashboard = $dashboardByArea['analysis-report']
$advancedDashboard = $dashboardByArea['advanced-platform']
Assert-True ($analysisDashboard.current_state -eq 'teacher_validated') 'analysis-report must stay teacher_validated before R004 evaluation'
Assert-True ($analysisDashboard.blocking_gap -match '正式历史口径|现场学情发布') 'analysis-report must keep production history/pilot blocker'
Assert-True ($advancedDashboard.current_state -eq 'contract_done') 'advanced-platform must stay contract_done'
Assert-True ($advancedDashboard.usable_today -eq '不可使用') 'advanced-platform must remain unavailable before admission'
Assert-True ($advancedDashboard.blocking_gap -match '真实瓶颈|发布后证据') 'advanced-platform must require real bottleneck or post-release evidence'

$automationRows = Import-Csv -LiteralPath (Resolve-RepoPath $AutomationFirstPath) -Encoding UTF8
$automationById = @{}
foreach ($row in $automationRows) { $automationById[$row.task_id] = $row }
Assert-True ($automationById.ContainsKey('R004')) 'automation-first contract missing R004 row'
$r004Automation = $automationById['R004']
Assert-True ($r004Automation.deterministic_precheck -match 'sample|样本|CTT|baseline|responsibility|责任') 'R004 automation-first deterministic precheck must include sample/CTT/responsibility checks'
Assert-True ($r004Automation.exception_policy -match 'IRT|sample|responsibility|blocks|without') 'R004 automation-first exception policy must block IRT without sample/responsibility evidence'

$f003 = Read-JsonFile $F003ReportPath
Assert-True ($f003.status -eq 'pass') 'F003 report must pass before R004 preflight'
Assert-True ($f003.productionEligible -eq $false) 'F003 must not be production eligible'
Assert-True ($f003.realStudentDataUsed -eq $false) 'F003 must not use real student data'
Assert-True ($f003.noProductionHistoryWrite -eq $true) 'F003 must not write production history'
Assert-True ($f003.classSummary.discriminationAvailable -eq $true) 'F003 must provide the CTT baseline signal'

$studentCount = [int] $f003.classSummary.studentCount
$knowledgeSampleSizes = @($f003.knowledgePointSummaries | ForEach-Object { [int] $_.sampleSize })
$minimumKnowledgeSampleSize = if ($knowledgeSampleSizes.Count -gt 0) {
    [int] ($knowledgeSampleSizes | Measure-Object -Minimum).Minimum
}
else {
    0
}

$real012 = Read-JsonFile $Real012ReportPath
Assert-True ($real012.status -eq 'pass') 'REAL012 report must pass before R004 can cite real-question analysis smoke'
Assert-True ($real012.analysis.status -eq 'ready') 'REAL012 analysis smoke must be ready'
Assert-True ($real012.analysis.allowAiDraftText -eq $false) 'REAL012 analysis must keep AI draft text disabled'
Assert-True ($real012.analysis.writesProductionHistory -eq $false) 'REAL012 analysis must not write formal history'
Assert-True ($real012.real005ClosureStatus -eq 'not_closed') 'REAL012 must keep full real-paper closure not_closed'

$samplePolicy = [ordered]@{
    policyNature = 'project admission thresholds; revise only through R004 ADR after evidence review'
    descriptiveCttMinimum = 2
    descriptiveCttWarningBelow = 30
    irtPilotMinimum = 500
    operationalEquatingMinimum = 1000
    longitudinalMinimumCohorts = 3
    mandatoryEvidence = @(
        'authorized_or_anonymized_score_records',
        'stable_item_to_question_mapping',
        'active_knowledge_version_reference',
        'missing_data_policy',
        'psychometric_owner',
        'teacher_explanation_boundary',
        'rollback_or_disable_switch'
    )
}

$admissionMatrix = @(
    [ordered]@{
        analysisKind = 'basic_ctt_commentary'
        currentDecision = 'allowed_in_draft_test'
        currentEvidence = "N004/F003 available with synthetic studentCount=$studentCount and minKnowledgeSampleSize=$minimumKnowledgeSampleSize; REAL012 real-question analysis smoke is ready without production history writes."
        allowedOutput = '得分率、区分度、薄弱知识点和讲评建议；必须标注 draft/test 或非正式口径。'
        teacherExplanationDuty = '解释为描述性班级讲评信号，不解释为能力量尺、成长分或跨卷可比分。'
        failClosedRule = '只要使用真实学生数据、写正式历史口径、隐藏小样本提示或绕过 N001/P001 授权，即阻断。'
    }
    [ordered]@{
        analysisKind = 'irt_calibration'
        currentDecision = 'blocked'
        currentEvidence = "current F003 sample is synthetic studentCount=$studentCount; no reviewed large response sample, fit/DIF diagnostics, or psychometric owner evidence."
        requiredBeforeAdmission = @('large_authorized_response_sample', 'stable_item_bank', 'missing_data_policy', 'fit_dif_diagnostics', 'psychometric_owner', 'rollback_plan')
        failClosedRule = '不得新增 IRT endpoint、UI 文案、导出字段或数据库正式指标；AI 只能生成待审解释草稿。'
    }
    [ordered]@{
        analysisKind = 'form_equating'
        currentDecision = 'blocked'
        currentEvidence = 'no anchor-item design, cross-form common-student/common-item evidence, or operational equating owner.'
        requiredBeforeAdmission = @('anchor_design', 'cross_form_sample', 'score_scale_owner', 'teacher_explainability_card', 'historical_report_freeze_policy')
        failClosedRule = '不得宣称不同试卷分数可直接等值；只能保留单卷内描述性分析。'
    }
    [ordered]@{
        analysisKind = 'longitudinal_growth'
        currentDecision = 'blocked'
        currentEvidence = 'no authorized longitudinal identifiers, cohort continuity evidence, or privacy retention approval.'
        requiredBeforeAdmission = @('N001_real_privacy_authorization', 'longitudinal_id_policy', 'minimum_three_cohorts', 'measurement_invariance_review', 'retention_and_deletion_plan')
        failClosedRule = '不得生成学生长期成长轨迹、排名趋势或正式历史学情；只允许当前班级 draft/test 汇总。'
    }
)

$blockers = @(
    'R004 remains todo; ADR-006 exists, but no post-ADR feature admission for advanced methods exists yet.',
    "Current F003 sample is synthetic and small (studentCount=$studentCount, minKnowledgeSampleSize=$minimumKnowledgeSampleSize).",
    'REAL012 only proves sampled real-question commentary reference; full 2015-2025 closure is still not_closed.',
    'No real authorized student score sample, psychometric owner, anchor design, or explanation responsibility card exists.'
)

$report = [ordered]@{
    status = 'pass'
    taskId = 'R004'
    mode = 'admission_preflight'
    checkedAt = (Get-Date).ToString('s')
    n004Status = $n004.status
    r004Status = $r004.status
    closeTaskAllowed = $false
    currentDecision = 'keep_R004_todo_fail_closed_for_advanced_methods'
    checklistPath = $ChecklistPath
    evidencePath = $EvidencePath
    referencedEvidence = [ordered]@{
        f003Report = $F003ReportPath
        n004Evidence = $N004EvidencePath
        real012Report = $Real012ReportPath
        completionDashboard = $CompletionDashboardPath
        automationFirstContract = $AutomationFirstPath
        decision = $DecisionPath
    }
    currentSample = [ordered]@{
        f003StudentCount = $studentCount
        f003MinimumKnowledgeSampleSize = $minimumKnowledgeSampleSize
        f003ProductionEligible = [bool] $f003.productionEligible
        f003RealStudentDataUsed = [bool] $f003.realStudentDataUsed
        f003NoProductionHistoryWrite = [bool] $f003.noProductionHistoryWrite
        real012AnalysisReady = [bool] ($real012.analysis.status -eq 'ready')
        real012WritesProductionHistory = [bool] $real012.analysis.writesProductionHistory
        real005ClosureStatus = [string] $real012.real005ClosureStatus
    }
    samplePolicy = $samplePolicy
    admissionMatrix = $admissionMatrix
    blockers = $blockers
    nextRequiredEvidence = @(
        'post-ADR feature admission with explicit owner, rollback, sample plan, and teacher explanation card',
        'authorized/anonymized multi-class score sample after P001/P006 boundary is clear',
        'CTT baseline benchmark showing why current descriptive reports are insufficient',
        'independent review of IRT/equating/growth interpretation risk before any production UI'
    )
    boundary = 'R004 only refreshes advanced-analysis admission evidence and ADR-006; it performs no production write, no real student data processing, no IRT/equating computation, and no completion-state transition.'
    rollback = 'revert tools/run-r004-advanced-analysis-eval-preflight-contract.ps1, docs/templates/r004-advanced-analysis-eval-checklist.md, docs/decisions/ADR-006-advanced-analysis-admission.md, tasks/backlog.csv, and remove the generated R004 admission report.'
}

$json = $report | ConvertTo-Json -Depth 10
Write-ContentIfChanged -Path $ReportPath -Content $json
$report | ConvertTo-Json -Depth 10

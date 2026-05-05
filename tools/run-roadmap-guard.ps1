$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$backlogPath = Join-Path $repoRoot 'tasks\backlog.csv'
$rows = Import-Csv -LiteralPath $backlogPath -Encoding UTF8
$byId = @{}
foreach ($row in $rows) {
    $byId[$row.id] = $row
}

foreach ($requiredId in @(
    'C002', 'C002N', 'C002O', 'C002P', 'C002Q0', 'C002Q', 'C002S', 'C002T',
    'D001', 'D002', 'D003',
    'I008', 'I009', 'I010',
    'O004', 'O004B',
    'P001'
)) {
    if (-not $byId.ContainsKey($requiredId)) {
        throw "missing backlog task: $requiredId"
    }
}

$c002 = $byId['C002']
$c002n = $byId['C002N']
$c002o = $byId['C002O']
$c002q0 = $byId['C002Q0']
$c002q = $byId['C002Q']
$c002s = $byId['C002S']
$c002t = $byId['C002T']
$d001 = $byId['D001']
$i008 = $byId['I008']
$i009 = $byId['I009']
$i010 = $byId['I010']
$o004 = $byId['O004']
$o004b = $byId['O004B']
$p001 = $byId['P001']
if ($d001.depends_on -eq 'C002') {
    throw "D001 must not depend on formal C002; use the dynamic asset draft/test gate such as C002H"
}

if ($c002n.depends_on -ne 'C002N0') {
    throw "C002N must depend on C002N0 local-first AI consumption review"
}

if ($c002o.depends_on -ne 'C002N') {
    throw "C002O must depend on C002N chunk cache evidence"
}

if ($c002q0.depends_on -ne 'C002P') {
    throw "C002Q0 must depend on C002P model budget guard"
}

if ($c002q.depends_on -ne 'C002Q0') {
    throw "C002Q must depend on C002Q0 orchestration readiness"
}

if ($c002s.depends_on -ne 'C002Q') {
    throw "C002S must depend on C002Q small-batch AI extract dry-run"
}

if ($c002t.depends_on -ne 'C002M') {
    throw "C002T active switch must depend on C002M review apply contract"
}

if ($c002.depends_on -ne 'C002T') {
    throw "formal C002 must depend on C002T active switch"
}

if ($c002n.status -eq '已完成') {
    $c002nReport = Join-Path $repoRoot 'docs\evidence\c002n-source-chunk-cache-report.json'
    if (-not (Test-Path -LiteralPath $c002nReport)) {
        throw "C002N is completed but report is missing: docs/evidence/c002n-source-chunk-cache-report.json"
    }
    $report = Get-Content -LiteralPath $c002nReport -Raw | ConvertFrom-Json
    if ($report.status -ne 'pass' -or $report.externalAiCalls -ne 0 -or $report.sourceHashCoverage.coveragePass -ne $true) {
        throw "C002N report must pass with zero external AI calls and full source hash coverage"
    }
}

if ($c002o.status -eq '已完成') {
    $c002oReport = Join-Path $repoRoot 'docs\evidence\c002o-candidate-extraction-eval-report.json'
    if (-not (Test-Path -LiteralPath $c002oReport)) {
        throw "C002O is completed but report is missing: docs/evidence/c002o-candidate-extraction-eval-report.json"
    }
    $report = Get-Content -LiteralPath $c002oReport -Raw | ConvertFrom-Json
    if ($report.status -ne 'pass' -or $report.allowRealModelCalls -ne $false -or $report.productionEligible -ne $false) {
        throw "C002O report must pass with real model calls disabled and production eligibility false"
    }
    foreach ($requiredSection in @('knowledgePoints', 'curriculumStandardItems', 'textbookChapters', 'examPoints', 'trendSummaries', 'mappingSuggestions')) {
        $case = @($report.cases)[0]
        if ($case.$requiredSection -lt 1) {
            throw "C002O report missing required eval section: $requiredSection"
        }
    }
}

if ($byId['C002P'].status -eq '已完成') {
    $c002pReport = Join-Path $repoRoot 'docs\evidence\c002p-model-budget-guard-report.json'
    if (-not (Test-Path -LiteralPath $c002pReport)) {
        throw "C002P is completed but report is missing: docs/evidence/c002p-model-budget-guard-report.json"
    }
    $report = Get-Content -LiteralPath $c002pReport -Raw | ConvertFrom-Json
    if ($report.status -ne 'pass' -or $report.realModelCallsDefault -ne $false -or $report.fullSourceExceedsDryRunLimits -ne $true) {
        throw "C002P report must pass with real model calls disabled and full source exceeding dry-run limits"
    }
    if ($report.fullExtractionRequiresHumanBudgetApproval -ne $true) {
        throw "C002P full extraction must require human budget approval"
    }
}

if ($c002q0.status -eq '已完成') {
    $c002q0Report = Join-Path $repoRoot 'docs\evidence\c002q0-outer-ai-readiness-report.json'
    if (-not (Test-Path -LiteralPath $c002q0Report)) {
        throw "C002Q0 is completed but report is missing: docs/evidence/c002q0-outer-ai-readiness-report.json"
    }
    $report = Get-Content -LiteralPath $c002q0Report -Raw | ConvertFrom-Json
    if ($report.status -ne 'pass' -or $report.allowProjectRuntimeRealModelCalls -ne $false -or $report.externalAiCallsInReadiness -ne 0) {
        throw "C002Q0 report must pass with project runtime real model calls disabled and zero readiness AI calls"
    }
    if ($report.noActiveWrite -ne $true -or $report.subagentRuntimeDependency -ne $false -or $report.productionEligible -ne $false) {
        throw "C002Q0 report must enforce no active write, no runtime subagent dependency, and production eligibility false"
    }
    if ($report.humanReviewRequired -ne $true -or $report.cacheHitRequired -ne $true) {
        throw "C002Q0 report must require human review and cache hit evidence"
    }
}

if ($c002q.status -eq '已完成') {
    $c002qReport = Join-Path $repoRoot 'docs\evidence\c002q-ai-extract-dry-run-report.json'
    if (-not (Test-Path -LiteralPath $c002qReport)) {
        throw "C002Q is completed but report is missing: docs/evidence/c002q-ai-extract-dry-run-report.json"
    }
    $report = Get-Content -LiteralPath $c002qReport -Raw | ConvertFrom-Json
    if ($report.status -ne 'pass' -or $report.allowRealModelCalls -ne $false -or $report.externalAiCalls -ne 0) {
        throw "C002Q report must pass with real model calls disabled and zero external AI calls"
    }
    if ($report.noActiveWrite -ne $true -or $report.productionEligible -ne $false -or $report.reviewStatus -ne 'pending_review') {
        throw "C002Q report must enforce no active write and pending_review non-production output"
    }
    if ($report.overwritesExistingC002K -ne $false -or $report.requiresHumanReview -ne $true) {
        throw "C002Q report must not overwrite C002K and must require human review"
    }
    if ($report.sample.sourceDocuments -gt 4 -or $report.sample.chunksTotal -gt 32 -or $report.sample.estimatedInputTokens -gt 120000) {
        throw "C002Q report exceeds dry-run sample budget"
    }
}

if ($c002t.status -eq '已完成') {
    $c002tReport = Join-Path $repoRoot 'docs\evidence\c002t-active-switch-report.json'
    if (-not (Test-Path -LiteralPath $c002tReport)) {
        throw "C002T is completed but report is missing: docs/evidence/c002t-active-switch-report.json"
    }
    $report = Get-Content -LiteralPath $c002tReport -Raw | ConvertFrom-Json
    if ($report.status -ne 'pass' -or $report.activationGuardPassed -ne $true) {
        throw "C002T report must pass active switch guard"
    }
    if ($report.before.activeAssets -lt 1 -and $report.after.activeAssets -lt 1) {
        throw "C002T report must show active imported assets"
    }
    if ($report.after.candidateAssets -ne 0 -or $report.after.pendingMappings -ne 0 -or $report.after.pendingMigrations -ne 0 -or $report.after.openReviewItems -ne 0) {
        throw "C002T report must show no pending candidate review blockers"
    }
}

if ($i008.status -eq '已完成') {
    $i008Contract = Join-Path $repoRoot 'tools\run-i008-teacher-simplification-contract.ps1'
    if (-not (Test-Path -LiteralPath $i008Contract)) {
        throw "I008 is completed but contract is missing: tools/run-i008-teacher-simplification-contract.ps1"
    }
    foreach ($pattern in @('普通教师', '不暴露', 'C002R', 'active', 'candidate', 'migration', 'rollback', 'draft_test', 'synthetic fixture', 'UI 合同')) {
        if ($i008.acceptance -notmatch $pattern) {
            throw "I008 acceptance missing simplification boundary: $pattern"
        }
    }
}

if ($i009.depends_on -ne 'I008') {
    throw "I009 must depend on I008 teacher simplification baseline"
}

if ($i010.depends_on -ne 'I009') {
    throw "I010 must depend on I009 teacher-visible terminology cleanup"
}

if ($o004b.depends_on -ne 'O004') {
    throw "O004B must depend on O004 fail-closed API guard"
}

$p001Dependencies = @($p001.depends_on -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($requiredDependency in @('O004B', 'O006', 'O007')) {
    if ($p001Dependencies -notcontains $requiredDependency) {
        throw "P001 must depend on $requiredDependency before live readiness"
    }
}

if ($i009.status -eq '已完成') {
    $i009Evidence = Join-Path $repoRoot 'docs\evidence\20260505-i009-teacher-visible-terminology.md'
    if (-not (Test-Path -LiteralPath $i009Evidence)) {
        throw "I009 is completed but evidence is missing: docs/evidence/20260505-i009-teacher-visible-terminology.md"
    }
    foreach ($pattern in @('draft/test', 'medium_hard', '0\.x', '状态枚举', '集中教师标签')) {
        if ($i009.acceptance -notmatch $pattern) {
            throw "I009 acceptance missing teacher terminology boundary: $pattern"
        }
    }
    if ($i009.verification -notmatch 'run-i008-teacher-simplification-contract') {
        throw "I009 verification must include the teacher simplification contract"
    }
}

if ($i010.status -eq '已完成') {
    $i010Evidence = Join-Path $repoRoot 'docs\evidence\20260505-i010-teacher-admin-shell-split.md'
    if (-not (Test-Path -LiteralPath $i010Evidence)) {
        throw "I010 is completed but evidence is missing: docs/evidence/20260505-i010-teacher-admin-shell-split.md"
    }
    foreach ($pattern in @('AdminGovernancePanels', 'admin', 'source', 'activation', 'knowledge', 'storage', 'guardrail')) {
        if ($i010.acceptance -notmatch $pattern) {
            throw "I010 acceptance missing admin shell split boundary: $pattern"
        }
    }
    if ($i010.verification -notmatch 'run-i008-teacher-simplification-contract') {
        throw "I010 verification must include the teacher simplification contract"
    }
}

if ($o004.status -eq '已完成') {
    foreach ($pattern in @('fail-closed', '/api/admin/\*', '/internal/ai/\*', '不代表角色和审计已完成')) {
        if ($o004.acceptance -notmatch $pattern) {
            throw "O004 acceptance missing fail-closed scope boundary: $pattern"
        }
    }
}

if ($p001.status -ne '待办' -and $o004b.status -ne '已完成') {
    throw "P001 cannot leave todo until O004B role/audit/admin UI authorization is complete"
}

$p0LiveCompleted = $rows | Where-Object {
    $_.phase -eq 'P0-live' -and $_.status -eq '已完成'
}
if (@($p0LiveCompleted).Count -gt 0 -and $o004b.status -ne '已完成') {
    $ids = ($p0LiveCompleted | Select-Object -ExpandProperty id) -join ','
    throw "P0-live tasks cannot be completed before O004B: $ids"
}

foreach ($pattern in @('subagent', '外层', '真实模型', 'no_active_write', '运行时依赖')) {
    if ($c002q0.acceptance -notmatch $pattern) {
        throw "C002Q0 acceptance missing orchestration boundary: $pattern"
    }
}

if ($c002.status -ne '已完成') {
    $blocked = $rows | Where-Object {
        $_.phase -in @('P3', 'P4', 'P5', 'P6') -and $_.status -eq '已完成'
    }
    if (@($blocked).Count -gt 0) {
        $productionCompleted = $blocked | Where-Object {
            $_.acceptance -notmatch 'draft|test|schema|接口|Evals|成本日志|人工审核|迁移建议|不接真实模型|不进入实现|synthetic|productionEligible=false|不具备生产资格|不等待正式|不依赖正式'
        }
        if (@($productionCompleted).Count -gt 0) {
            $ids = ($productionCompleted | Select-Object -ExpandProperty id) -join ','
            throw "production P3+ tasks cannot be completed before formal C002: $ids"
        }
    }
}

$futureDynamicTasks = $rows | Where-Object {
    $_.phase -in @('P4', 'P5', 'P6') -and $_.status -ne '已完成'
}
$missingDraftPlan = $futureDynamicTasks | Where-Object {
    $_.acceptance -notmatch 'draft|test|synthetic|动态|不等待正式|不要求正式|不使用真实|production'
}
if (@($missingDraftPlan).Count -gt 0) {
    $ids = ($missingDraftPlan | Select-Object -ExpandProperty id) -join ','
    throw "future P4+ tasks must state draft/test no-stop acceptance: $ids"
}

if ($c002.acceptance -notmatch '教师录入|导入|来源|教材|课程标准|真题|draft|迁移|替换|审核|active') {
    throw "C002 acceptance must preserve draft/test and teacher/source-derived formal upgrade semantics"
}

[ordered]@{
    status = 'pass'
    c002Status = $c002.status
    d001DependsOn = $d001.depends_on
    teacherSimplificationGate = 'I008/I009/I010'
    simplificationBlockersChecked = @('I008', 'I009', 'I010', 'O004B', 'P001')
    o004Status = $o004.status
    o004bStatus = $o004b.status
    p001DependsOn = $p001Dependencies
    productionDynamicAssetsBlockedUntilFormalC002 = ($c002.status -ne '已完成')
    draftTestSystemBuildAllowed = $true
    futureNoStopTasksChecked = @($futureDynamicTasks).Count
    noStopPolicy = if ($c002.status -eq '已完成') {
        'dynamic assets may still use candidate/review/rollback flow for future revisions after formal C002 activation'
    }
    else {
        'dynamic assets may use draft/test fixtures while production activation remains blocked'
    }
} | ConvertTo-Json

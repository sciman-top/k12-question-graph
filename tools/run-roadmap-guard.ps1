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
    'L001', 'L002', 'L003', 'L004', 'L005', 'L006', 'L007', 'M001', 'M002', 'M003', 'M004', 'M005', 'M006', 'N001', 'N002', 'N003', 'N004', 'N005', 'N006',
    'D001', 'D002', 'D003',
    'I008', 'I009', 'I010',
    'O004', 'O004B',
    'S001', 'S002', 'S003', 'S004', 'S005', 'S006', 'S007', 'S008', 'S009', 'S010', 'S011', 'S012',
    'REAL001', 'REAL002', 'REAL003', 'REAL004', 'REAL005', 'REAL006', 'REAL007', 'REAL008', 'REAL009', 'REAL010', 'REAL011', 'REAL012',
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
$l001 = $byId['L001']
$l002 = $byId['L002']
$l003 = $byId['L003']
$l004 = $byId['L004']
$l005 = $byId['L005']
$l006 = $byId['L006']
$l007 = $byId['L007']
$m001 = $byId['M001']
$m002 = $byId['M002']
$m003 = $byId['M003']
$m004 = $byId['M004']
$m005 = $byId['M005']
$m006 = $byId['M006']
$n001 = $byId['N001']
$n002 = $byId['N002']
$n003 = $byId['N003']
$n004 = $byId['N004']
$n005 = $byId['N005']
$n006 = $byId['N006']
$d001 = $byId['D001']
$i008 = $byId['I008']
$i009 = $byId['I009']
$i010 = $byId['I010']
$o004 = $byId['O004']
$o004b = $byId['O004B']
$s001 = $byId['S001']
$s002 = $byId['S002']
$s003 = $byId['S003']
$s004 = $byId['S004']
$s005 = $byId['S005']
$s006 = $byId['S006']
$s007 = $byId['S007']
$s008 = $byId['S008']
$s009 = $byId['S009']
$s010 = $byId['S010']
$s011 = $byId['S011']
$s012 = $byId['S012']
$real001 = $byId['REAL001']
$real002 = $byId['REAL002']
$real003 = $byId['REAL003']
$real004 = $byId['REAL004']
$real005 = $byId['REAL005']
$real006 = $byId['REAL006']
$real007 = $byId['REAL007']
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

if ($l001.depends_on -ne 'H003') {
    throw "L001 must depend on H003 teacher efficiency baseline retest"
}

if ($l001.status -eq '已完成') {
    $l001Evidence = Join-Path $repoRoot 'docs\evidence\20260505-l001-real-model-admission-card.md'
    if (-not (Test-Path -LiteralPath $l001Evidence)) {
        throw "L001 is completed but evidence is missing: docs/evidence/20260505-l001-real-model-admission-card.md"
    }
    if ($l001.acceptance -notmatch '数据边界|预算|人工审核|外部传输|no active write') {
        throw "L001 acceptance must lock data boundary, budget, human review, external transfer and no active write"
    }
    if ($l001.verification -notmatch 'run-l001-real-model-admission-card') {
        throw "L001 verification must include run-l001-real-model-admission-card.ps1"
    }
}

if ($l007.depends_on -ne 'L001') {
    throw "L007 must depend on L001 real model admission card"
}

if ($l002.depends_on -ne 'L007') {
    throw "L002 must depend on L007 LLM security red-team gate"
}

if ($l002.status -eq '已完成') {
    $l002Evidence = Join-Path $repoRoot 'docs\evidence\20260505-l002-real-ai-extract-pilot.md'
    if (-not (Test-Path -LiteralPath $l002Evidence)) {
        throw "L002 is completed but evidence is missing: docs/evidence/20260505-l002-real-ai-extract-pilot.md"
    }
    if ($l002.acceptance -notmatch 'cache-hit|candidate pending_review|token cost|不覆盖 C002K') {
        throw "L002 acceptance must keep sample cache-hit, pending_review, token cost, and no C002K overwrite"
    }
    if ($l002.verification -notmatch 'run-l002-real-ai-extract-pilot') {
        throw "L002 verification must include run-l002-real-ai-extract-pilot.ps1"
    }
}

if ($l003.depends_on -ne 'J006;L001') {
    throw "L003 must depend on J006 and L001"
}

if ($l003.status -eq '已完成') {
    $l003Evidence = Join-Path $repoRoot 'docs\evidence\20260505-l003-ai-cut-candidate-pilot.md'
    if (-not (Test-Path -LiteralPath $l003Evidence)) {
        throw "L003 is completed but evidence is missing: docs/evidence/20260505-l003-ai-cut-candidate-pilot.md"
    }
    if ($l003.acceptance -notmatch '只产候选|低置信度进入确认队列|原文件可接管') {
        throw "L003 acceptance must keep candidate-only and manual takeover boundaries"
    }
    if ($l003.verification -notmatch 'run-l003-ai-cut-candidate-pilot') {
        throw "L003 verification must include run-l003-ai-cut-candidate-pilot.ps1"
    }
}

if ($l004.depends_on -ne 'K001;L001') {
    throw "L004 must depend on K001 and L001"
}

if ($l004.status -eq '已完成') {
    $l004Evidence = Join-Path $repoRoot 'docs\evidence\20260505-l004-knowledge-tagging-suggestion-pilot.md'
    if (-not (Test-Path -LiteralPath $l004Evidence)) {
        throw "L004 is completed but evidence is missing: docs/evidence/20260505-l004-knowledge-tagging-suggestion-pilot.md"
    }
    if ($l004.acceptance -notmatch '只作为建议|绑定 active 知识版本|FeedbackEvent') {
        throw "L004 acceptance must keep suggestion-only and active-version boundaries"
    }
    if ($l004.verification -notmatch 'run-l004-knowledge-tagging-suggestion-pilot') {
        throw "L004 verification must include run-l004-knowledge-tagging-suggestion-pilot.ps1"
    }
}

if ($l005.depends_on -ne 'L001') {
    throw "L005 must depend on L001"
}

if ($l005.status -eq '已完成') {
    $l005Evidence = Join-Path $repoRoot 'docs\evidence\20260505-l005-answer-verification-quality-pilot.md'
    if (-not (Test-Path -LiteralPath $l005Evidence)) {
        throw "L005 is completed but evidence is missing: docs/evidence/20260505-l005-answer-verification-quality-pilot.md"
    }
    if ($l005.acceptance -notmatch '保留来源和置信度|不自动覆盖教师答案') {
        throw "L005 acceptance must keep source-confidence and no-auto-override boundaries"
    }
    if ($l005.verification -notmatch 'run-l005-answer-verification-quality-pilot') {
        throw "L005 verification must include run-l005-answer-verification-quality-pilot.ps1"
    }
}

if ($l006.depends_on -ne 'L002') {
    throw "L006 must depend on L002"
}

if ($l006.status -eq '已完成') {
    $l006Evidence = Join-Path $repoRoot 'docs\evidence\20260505-l006-cost-cache-batch-dashboard-pilot.md'
    if (-not (Test-Path -LiteralPath $l006Evidence)) {
        throw "L006 is completed but evidence is missing: docs/evidence/20260505-l006-cost-cache-batch-dashboard-pilot.md"
    }
    if ($l006.acceptance -notmatch '任务成本 cache hit 模型路由和异常失败原因') {
        throw "L006 acceptance must keep cost/cache/routing/failure boundaries"
    }
    if ($l006.verification -notmatch 'run-l006-cost-cache-batch-dashboard-pilot') {
        throw "L006 verification must include run-l006-cost-cache-batch-dashboard-pilot.ps1"
    }
}

if ($l007.status -eq '已完成') {
    $l007Evidence = Join-Path $repoRoot 'docs\evidence\20260505-l007-llm-security-red-team-gate.md'
    if (-not (Test-Path -LiteralPath $l007Evidence)) {
        throw "L007 is completed but evidence is missing: docs/evidence/20260505-l007-llm-security-red-team-gate.md"
    }
    if ($l007.acceptance -notmatch 'prompt injection|sensitive information disclosure|insecure output handling|supply chain|vector/embedding weakness|excessive agency') {
        throw "L007 acceptance must cover OWASP/NIST risk set"
    }
    if ($l007.verification -notmatch 'run-l007-llm-security-red-team-gate') {
        throw "L007 verification must include run-l007-llm-security-red-team-gate.ps1"
    }
}

if ($m001.depends_on -ne 'K001') {
    throw "M001 must depend on K001"
}

if ($m001.status -eq '已完成') {
    $m001Evidence = Join-Path $repoRoot 'docs\evidence\20260505-m001-paper-basket-structure-contract.md'
    if (-not (Test-Path -LiteralPath $m001Evidence)) {
        throw "M001 is completed but evidence is missing: docs/evidence/20260505-m001-paper-basket-structure-contract.md"
    }
    if ($m001.acceptance -notmatch '题篮 试卷结构 分值 题号 小问和版本引用可保存和复现') {
        throw "M001 acceptance must keep paper basket/structure/version-reference boundary"
    }
    if ($m001.verification -notmatch 'run-m001-paper-basket-structure-contract') {
        throw "M001 verification must include run-m001-paper-basket-structure-contract.ps1"
    }
}

if ($m002.depends_on -ne 'M001;L001') { throw "M002 must depend on M001 and L001" }
if ($m002.status -eq '已完成') {
  $p = Join-Path $repoRoot 'docs\evidence\20260505-m002-nl-to-blueprint-production-chain.md'
  if(-not (Test-Path -LiteralPath $p)){ throw "M002 evidence missing" }
  if($m002.verification -notmatch 'run-m002-nl-to-blueprint-production-chain'){ throw "M002 verification missing contract script" }
}

if ($m003.depends_on -ne 'M001') { throw "M003 must depend on M001" }
if ($m003.status -eq '已完成') {
  $p = Join-Path $repoRoot 'docs\evidence\20260505-m003-replacement-production-constraints.md'
  if(-not (Test-Path -LiteralPath $p)){ throw "M003 evidence missing" }
  if($m003.verification -notmatch 'run-m003-replacement-production-constraints'){ throw "M003 verification missing contract script" }
}

if ($m004.depends_on -ne 'M003') { throw "M004 must depend on M003" }
if ($m004.status -eq '已完成') {
  $p = Join-Path $repoRoot 'docs\evidence\20260505-m004-export-preflight-contract.md'
  if(-not (Test-Path -LiteralPath $p)){ throw "M004 evidence missing" }
  if($m004.verification -notmatch 'run-m004-export-preflight-contract'){ throw "M004 verification missing contract script" }
}

if ($m005.depends_on -ne 'M004') { throw "M005 must depend on M004" }
if ($m005.status -eq '已完成') {
  $p = Join-Path $repoRoot 'docs\evidence\20260505-m005-export-regression-extended.md'
  if(-not (Test-Path -LiteralPath $p)){ throw "M005 evidence missing" }
  if($m005.verification -notmatch 'run-m005-export-regression-extended'){ throw "M005 verification missing contract script" }
}

if ($m006.depends_on -ne 'M005') { throw "M006 must depend on M005" }
if ($m006.status -eq '已完成') {
  $p = Join-Path $repoRoot 'docs\evidence\20260505-m006-ten-minute-paper-workflow-acceptance.md'
  if(-not (Test-Path -LiteralPath $p)){ throw "M006 evidence missing" }
  if($m006.verification -notmatch 'run-m006-ten-minute-paper-workflow-acceptance'){ throw "M006 verification missing contract script" }
}

if ($n001.depends_on -ne 'H003') { throw "N001 must depend on H003" }
if ($n001.status -eq '已完成') {
  $p = Join-Path $repoRoot 'docs\evidence\20260505-n001-real-privacy-boundary-admission.md'
  if(-not (Test-Path -LiteralPath $p)){ throw "N001 evidence missing" }
  if($n001.verification -notmatch 'run-n001-real-privacy-boundary-admission'){ throw "N001 verification missing contract script" }
}

if ($n002.depends_on -ne 'N001') { throw "N002 must depend on N001" }
if ($n002.status -eq '已完成') {
  $p = Join-Path $repoRoot 'docs\evidence\20260505-n002-excel-template-reuse.md'
  if(-not (Test-Path -LiteralPath $p)){ throw "N002 evidence missing" }
  if($n002.verification -notmatch 'run-n002-excel-template-reuse'){ throw "N002 verification missing contract script" }
}

if ($n003.depends_on -ne 'M001;N002') { throw "N003 must depend on M001 and N002" }
if ($n003.status -eq '已完成') {
  $p = Join-Path $repoRoot 'docs\evidence\20260505-n003-item-score-mapping-workbench.md'
  if(-not (Test-Path -LiteralPath $p)){ throw "N003 evidence missing" }
  if($n003.verification -notmatch 'run-n003-item-score-mapping-workbench'){ throw "N003 verification missing contract script" }
}

if ($n004.depends_on -ne 'N003') { throw "N004 must depend on N003" }
if ($n004.status -eq '已完成') {
  $p = Join-Path $repoRoot 'docs\evidence\20260505-n004-class-commentary-report-mvp.md'
  if(-not (Test-Path -LiteralPath $p)){ throw "N004 evidence missing" }
  if($n004.verification -notmatch 'run-n004-class-commentary-report-mvp'){ throw "N004 verification missing contract script" }
}

if ($n005.depends_on -ne 'N004') { throw "N005 must depend on N004" }
if ($n005.status -eq '已完成') {
  $p = Join-Path $repoRoot 'docs\evidence\20260505-n005-tiered-practice-draft-test.md'
  if(-not (Test-Path -LiteralPath $p)){ throw "N005 evidence missing" }
  if($n005.verification -notmatch 'run-n005-tiered-practice-draft-test'){ throw "N005 verification missing contract script" }
}

if ($n006.depends_on -ne 'N001') { throw "N006 must depend on N001" }
if ($n006.status -eq '已完成') {
  $p = Join-Path $repoRoot 'docs\evidence\20260505-n006-pre-pilot-security-audit.md'
  if(-not (Test-Path -LiteralPath $p)){ throw "N006 evidence missing" }
  if($n006.verification -notmatch 'run-n006-pre-pilot-security-audit'){ throw "N006 verification missing contract script" }
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

$expectedS0Dependencies = [ordered]@{
    S001 = 'O007'
    S002 = 'S001'
    S003 = 'S002'
    S004 = 'S003'
    S005 = 'S004'
    S006 = 'S005'
    S007 = 'S006;L007'
    S008 = 'S007;K001'
    S009 = 'S008'
    S010 = 'S009'
    S011 = 'S010;N001'
    S012 = 'S011'
}

foreach ($entry in $expectedS0Dependencies.GetEnumerator()) {
    $actual = $byId[$entry.Key].depends_on
    if ($actual -ne $entry.Value) {
        throw "$($entry.Key) must depend on $($entry.Value); actual: $actual"
    }
}

$p001Dependencies = @($p001.depends_on -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($requiredDependency in @('S012', 'O004B', 'O006', 'O007')) {
    if ($p001Dependencies -notcontains $requiredDependency) {
        throw "P001 must depend on $requiredDependency before live readiness"
    }
}

if ($p001Dependencies -notcontains 'REAL012') {
    throw "P001 must depend on REAL012 real production-grade question flow closure before live readiness"
}

$expectedRealDependencies = [ordered]@{
    REAL002 = 'REAL001'
    REAL003 = 'REAL002'
    REAL004 = 'REAL001'
    REAL005 = 'REAL002;REAL003;REAL004'
    REAL006 = 'REAL004'
    REAL007 = 'REAL006'
    REAL008 = 'REAL006'
    REAL009 = 'REAL007'
    REAL010 = 'REAL007'
    REAL011 = 'REAL008;REAL009;REAL010'
    REAL012 = 'REAL011'
}

foreach ($entry in $expectedRealDependencies.GetEnumerator()) {
    $actual = $byId[$entry.Key].depends_on
    if ($actual -ne $entry.Value) {
        throw "$($entry.Key) must depend on $($entry.Value); actual: $actual"
    }
}

if ($real001.status -eq '已完成') {
    $real001Report = Join-Path $repoRoot 'docs\evidence\20260512-guangzhou-2015-real-ingest-slice-report.json'
    if (-not (Test-Path -LiteralPath $real001Report)) {
        throw "REAL001 is completed but evidence is missing: docs/evidence/20260512-guangzhou-2015-real-ingest-slice-report.json"
    }
    $report = Get-Content -LiteralPath $real001Report -Raw | ConvertFrom-Json
    if ($report.status -ne 'pass' -or $report.mode -ne 'apply') {
        throw "REAL001 report must be an applied pass, got status=$($report.status) mode=$($report.mode)"
    }
    if ($report.after.questionCount -ne 18 -or $report.after.cutCandidateCount -ne 18 -or $report.after.openReviewQueueCount -ne 18) {
        throw "REAL001 report must prove 18 questions, 18 cut candidates, and 18 open review items"
    }
    if ($report.verification.allHaveAnswers -ne $true -or $report.verification.allHaveKnowledgeTags -ne $true -or $report.verification.allRequireTeacherReview -ne $true) {
        throw "REAL001 report must prove answer/tag presence and teacher review boundary"
    }
}

if ($real002.status -eq '已完成') {
    $real002Report = Join-Path $repoRoot 'docs\evidence\20260512-guangzhou-2015-visual-region-slice-report.json'
    if (-not (Test-Path -LiteralPath $real002Report)) {
        throw "REAL002 is completed but evidence is missing: docs/evidence/20260512-guangzhou-2015-visual-region-slice-report.json"
    }
    $report = Get-Content -LiteralPath $real002Report -Raw | ConvertFrom-Json
    if ($report.status -ne 'pass' -or $report.mode -ne 'apply') {
        throw "REAL002 report must be an applied pass, got status=$($report.status) mode=$($report.mode)"
    }
    $questionNumbers = @($report.after.questionNumbers | ForEach-Object { [int] $_ })
    $expectedNumbers = @(19, 20, 21, 22, 23, 24)
    if ((Compare-Object -ReferenceObject $expectedNumbers -DifferenceObject $questionNumbers).Count -ne 0) {
        throw "REAL002 report must prove visual questions 19-24"
    }
    if ($report.after.questionCount -ne 6 -or $report.after.sourceRegionCount -lt 17 -or $report.after.questionAssetCount -lt 5 -or $report.after.openReviewQueueCount -ne 6) {
        throw "REAL002 report must prove 6 questions, at least 17 source regions, at least 5 question assets, and 6 open review items"
    }
    if ($report.verification.questionRangeComplete -ne $true -or $report.verification.allHaveAnswers -ne $true -or $report.verification.allHaveKnowledgeTags -ne $true -or $report.verification.hasQuestionAssetsForVisualQuestions -ne $true) {
        throw "REAL002 report must prove range, answers, tags, and visual question assets"
    }
}

if ($real003.status -eq '已完成') {
    $real003Report = Join-Path $repoRoot 'docs\evidence\20260514-real003-guangzhou-physics-year-batch-ingest-report.json'
    if (-not (Test-Path -LiteralPath $real003Report)) {
        throw "REAL003 is completed but evidence is missing: docs/evidence/20260514-real003-guangzhou-physics-year-batch-ingest-report.json"
    }
    $report = Get-Content -LiteralPath $real003Report -Raw | ConvertFrom-Json
    if ($report.status -ne 'dry_run_pass' -or $report.dryRunOnly -ne $true -or $report.activeWrite -ne $false) {
        throw "REAL003 report must be dry_run_pass with no active write"
    }
    if ($report.externalAiCalls -ne 0 -or $report.realStudentDataUsed -ne $false) {
        throw "REAL003 report must prove zero external AI calls and no real student data"
    }
    if ($report.totals.questions -ne 210 -or $report.totals.answers -ne 210 -or $report.totals.dbSourceDocumentsWithHash -lt 30) {
        throw "REAL003 report must prove 210 questions, 210 answers, and source hash coverage"
    }
    if (@($report.blockers).Count -ne 0) {
        throw "REAL003 report must have no blockers"
    }
}

if ($real004.status -eq '已完成') {
    $real004Report = Join-Path $repoRoot 'docs\evidence\20260512-real004-guangzhou-2015-review-smoke-report.json'
    if (-not (Test-Path -LiteralPath $real004Report)) {
        throw "REAL004 is completed but evidence is missing: docs/evidence/20260512-real004-guangzhou-2015-review-smoke-report.json"
    }
    $report = Get-Content -LiteralPath $real004Report -Raw | ConvertFrom-Json
    if ($report.status -ne 'pass' -or $report.initialOpenReviewItems -ne 24 -or $report.restoredOpenReviewItems -ne 24) {
        throw "REAL004 report must pass and restore the 24-item review baseline"
    }
    if ($report.verification.canFilterGuangzhou2015Queue -ne $true -or $report.verification.canLoadQuestionSources -ne $true -or $report.verification.canConfirmWithAudit -ne $true -or $report.verification.canReturnWithAudit -ne $true) {
        throw "REAL004 report must prove queue filter, source load, confirm audit, and return audit"
    }
    if ($report.verification.canSubmitTeacherRevisionWithAudit -ne $true) {
        throw "REAL004 report must prove teacher-edited revision is persisted with audit"
    }
}

if ($real006.status -eq '已完成') {
    $real004Report = Join-Path $repoRoot 'docs\evidence\20260512-real004-guangzhou-2015-review-smoke-report.json'
    if (-not (Test-Path -LiteralPath $real004Report)) {
        throw "REAL006 is completed but REAL004 source screenshot evidence is missing"
    }
    $report = Get-Content -LiteralPath $real004Report -Raw | ConvertFrom-Json
    if ($report.verification.allReviewItemsHaveSourceScreenshotUrls -ne $true -or $report.verification.allReviewItemsHavePageScreenshotUrls -ne $true) {
        throw "REAL006 requires every 2015 review item to have source and page screenshot URLs"
    }
    if ([double]$report.sourceScreenshotCoverage.minRestoredImageUrlCount -lt 2 -or [double]$report.sourceScreenshotCoverage.minRestoredPageImageUrlCount -lt 2) {
        throw "REAL006 requires at least two restored source/page image URLs per question"
    }
}

if ($real007.status -eq '已完成') {
    $real007Report = Join-Path $repoRoot 'docs\evidence\20260516-real007-guangzhou-2015-layout-quality-report.json'
    if (-not (Test-Path -LiteralPath $real007Report)) {
        throw "REAL007 is completed but evidence is missing: docs/evidence/20260516-real007-guangzhou-2015-layout-quality-report.json"
    }
    $report = Get-Content -LiteralPath $real007Report -Raw | ConvertFrom-Json
    if ($report.status -ne 'pass' -or $report.missingScreenshotCount -ne 0 -or $report.placeholderLikeScreenshotCount -ne 0 -or $report.noiseOverlapCount -ne 0) {
        throw "REAL007 report must pass with no missing screenshots, placeholder screenshots, or noise overlaps"
    }
    if (@($report.missingRequiredAssetQuestionNos).Count -ne 0 -or $null -eq $report.latestRecropAudit) {
        throw "REAL007 report must prove required figure assets and recrop audit"
    }
}

if ($real008.status -eq '已完成') {
    $real008Report = Join-Path $repoRoot 'docs\evidence\20260518-real008-question-asset-smoke-report.json'
    if (-not (Test-Path -LiteralPath $real008Report)) {
        throw "REAL008 is completed but evidence is missing: docs/evidence/20260518-real008-question-asset-smoke-report.json"
    }
    $report = Get-Content -LiteralPath $real008Report -Raw | ConvertFrom-Json
    if ($report.status -ne 'pass') {
        throw "REAL008 report must pass"
    }
    if ($report.cardProbe.beforeAssociation.hasImage -ne $false -or $report.cardProbe.beforeAssociation.assetCount -ne 0) {
        throw "REAL008 must prove cards do not infer hasImage from source screenshots alone"
    }
    if ($report.cardProbe.afterAssociation.hasImage -ne $true -or $report.cardProbe.afterAssociation.assetCount -lt 1) {
        throw "REAL008 must prove card hasImage/assetCount come from associated question_assets"
    }
    if ($report.cardProbe.afterUnlink.hasImage -ne $false -or $report.cardProbe.afterUnlink.assetCount -ne 0) {
        throw "REAL008 must prove unlink removes card hasImage/assetCount"
    }
    if ($report.detailProbe.assetCount -lt 1 -or [string]::IsNullOrWhiteSpace([string]$report.detailProbe.sourceRegionScreenshotUrl)) {
        throw "REAL008 must prove question detail exposes asset screenshot URL"
    }
    if ($report.sourceProbe.assetRegionType -ne 'question_asset' -or $report.sourceProbe.assetScreenshotStatusCode -ne 200) {
        throw "REAL008 must prove source review returns a renderable question_asset region"
    }
    if ([string]::IsNullOrWhiteSpace([string]$report.auditIds.associate) -or [string]::IsNullOrWhiteSpace([string]$report.auditIds.unlink) -or [string]::IsNullOrWhiteSpace([string]$report.auditIds.reassociate)) {
        throw "REAL008 must prove associate, unlink, and reassociate audits"
    }
}

if ($real009.status -eq '已完成') {
    $real009Report = Join-Path $repoRoot 'docs\evidence\20260518-real009-table-structure-smoke-report.json'
    if (-not (Test-Path -LiteralPath $real009Report)) {
        throw "REAL009 is completed but evidence is missing: docs/evidence/20260518-real009-table-structure-smoke-report.json"
    }
    $report = Get-Content -LiteralPath $real009Report -Raw | ConvertFrom-Json
    if ($report.status -ne 'pass') {
        throw "REAL009 report must pass"
    }
    if ($report.tableStructure.columnCount -lt 1 -or $report.tableStructure.rowCount -lt 1 -or [string]::IsNullOrWhiteSpace([string]$report.tableStructure.caption)) {
        throw "REAL009 must prove table columns, rows, and caption are structured"
    }
    if ([string]::IsNullOrWhiteSpace([string]$report.tableStructure.sourceRegionId) -or [double]$report.tableStructure.confidence -ge 0.8 -or $report.tableStructure.reviewStatus -ne 'pending_review') {
        throw "REAL009 must prove source region, low confidence, and pending review status"
    }
    if ($report.cardProbe.hasTable -ne $true -or $report.cardProbe.hasImage -ne $false -or $report.cardProbe.assetCount -ne 0) {
        throw "REAL009 must prove table blocks are searchable as tables and not misclassified as image assets"
    }
    if ($report.sourceProbe.tableRegionType -ne 'question_table' -or $report.sourceProbe.tableScreenshotStatusCode -ne 200) {
        throw "REAL009 must prove table source screenshot is renderable"
    }
    if ($report.reviewQueueProbe.reviewType -ne 'question_table_block_review' -or $report.reviewQueueProbe.requiredAction -ne 'review_table_structure') {
        throw "REAL009 must prove low-confidence table review queue routing"
    }
}

if ($real010.status -eq '已完成') {
    $real010Report = Join-Path $repoRoot 'docs\evidence\20260518-real010-formula-fidelity-smoke-report.json'
    if (-not (Test-Path -LiteralPath $real010Report)) {
        throw "REAL010 is completed but evidence is missing: docs/evidence/20260518-real010-formula-fidelity-smoke-report.json"
    }
    $report = Get-Content -LiteralPath $real010Report -Raw | ConvertFrom-Json
    if ($report.status -ne 'pass') {
        throw "REAL010 report must pass"
    }
    if ($report.officeFormula.sourceFormat -ne 'omml' -or $report.officeFormula.ommlPreserved -ne $true -or $report.officeFormula.mathmlPresent -ne $true -or $report.officeFormula.exportPreference -ne 'omml') {
        throw "REAL010 must prove Office formulas preserve OMML and derivative formats"
    }
    if ($report.scannedFormula.sourceFormat -ne 'scanned_formula_candidate' -or $report.scannedFormula.reviewStatus -ne 'pending_review' -or [double]$report.scannedFormula.confidence -ge 0.9 -or $report.scannedFormula.fallbackImageStatusCode -ne 200) {
        throw "REAL010 must prove scanned formulas keep fallback image and pending review"
    }
    if ($report.cardProbe.hasFormula -ne $true -or $report.cardProbe.hasImage -ne $false) {
        throw "REAL010 must prove formula blocks are searchable as formulas and not misclassified as question images"
    }
    if ($report.reviewQueueProbe.reviewType -ne 'question_formula_block_review' -or $report.reviewQueueProbe.requiredAction -ne 'review_formula_structure') {
        throw "REAL010 must prove scanned formula review queue routing"
    }
}

if ($real011.status -eq '已完成') {
    $real011Report = Join-Path $repoRoot 'docs\evidence\20260518-real011-question-edit-smoke-report.json'
    if (-not (Test-Path -LiteralPath $real011Report)) {
        throw "REAL011 is completed but evidence is missing: docs/evidence/20260518-real011-question-edit-smoke-report.json"
    }
    $report = Get-Content -LiteralPath $real011Report -Raw | ConvertFrom-Json
    if ($report.status -ne 'pass') {
        throw "REAL011 report must pass"
    }
    if ($report.questionEdit.questionType -ne 'calculation' -or [double]$report.questionEdit.defaultScore -ne 6 -or [double]$report.questionEdit.difficultyEstimated -lt 0.7 -or $report.questionEdit.status -ne 'pending_review') {
        throw "REAL011 must prove question type, score, difficulty, and status editing"
    }
    if ([string]::IsNullOrWhiteSpace([string]$report.questionEdit.editedStem) -or $report.questionEdit.blockCount -lt 2 -or [string]::IsNullOrWhiteSpace([string]$report.questionEdit.answer) -or [string]::IsNullOrWhiteSpace([string]$report.questionEdit.solution)) {
        throw "REAL011 must prove stem, answer, solution, and block edits"
    }
    if ($report.sourceRegionEdit.regionType -ne 'question_stem_revised' -or [string]::IsNullOrWhiteSpace([string]$report.sourceRegionEdit.auditId)) {
        throw "REAL011 must prove source region recrop edit and audit"
    }
    if ([string]::IsNullOrWhiteSpace([string]$report.auditProbe.questionRevisionAuditId) -or $report.auditProbe.questionAuditDecision -ne 'question_updated') {
        throw "REAL011 must prove question revision audit"
    }
}

if ($real012.status -eq '已完成') {
    $real012Report = Join-Path $repoRoot 'docs\evidence\20260518-real012-production-flow-quality-report.json'
    if (-not (Test-Path -LiteralPath $real012Report)) {
        throw "REAL012 is completed but evidence is missing: docs/evidence/20260518-real012-production-flow-quality-report.json"
    }
    $report = Get-Content -LiteralPath $real012Report -Raw | ConvertFrom-Json
    if ($report.status -ne 'pass') {
        throw "REAL012 report must pass"
    }
    if (@($report.searchProbe.selectedQuestionNos).Count -lt 3 -or $report.searchProbe.hasImageCount -lt 3) {
        throw "REAL012 must prove real question search returns ordered image-backed question cards"
    }
    if ($report.paperBasket.itemCount -lt 3 -or [string]::IsNullOrWhiteSpace([string]$report.paperBasket.id)) {
        throw "REAL012 must prove real questions enter a paper basket"
    }
    if ($report.exportPreflight.status -ne 'ready_for_review' -or $report.exportPreflight.summary.answerReadyCount -lt 3 -or $report.exportPreflight.summary.authorizedSourceCount -lt 3) {
        throw "REAL012 must prove export preflight is ready for the reviewed real sample"
    }
    if ($report.artifact.status -ne 'pass' -or [string]::IsNullOrWhiteSpace([string]$report.artifact.manifestPath)) {
        throw "REAL012 must prove Word/PDF draft artifacts are generated"
    }
    if ($report.analysis.status -ne 'ready' -or $report.analysis.allowAiDraftText -ne $false -or $report.analysis.writesProductionHistory -ne $false -or $report.analysis.weakKnowledgePointCount -lt 1) {
        throw "REAL012 must prove analysis references mapped real questions without AI draft text or formal history writes"
    }
    if ($report.qualityReport.closureStatus -ne 'not_closed' -or $report.qualityReport.metrics.questionCount -lt 24 -or $report.qualityReport.metrics.pendingManualItemCount -lt 1) {
        throw "REAL012 must prove per-paper quality report and keep full closure not_closed while manual items remain"
    }
    if ($report.real005ClosureStatus -ne 'not_closed') {
        throw "REAL012 must keep REAL005 full 2015-2025 closure status not_closed"
    }
}

$real005Guard = Join-Path $PSScriptRoot 'run-real005-guangzhou-2015-2025-closure-standard.ps1'
if (-not (Test-Path -LiteralPath $real005Guard)) {
    throw "REAL005 closure standard guard is missing"
}
$real005Report = & $real005Guard | ConvertFrom-Json
if ($real005.status -ne '已完成' -and $real005Report.closureStatus -ne 'not_closed') {
    throw "REAL005 must remain not_closed until backlog is completed; got $($real005Report.closureStatus)"
}
if ($real005.status -eq '已完成' -and $real005Report.status -ne 'pass') {
    throw "REAL005 completed status requires the closure standard guard itself to pass"
}
if ($real005Report.closureStatus -eq 'closed' -and $real005Report.fullClosureAllowed -ne $true) {
    throw "REAL005 closed status must set fullClosureAllowed=true"
}

$automationFirstGuard = Join-Path $PSScriptRoot 'run-automation-first-feature-contract-guard.ps1'
if (-not (Test-Path -LiteralPath $automationFirstGuard)) {
    throw "automation-first feature contract guard is missing"
}
& $automationFirstGuard | Out-Null

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

if ($p001.status -ne '待办' -and $s012.status -ne '已完成') {
    throw "P001 cannot leave todo until S012 productization end-to-end rehearsal is complete"
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
    automationFirstGate = 'tasks/automation-first-contract.csv'
    s0ProductizationGate = 'S001-S012'
    realPaperGate = 'REAL001'
    realFullClosureGate = 'REAL005'
    realFullClosureStatus = $real005Report.closureStatus
    s0Statuses = @($s001, $s002, $s003, $s004, $s005, $s006, $s007, $s008, $s009, $s010, $s011, $s012) | ForEach-Object {
        [ordered]@{
            id = $_.id
            status = $_.status
            depends_on = $_.depends_on
        }
    }
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

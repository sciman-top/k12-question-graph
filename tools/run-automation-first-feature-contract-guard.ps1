param(
    [string] $ContractPath = 'tasks/automation-first-contract.csv',
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $S0PlanPath = 'tasks/productization-s0-execution-plan.csv',
    [string] $FeatureAdmissionPath = 'docs/25_FeatureAdmissionCriteria.md',
    [string] $RoadmapPath = 'docs/19_Roadmap.md',
    [string] $TaskBreakdownPath = 'docs/20_TaskBreakdown.md',
    [string] $TechnologyStackPath = 'docs/04_TechnologyStack.md',
    [string] $ImportPipelinePath = 'docs/07_Document_AI_ImportPipeline.md',
    [string] $ProductizationPlanPath = 'docs/99_ProductizationFullRoadmapAndTaskPlan.md',
    [string] $ProductizationRoadmapPath = 'tasks/productization-roadmap.csv',
    [string] $PrdPath = 'docs/01_PRD.md',
    [string] $ReadmePath = 'README.md',
    [string] $JsonReportPath = 'docs/evidence/20260508-automation-first-feature-contract-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Resolve-RepoPath([string] $Path) {
    return Join-Path $repoRoot $Path
}

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

$contractFullPath = Resolve-RepoPath $ContractPath
$backlogFullPath = Resolve-RepoPath $BacklogPath
$s0PlanFullPath = Resolve-RepoPath $S0PlanPath
$jsonFullPath = Resolve-RepoPath $JsonReportPath

foreach ($path in @(
    $contractFullPath,
    $backlogFullPath,
    $s0PlanFullPath,
    (Resolve-RepoPath $FeatureAdmissionPath),
    (Resolve-RepoPath $RoadmapPath),
    (Resolve-RepoPath $TaskBreakdownPath),
    (Resolve-RepoPath $TechnologyStackPath),
    (Resolve-RepoPath $ImportPipelinePath),
    (Resolve-RepoPath $ProductizationPlanPath),
    (Resolve-RepoPath $ProductizationRoadmapPath),
    (Resolve-RepoPath $PrdPath),
    (Resolve-RepoPath $ReadmePath)
)) {
    Assert-True (Test-Path -LiteralPath $path) "required automation-first file missing: $path"
}

$contractRows = @(Import-Csv -LiteralPath $contractFullPath -Encoding UTF8)
$backlogRows = @(Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8)
$s0Rows = @(Import-Csv -LiteralPath $s0PlanFullPath -Encoding UTF8)

Assert-True ($contractRows.Count -gt 0) 'automation-first contract must not be empty'

$requiredColumns = @(
    'task_id',
    'scope',
    'deterministic_precheck',
    'dedicated_surface',
    'ai_agent_allowed_scope',
    'exception_policy',
    'evidence_command'
)

foreach ($column in $requiredColumns) {
    Assert-True ($contractRows[0].PSObject.Properties.Name -contains $column) "automation-first contract missing column: $column"
}

$contractById = @{}
foreach ($row in $contractRows) {
    Assert-True (-not [string]::IsNullOrWhiteSpace($row.task_id)) 'automation-first contract row has blank task_id'
    Assert-True (-not $contractById.ContainsKey($row.task_id)) "duplicate automation-first contract task_id: $($row.task_id)"
    $contractById[$row.task_id] = $row

    foreach ($column in $requiredColumns) {
        Assert-True (-not [string]::IsNullOrWhiteSpace($row.$column)) "automation-first row $($row.task_id) missing $column"
    }

    Assert-True ($row.deterministic_precheck -match 'rule|script|schema|SQL|hash|parser|adapter|contract|guard|API|UI|Excel|privacy|fixture|manifest|backup|typed|PostgreSQL|evidence|source|rules|checks|validation|golden|query|metric|baseline|checklist|classification|authorization|permission|boundary|field|diff|latency|throughput|sample|demand|responsibility|procurement|stale') "automation-first row $($row.task_id) must name deterministic checks"
    Assert-True ($row.dedicated_surface -match 'script|API|UI|adapter|service|guard|contract|template|runbook|dashboard|workflow|gate|client|checklist|report|evidence|typed|preflight') "automation-first row $($row.task_id) must name a dedicated surface"
    Assert-True ($row.ai_agent_allowed_scope -match 'only|N/A|no AI|not used|candidate|pending_review|draft|review|human|outer|suggestion|semantic|mapping|risk|proxy|observer|summarizer|不') "automation-first row $($row.task_id) must limit AI/agent scope"
    Assert-True ($row.exception_policy -match 'block|blocks|fail|fail-closed|N/A|no exception|human|后置|阻断|准入|missing|without') "automation-first row $($row.task_id) must define exception or fail-closed policy"
    Assert-True ($row.evidence_command -match 'tools/|run-|gate|contract|guard|smoke|evidence|checklist|dashboard|full gate|roadmap') "automation-first row $($row.task_id) must point to evidence command"
}

Assert-True ($contractById.ContainsKey('GLOBAL')) 'automation-first contract must include GLOBAL policy row'

$openBacklogRows = @($backlogRows | Where-Object { $_.status -ne '已完成' })
$missingBacklogCoverage = @($openBacklogRows | Where-Object { -not $contractById.ContainsKey($_.id) })
Assert-True ($missingBacklogCoverage.Count -eq 0) ("automation-first contract missing open backlog tasks: " + (($missingBacklogCoverage | Select-Object -ExpandProperty id) -join ','))

$openS0Rows = @($s0Rows | Where-Object { $_.status -ne '已完成' })
$missingS0Coverage = @($openS0Rows | Where-Object { -not $contractById.ContainsKey($_.id) })
Assert-True ($missingS0Coverage.Count -eq 0) ("automation-first contract missing open S0 subtasks: " + (($missingS0Coverage | Select-Object -ExpandProperty id) -join ','))

Assert-True ($contractById.ContainsKey('S004')) 'automation-first contract must include S004 document adapter policy'
$s004 = $contractById['S004']
$s004PolicyText = @(
    $s004.scope,
    $s004.deterministic_precheck,
    $s004.dedicated_surface,
    $s004.ai_agent_allowed_scope,
    $s004.exception_policy,
    $s004.evidence_command
) -join ' '
foreach ($term in @('OpenXML', 'OMML', 'PDF text', 'Docling', 'PaddleOCR', 'PP-OCRv5', 'PP-StructureV3', 'PP-FormulaNet', 'cloud')) {
    Assert-True ($s004PolicyText.Contains($term)) "S004 automation-first contract missing document adapter policy term: $term"
}

$docRequirements = @(
    @{ Path = $FeatureAdmissionPath; Patterns = @('automation-first', '规则/脚本', '专用 UI/API', 'tasks/automation-first-contract.csv') },
    @{ Path = $RoadmapPath; Patterns = @('automation-first', 'tasks/automation-first-contract.csv', 'run-automation-first-feature-contract-guard.ps1') },
    @{ Path = $TaskBreakdownPath; Patterns = @('Automation-first', 'tasks/automation-first-contract.csv', '缺少覆盖的待办任务不得继续实现') },
    @{ Path = $TechnologyStackPath; Patterns = @('文档、OCR 和公式识别属于专用 Adapter', 'OpenXML/OMML', 'PDF text/layout', 'PP-OCRv5', 'PP-StructureV3', 'PP-FormulaNet', 'Mathpix', 'Azure Document Intelligence') },
    @{ Path = $ImportPipelinePath; Patterns = @('OCR 和公式识别是专用功能', 'OpenXML/OMML', 'PDF text/layout', 'PP-OCRv5', 'PP-StructureV3', 'PP-FormulaNet', 'Mathpix', 'Azure Document Intelligence') },
    @{ Path = $ProductizationPlanPath; Patterns = @('automation-first', 'S0、P0-live、Q0、R0', 'run-automation-first-feature-contract-guard.ps1') },
    @{ Path = $ProductizationRoadmapPath; Patterns = @('OpenXML OMML docx 优先', 'PP-OCRv5 PP-StructureV3', 'PP-FormulaNet', 'automation-first guard') },
    @{ Path = $PrdPath; Patterns = @('Automation-First', 'AI 和 AI agent 只能作为限定辅助', 'fail-closed') },
    @{ Path = $ReadmePath; Patterns = @('automation-first', 'tasks/automation-first-contract.csv', 'unified gate') }
)

foreach ($requirement in $docRequirements) {
    $content = Get-Content -LiteralPath (Resolve-RepoPath $requirement.Path) -Raw
    foreach ($pattern in $requirement.Patterns) {
        Assert-True ($content.Contains($pattern)) "document $($requirement.Path) missing automation-first pattern: $pattern"
    }
}

$report = [ordered]@{
    status = 'pass'
    task = 'automation-first feature contract guard'
    checkedAt = (Get-Date).ToString('s')
    contractPath = $ContractPath
    contractRows = $contractRows.Count
    openBacklogTasksChecked = @($openBacklogRows).Count
    openS0SubtasksChecked = @($openS0Rows).Count
    policy = 'deterministic rules scripts dedicated surfaces first and AI agent only as bounded assistance'
    s004DocumentAdapterPolicy = 'OpenXML OMML first PDF text layout first Docling structure PaddleOCR OCR FormulaRecognition PP-FormulaNet and cloud fallback only after admission'
    requiredDocs = @($docRequirements | ForEach-Object { $_.Path })
    conclusion = 'future feature implementation is blocked unless automation-first contract coverage and evidence commands are present'
}

New-Item -ItemType Directory -Path (Split-Path -Parent $jsonFullPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonFullPath -Encoding UTF8
$report | ConvertTo-Json -Depth 6

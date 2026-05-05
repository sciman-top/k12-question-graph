$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$appPath = Join-Path $repoRoot 'apps\web\src\App.tsx'
$cssPath = Join-Path $repoRoot 'apps\web\src\App.css'
$teacherLabelsPath = Join-Path $repoRoot 'apps\web\src\ui\teacherLabels.ts'
$adminPanelsPath = Join-Path $repoRoot 'apps\web\src\ui\AdminGovernancePanels.tsx'

$app = Get-Content -LiteralPath $appPath -Raw
$css = Get-Content -LiteralPath $cssPath -Raw
$teacherLabels = Get-Content -LiteralPath $teacherLabelsPath -Raw
$adminPanels = Get-Content -LiteralPath $adminPanelsPath -Raw
$uiSource = $app + "`n" + $adminPanels

function Get-SectionByClass([string] $ClassName) {
    $pattern = '<section\s+className="' + [regex]::Escape($ClassName) + '"[\s\S]*?</section>'
    $match = [regex]::Match($app, $pattern)
    if (-not $match.Success) {
        throw "missing teacher section: $ClassName"
    }

    return $match.Value
}

function Remove-ContractOnlyText([string] $Text) {
    $withoutDataAttributes = [regex]::Replace($Text, '\sdata-[a-zA-Z0-9_-]+="[^"]*"', '')
    $withoutAriaAttributes = [regex]::Replace($withoutDataAttributes, '\saria-[a-zA-Z0-9_-]+="[^"]*"', '')
    return $withoutAriaAttributes
}

$adminOnlySelectors = @(
    '.admin-knowledge-panel',
    '.source-material-panel',
    '.activation-panel',
    '.knowledge-health-panel',
    '.storage-panel',
    '.guardrail-panel'
)

$teacherSectionClasses = @(
    'primary-panel',
    'status-panel',
    'review-panel',
    'paper-workbench-panel',
    'question-panel',
    'paper-request-panel',
    'paper-replacement-panel',
    'paper-export-panel',
    'score-panel',
    'analysis-panel'
)

$topbarMatch = [regex]::Match($app, '<header\s+className="topbar"[\s\S]*?</header>')
if (-not $topbarMatch.Success) {
    throw "missing teacher topbar"
}

$teacherVisibleParts = @($teacherSectionClasses | ForEach-Object {
    Remove-ContractOnlyText (Get-SectionByClass $_)
})
$teacherVisibleParts += Remove-ContractOnlyText $topbarMatch.Value
$teacherVisibleSource = $teacherVisibleParts -join "`n"

$forbiddenVisibleTerms = @(
    'synthetic fixture',
    'synthetic baseline',
    'draft/test',
    'draft 动态资产',
    'draft_test',
    'productionEligible=false',
    'candidate 版本',
    'active switch',
    'rollback snapshot',
    'importKey',
    'migration',
    'TanStack Query',
    'API 合同',
    '不进入生产',
    'sameKnowledge=true',
    'sameQuestionType=true',
    'similarDifficulty=true',
    'excludeRecentlyUsed=true',
    'knowledgeStatus=draft',
    'medium_hard',
    '生产资格',
    '状态枚举',
    'unknown'
)

foreach ($term in $forbiddenVisibleTerms) {
    if ($teacherVisibleSource.Contains($term)) {
        throw "teacher-visible UI leaks technical/governance term: $term"
    }
}

foreach ($pattern in @('\bmedium\b', '\b0\.\d+(?:-0\.\d+)?\b')) {
    if ([regex]::IsMatch($teacherVisibleSource, $pattern)) {
        throw "teacher-visible UI leaks technical/governance pattern: $pattern"
    }
}

$analysisSection = Get-SectionByClass 'analysis-panel'
foreach ($advancedMarker in @(
    'revision-intake-panel',
    'mapping-review-panel',
    'data-flow="c002r-teacher-revision-ux"',
    'data-flow="c002h-mapping-review-workbench-ui"',
    'data-contract="complex-mapping-review"'
)) {
    if ($analysisSection.Contains($advancedMarker)) {
        throw "teacher analysis panel leaks admin governance workbench: $advancedMarker"
    }
}

foreach ($requiredAdminMarker in @(
    'className="admin-knowledge-panel"',
    'data-flow="admin-knowledge-governance"',
    'data-contract="advanced-admin-only"',
    'data-flow="c002r-teacher-revision-ux"',
    'data-flow="c002h-mapping-review-workbench-ui"'
)) {
    if (-not $uiSource.Contains($requiredAdminMarker)) {
        throw "missing admin-only governance marker: $requiredAdminMarker"
    }
}

foreach ($requiredTeacherLabel in @(
    "draft_test: '示例流程'",
    "draft_dynamic_asset: '示例约束'",
    "medium: '难度中等'",
    "medium_hard: '难度略高'",
    "pending_review: '需确认'",
    "synthetic: '示例来源'",
    "golden: '样本来源'"
)) {
    if (-not $teacherLabels.Contains($requiredTeacherLabel)) {
        throw "missing centralized teacher-facing label: $requiredTeacherLabel"
    }
}

foreach ($requiredHelper in @(
    'teacherDifficultyLabelFor',
    'teacherDifficultyRangeLabelFor'
)) {
    if (-not $teacherLabels.Contains($requiredHelper)) {
        throw "missing teacher-facing helper: $requiredHelper"
    }
    if (-not $app.Contains($requiredHelper)) {
        throw "teacher UI must use centralized helper: $requiredHelper"
    }
}

if (-not $app.Contains('服务未连接')) {
    throw "teacher-visible service fallback must use clear Chinese wording"
}

foreach ($adminOnlySelector in $adminOnlySelectors) {
    $adminOnlyClass = 'className="' + $adminOnlySelector.TrimStart('.') + '"'
    if ($app.Contains($adminOnlyClass)) {
        throw "teacher shell must not inline admin-only panel: $adminOnlyClass"
    }
}

$displayNoneBlocks = [regex]::Matches($css, '(?s)([^{}]+)\{\s*display:\s*none;\s*\}')
foreach ($adminOnlySelector in $adminOnlySelectors) {
    $adminHiddenByDefault = $false
    foreach ($block in $displayNoneBlocks) {
        if ($block.Groups[1].Value.Contains($adminOnlySelector)) {
            $adminHiddenByDefault = $true
            break
        }
    }
    if (-not $adminHiddenByDefault) {
        throw "admin-only panel must be hidden by default: $adminOnlySelector"
    }
}

$teacherDisplayBlocks = [regex]::Matches($css, '(?s)([^{}]*teacher-view[^{}]*)\{\s*display:\s*block;\s*\}')
foreach ($block in $teacherDisplayBlocks) {
    foreach ($adminOnlySelector in $adminOnlySelectors) {
        if ($block.Groups[1].Value.Contains($adminOnlySelector)) {
            throw "admin-only panel must not be displayed by teacher-view CSS: $adminOnlySelector"
        }
    }
}

[ordered]@{
    status = 'pass'
    task = 'I008'
    teacherSectionClasses = $teacherSectionClasses
    forbiddenVisibleTermsChecked = $forbiddenVisibleTerms
    centralizedTeacherLabels = 'apps/web/src/ui/teacherLabels.ts'
    adminGovernanceHiddenByDefault = $adminOnlySelectors
    analysisPanelAdminLeakBlocked = $true
} | ConvertTo-Json -Depth 5

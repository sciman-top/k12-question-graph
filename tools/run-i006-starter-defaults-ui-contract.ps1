$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$app = Get-Content -LiteralPath (Join-Path $repoRoot 'apps\web\src\App.tsx') -Raw
$css = Get-Content -LiteralPath (Join-Path $repoRoot 'apps\web\src\App.css') -Raw

foreach ($pattern in @(
    'data-flow="first-run-starter-demo"',
    'data-contract="teacher-default-values"',
    'data-action="run-starter-example"',
    "contract: 'starter-step-1'",
    "contract: 'starter-step-2'",
    "contract: 'starter-step-3'",
    "contract: 'starter-step-4'",
    "view: 'import' as TeacherView",
    "view: 'paper' as TeacherView",
    "view: 'scores' as TeacherView",
    "view: 'analysis' as TeacherView"
)) {
    if (-not $app.Contains($pattern)) {
        throw "missing I006 starter/default marker: $pattern"
    }
}

foreach ($label in @('新手示例','用默认样例跑一遍','导入样卷','生成草稿卷','导入样例成绩','查看讲评摘要','不需要先准备真实资料')) {
    if (-not $app.Contains($label)) {
        throw "missing I006 teacher-facing label: $label"
    }
}

foreach ($pattern in @('.starter-demo', '.starter-demo-grid', '.starter-step')) {
    if (-not $css.Contains($pattern)) {
        throw "missing I006 starter/default CSS: $pattern"
    }
}

[ordered]@{
    status = 'pass'
    task = 'I006'
    firstRunSteps = @('import-sample-paper','assemble-draft-paper','import-sample-scores','open-analysis-summary')
    defaultValuesVisible = $true
    teacherDocsRequired = $false
} | ConvertTo-Json -Depth 4

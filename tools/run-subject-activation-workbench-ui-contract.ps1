param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$app = Get-Content -LiteralPath (Join-Path $repoRoot 'apps\web\src\App.tsx') -Raw
$style = Get-Content -LiteralPath (Join-Path $repoRoot 'apps\web\src\App.css') -Raw

foreach ($pattern in @(
    'data-flow="subject-activation-workbench"',
    'data-contract="activation-state"',
    'data-contract="activation-readiness"',
    'data-contract="teacher-review"',
    'data-contract="role-split"',
    'data-contract="no-direct-activation"',
    'data-contract="rollback-ready"',
    'data-action="open-candidate-review"',
    'data-action="open-activation-approval"',
    'data-action="open-activation-evidence"',
    'data-action="open-rollback-summary"',
    '教师只做复核和确认',
    '正式激活只给管理员'
)) {
    if (-not $app.Contains($pattern)) {
        throw "missing subject activation workbench UI marker: $pattern"
    }
}

foreach ($forbidden in @(
    'data-action="apply-activation"',
    'data-action="run-activation-script"',
    'ApplyActivation'
)) {
    if ($app.Contains($forbidden)) {
        throw "teacher-facing workbench must not expose direct activation action: $forbidden"
    }
}

foreach ($pattern in @(
    '.activation-panel',
    '.activation-summary',
    '.activation-flow',
    '.activation-review',
    '.activation-actions',
    '@media (max-width: 900px)'
)) {
    if (-not $style.Contains($pattern)) {
        throw "missing subject activation workbench style marker: $pattern"
    }
}

[ordered]@{
    status = 'pass'
    task = 'subject_activation_workbench_ui_contract'
    teacherFacingDirectActivation = $false
    checkedMarkers = 19
} | ConvertTo-Json -Depth 4

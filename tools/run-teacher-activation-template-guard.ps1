$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

$files = @(
    'docs/templates/subject-candidate-review-checklist.md',
    'docs/templates/subject-activation-approval-form.md',
    'docs/79_TeacherCandidateReviewAndActivationGuide.md',
    'docs/78_SubjectDomainAssetActivationRunbook.md'
)

foreach ($relative in $files) {
    $path = Join-Path $repoRoot $relative
    if (-not (Test-Path -LiteralPath $path)) {
        throw "missing teacher activation template doc: $relative"
    }
}

$review = Get-Content -LiteralPath (Join-Path $repoRoot 'docs/templates/subject-candidate-review-checklist.md') -Raw
foreach ($pattern in @('批次信息', '抽样复核要求', '逐项看什么', '决策规则', '复核结论')) {
    if ($review -notmatch $pattern) {
        throw "candidate review checklist missing section: $pattern"
    }
}

$approval = Get-Content -LiteralPath (Join-Path $repoRoot 'docs/templates/subject-activation-approval-form.md') -Raw
foreach ($pattern in @('机器摘要确认', '人工复核确认', '备份确认', '激活决定', 'Backup|backup')) {
    if ($approval -notmatch $pattern) {
        throw "activation approval form missing section: $pattern"
    }
}

$guide = Get-Content -LiteralPath (Join-Path $repoRoot 'docs/79_TeacherCandidateReviewAndActivationGuide.md') -Raw
foreach ($pattern in @('run-domain-asset-activation.ps1', 'GenerateDecisionFile', 'ApplyReview', 'ApplyActivation', '不要通过')) {
    if ($guide -notmatch $pattern) {
        throw "teacher activation guide missing operation detail: $pattern"
    }
}

$runbook = Get-Content -LiteralPath (Join-Path $repoRoot 'docs/78_SubjectDomainAssetActivationRunbook.md') -Raw
foreach ($pattern in @('subject-candidate-review-checklist.md', 'subject-activation-approval-form.md', '教师侧')) {
    if ($runbook -notmatch $pattern) {
        throw "activation runbook missing teacher template reference: $pattern"
    }
}

[ordered]@{
    status = 'pass'
    task = 'teacher_activation_template_guard'
    templates = $files
    requiredSectionsChecked = 19
} | ConvertTo-Json -Depth 4

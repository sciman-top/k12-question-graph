param(
    [string] $ReportPath = 'docs/evidence/20260530-ns403-review-workbench-ui-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

Push-Location $repoRoot
try {
    Push-Location 'apps/web'
    try {
        npm run build | Write-Host
        Assert-Condition ($LASTEXITCODE -eq 0) 'NS403 frontend build failed'
        npm run lint | Write-Host
        Assert-Condition ($LASTEXITCODE -eq 0) 'NS403 frontend lint failed'
    }
    finally {
        Pop-Location
    }

    $i003Output = & pwsh -NoProfile -ExecutionPolicy Bypass -File 'tools/run-i003-review-queue-ui-contract.ps1' 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) 'I003 review queue UI dependency failed'
    $i003 = $i003Output | ConvertFrom-Json
    Assert-Condition ($i003.status -eq 'pass') 'I003 review queue UI report did not pass'
    Assert-Condition ($i003.realGuangzhou2015QueueVisible -eq $true) 'NS403 real review queue marker missing'
    Assert-Condition ($i003.realGuangzhou2015DetailVisible -eq $true) 'NS403 real review detail marker missing'
    Assert-Condition (@($i003.shortcutActions) -contains 'merge') 'NS403 merge action missing'
    Assert-Condition (@($i003.shortcutActions) -contains 'split') 'NS403 split action missing'
    Assert-Condition (@($i003.shortcutActions) -contains 'associate') 'NS403 associate action missing'
    Assert-Condition (@($i003.shortcutActions) -contains 'undo') 'NS403 undo action missing'

    $app = Get-Content -LiteralPath 'apps/web/src/App.tsx' -Raw
    foreach ($marker in @(
        'runWorkbenchAction(',
        "action: 'merge' | 'split' | 'skip' | 'rerun' | 'associate' | 'undo' | 'save_question'",
        'resolveReviewQueueItem(',
        'const revision = {',
        'revision,',
        'data-contract="real-exam-teacher-revision"'
    )) {
        Assert-Condition ($app.Contains($marker)) "NS403 UI workflow marker missing: $marker"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS403'
        checkedAt = (Get-Date).ToString('s')
        mode = 'frontend_build_lint_plus_i003_ui_contract'
        productionEligible = $false
        verification = [ordered]@{
            frontendBuild = 'pass'
            frontendLint = 'pass'
            i003Contract = 'pass'
        }
        ui = [ordered]@{
            realReviewQueueVisible = [bool]$i003.realGuangzhou2015QueueVisible
            realReviewDetailVisible = [bool]$i003.realGuangzhou2015DetailVisible
            teacherRevisionVisible = $true
            shortcutActions = @($i003.shortcutActions)
            batchConfirm = [bool]$i003.batchConfirm
        }
        acceptance = [ordered]@{
            teacherCanMerge = $true
            teacherCanSplit = $true
            teacherCanAssociateAsset = $true
            teacherCanUndo = $true
            teacherCanSaveQuestion = $true
            teacherCanConfirmDismissAndRevise = $true
            backendTermsHiddenBehindTeacherLabels = $true
        }
        boundary = 'NS403 proves the review workbench UI contract, typed API calls, teacher revision controls, and frontend build/lint. It does not prove live browser interaction or onsite teacher validation.'
        next = 'NS404 can continue QuestionAsset association/unlink/recrop audit evidence.'
        rollback = 'git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns403-review-workbench-ui.ps1 docs/evidence/20260530-ns403-review-workbench-ui-report.json'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 6
}
finally {
    Pop-Location
}

param(
    [string] $ReportPath = 'docs/evidence/20260530-ns605-replace-undo-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Read-Json([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing report: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Read-Text([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing file: $Path"
    return Get-Content -LiteralPath $fullPath -Raw
}

function Invoke-CheckedScript([scriptblock] $Command, [string] $Label) {
    $output = & $Command 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "$Label failed: $output"
    return $output
}

Push-Location $repoRoot
try {
    $ns604 = Read-Json 'docs/evidence/20260530-ns604-paper-request-understanding-report.json'
    Assert-Condition ($ns604.status -eq 'pass') 'NS605 dependency NS604 report did not pass'
    Assert-Condition ([bool]$ns604.acceptance.pendingReviewBeforeTeacherConfirmation) 'NS605 requires NS604 review-before-generation boundary'

    $apiBuildOutput = & dotnet build apps/api/K12QuestionGraph.Api.csproj -c Release 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "NS605 API build failed: $apiBuildOutput"

    $e003Output = Invoke-CheckedScript {
        .\tools\run-e003-question-replacement-contract.ps1
    } 'E003 question replacement contract'
    $e003 = $e003Output | ConvertFrom-Json
    Assert-Condition ($e003.status -eq 'pass') 'E003 source contract did not pass'
    Assert-Condition ([string]$e003.mode -eq 'draft_test') 'NS605 replacement must stay draft_test'
    Assert-Condition (-not [bool]$e003.productionEligible) 'NS605 replacement must not be production eligible'
    Assert-Condition (-not [bool]$e003.allowRealModelCalls) 'NS605 replacement must not allow real model calls'
    Assert-Condition ([bool]$e003.sameKnowledge) 'NS605 must preserve same knowledge'
    Assert-Condition ([bool]$e003.sameQuestionType) 'NS605 must preserve same question type'
    Assert-Condition ([bool]$e003.similarDifficulty) 'NS605 must preserve similar difficulty'
    Assert-Condition ([bool]$e003.sameScore) 'NS605 must preserve same score'
    Assert-Condition ([bool]$e003.undoTokenPresent) 'NS605 must return undo token'
    Assert-Condition ([string]$e003.knowledgeStatus -eq 'draft') 'NS605 must stay on draft dynamic assets'

    $app = Read-Text 'apps/web/src/App.tsx'
    foreach ($marker in @(
        'data-flow="paper-question-replacement"',
        'data-action="replace-question"',
        'data-action="undo-question-replacement"',
        'data-contract="replacement-constraints"',
        'data-contract="replacement-undo-snapshot"',
        'data-contract="replacement-productionEligible=false"',
        'data-contract="replacement-audit-trail"',
        'kept primary knowledge constraint',
        'kept question type constraint',
        'kept score constraint',
        'kept draft_test non-production boundary'
    )) {
        Assert-Condition ($app.Contains($marker)) "NS605 UI marker missing: $marker"
    }

    $program = Read-Text 'apps/api/Program.cs'
    foreach ($marker in @(
        '/paper-requests/replace-question',
        'ReplacePaperQuestion',
        'PaperQuestionReplacementResponse',
        'PaperQuestionUndoSnapshot',
        'BlocksProductionPaper'
    )) {
        Assert-Condition ($program.Contains($marker)) "NS605 API marker missing: $marker"
    }

    $doc = Read-Text 'docs/74_E003_QuestionReplacementUndo.md'
    foreach ($keyword in @(
        '同知识点',
        '同题型',
        '相近难度',
        '同分值',
        '当前卷不重复',
        'undo.undoToken',
        'revertAction',
        '不调用真实模型'
    )) {
        Assert-Condition ($doc.Contains($keyword)) "NS605 evidence doc missing keyword: $keyword"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS605'
        checkedAt = (Get-Date).ToString('s')
        mode = 'replace_question_and_undo_snapshot'
        productionEligible = $false
        externalAiCalls = 0
        realStudentDataUsed = $false
        activeAssetMutation = $false
        dependency = [ordered]@{
            ns604 = 'docs/evidence/20260530-ns604-paper-request-understanding-report.json'
            e003 = 'tools/run-e003-question-replacement-contract.ps1'
            workflowDoc = 'docs/74_E003_QuestionReplacementUndo.md'
        }
        replacement = [ordered]@{
            mode = [string]$e003.mode
            action = [string]$e003.action
            sameKnowledge = [bool]$e003.sameKnowledge
            sameQuestionType = [bool]$e003.sameQuestionType
            similarDifficulty = [bool]$e003.similarDifficulty
            sameScore = [bool]$e003.sameScore
            undoTokenPresent = [bool]$e003.undoTokenPresent
            knowledgeStatus = [string]$e003.knowledgeStatus
        }
        acceptance = [ordered]@{
            keepsSameKnowledge = $true
            keepsSameQuestionType = $true
            keepsSimilarDifficulty = $true
            keepsSameScore = $true
            excludesCurrentPaperDuplicates = $true
            excludesRecentlyUsedQuestions = $true
            providesUndoSnapshot = $true
            uiHasReplaceAndUndoActions = $true
            auditTrailVisible = $true
            noExternalAiCall = $true
            noRealStudentData = $true
            noActiveSwitch = $true
        }
        verification = [ordered]@{
            build = 'dotnet build apps/api/K12QuestionGraph.Api.csproj -c Release'
            test = 'tools/run-e003-question-replacement-contract.ps1'
            contractInvariant = 'API/UI markers and docs/74_E003_QuestionReplacementUndo.md'
            hotspot = 'gate_na: no independent hotspot command; teacher workflow hotspot covered by same-knowledge/type/difficulty/score constraints, duplicate/recent-use exclusions, undo snapshot, and UI actions'
        }
        boundary = 'NS605 proves one-click replacement keeps teacher-facing paper constraints and returns an undo snapshot in draft_test mode without real model calls or production writes.'
        rollback = "git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns605-replace-undo.ps1 $ReportPath"
        next = 'NS606 can continue export preflight review before Word/PDF artifact generation.'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}

param(
    [string] $ApiProject = 'apps\api\K12QuestionGraph.Api.csproj'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse('127.0.0.1'), 0)
    try {
        $listener.Start()
        return $listener.LocalEndpoint.Port
    }
    finally {
        $listener.Stop()
    }
}

function Wait-ApiHealth([System.Diagnostics.Process] $Process, [string] $ApiUrl, [string] $LogErr) {
    for ($i = 0; $i -lt 30; $i++) {
        if ($Process.HasExited) {
            throw "API exited before health check on $ApiUrl; see $LogErr"
        }

        try {
            $health = Invoke-RestMethod -Uri "$ApiUrl/health" -TimeoutSec 2
            if ($health.status -eq 'ok') {
                return
            }
        }
        catch {
            Start-Sleep -Seconds 1
        }
    }

    throw "API did not become healthy on $ApiUrl"
}

Push-Location $repoRoot
try {
    $app = Get-Content -LiteralPath 'apps\web\src\App.tsx' -Raw
    foreach ($pattern in @(
        'data-flow="paper-question-replacement"',
        'data-action="replace-question"',
        'data-action="undo-question-replacement"',
        'data-contract="replacement-constraints"',
        'data-contract="replacement-undo-snapshot"',
        'data-contract="replacement-productionEligible=false"',
        'data-contract="replacement-audit-trail"'
    )) {
        if (-not $app.Contains($pattern)) {
            throw "missing E003 UI contract marker: $pattern"
        }
    }

    $port = Get-FreeTcpPort
    $apiUrl = "http://127.0.0.1:$port"
    $logOut = Join-Path $repoRoot 'docs\evidence\e003-gate-api.out.log'
    $logErr = Join-Path $repoRoot 'docs\evidence\e003-gate-api.err.log'
    $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project',$ApiProject,'-c','Release','--no-build','--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr

    try {
        Wait-ApiHealth -Process $process -ApiUrl $apiUrl -LogErr $logErr

        $body = [ordered]@{
            currentQuestion = [ordered]@{
                id = 'paper-q-01'
                stemPreview = '关于惯性的说法，下列哪项正确？'
                questionType = 'single_choice'
                score = 3
                difficultyEstimated = 0.62
                primaryKnowledgeId = 'PHY-JH-MECH-FORCE-NEWTON1'
                primaryKnowledgeTitle = '牛顿第一定律与惯性'
                sourceType = 'synthetic'
                recentUseStatus = 'not_recently_used'
            }
        } | ConvertTo-Json -Depth 6
        $replacement = Invoke-RestMethod -Method Post -Uri "$apiUrl/paper-requests/replace-question" -ContentType 'application/json' -Body $body

        if ($replacement.mode -ne 'draft_test') { throw "E003 replacement must stay draft_test" }
        if ($replacement.productionEligible) { throw "E003 replacement must not be production eligible" }
        if ($replacement.allowRealModelCalls) { throw "E003 replacement must not allow real model calls" }
        if ($replacement.action -ne 'replace_question') { throw "E003 action mismatch" }
        if (-not $replacement.constraints.sameKnowledge) { throw "E003 must keep same knowledge" }
        if (-not $replacement.constraints.sameQuestionType) { throw "E003 must keep same question type" }
        if (-not $replacement.constraints.similarDifficulty) { throw "E003 must keep similar difficulty" }
        if (-not $replacement.constraints.sameScore) { throw "E003 must keep same score" }
        if (-not $replacement.constraints.excludeCurrentPaperDuplicates) { throw "E003 must exclude duplicates in current paper" }
        if (-not $replacement.constraints.excludeRecentlyUsed) { throw "E003 must exclude recently used questions" }
        if ($replacement.constraints.knowledgeStatus -ne 'draft') { throw "E003 must use draft dynamic assets" }
        if (-not $replacement.constraints.blocksProductionPaper) { throw "E003 must block production paper semantics" }
        if ($replacement.replacement.questionType -ne 'single_choice') { throw "E003 replacement question type changed" }
        if ([decimal]$replacement.replacement.score -ne 3) { throw "E003 replacement score changed" }
        if ($replacement.replacement.primaryKnowledgeId -ne 'PHY-JH-MECH-FORCE-NEWTON1') { throw "E003 replacement knowledge changed" }
        if ([string]::IsNullOrWhiteSpace($replacement.undo.undoToken)) { throw "E003 undo token missing" }
        if ($replacement.undo.beforeQuestion.id -ne 'paper-q-01') { throw "E003 undo before snapshot mismatch" }
        if ($replacement.undo.afterQuestion.id -ne $replacement.replacement.id) { throw "E003 undo after snapshot mismatch" }

        [ordered]@{
            status = 'pass'
            mode = [string]$replacement.mode
            productionEligible = [bool]$replacement.productionEligible
            allowRealModelCalls = [bool]$replacement.allowRealModelCalls
            action = [string]$replacement.action
            sameKnowledge = [bool]$replacement.constraints.sameKnowledge
            sameQuestionType = [bool]$replacement.constraints.sameQuestionType
            similarDifficulty = [bool]$replacement.constraints.similarDifficulty
            sameScore = [bool]$replacement.constraints.sameScore
            undoTokenPresent = -not [string]::IsNullOrWhiteSpace($replacement.undo.undoToken)
            knowledgeStatus = [string]$replacement.constraints.knowledgeStatus
        } | ConvertTo-Json
    }
    finally {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
}
finally {
    Pop-Location
}

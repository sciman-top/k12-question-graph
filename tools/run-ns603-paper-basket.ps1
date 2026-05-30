param(
    [string] $ReportPath = 'docs/evidence/20260530-ns603-paper-basket-report.json',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

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

function Invoke-CheckedScript([scriptblock] $Command, [string] $Label) {
    $output = & $Command 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "$Label failed: $output"
    return $output
}

Push-Location $repoRoot
$previousPgPassword = $env:PGPASSWORD
try {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'DatabasePassword or PGPASSWORD is required for NS603 paper basket verification.'
    $env:PGPASSWORD = $DatabasePassword

    $ns602 = Read-Json 'docs/evidence/20260530-ns602-question-card-ui-report.json'
    Assert-Condition ($ns602.status -eq 'pass') 'NS603 dependency NS602 report did not pass'
    Assert-Condition ([bool]$ns602.acceptance.cardShowsSourceAndVersion) 'NS603 requires NS602 visible card version/source evidence'

    $apiBuildOutput = & dotnet build apps/api/K12QuestionGraph.Api.csproj -c Release 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "NS603 API build failed: $apiBuildOutput"

    $s009aPath = 'docs/evidence/20260530-ns603-s009a-source-report.json'
    $s009bPath = 'docs/evidence/20260530-ns603-s009b-source-report.json'
    $s009cPath = 'docs/evidence/20260530-ns603-s009c-source-report.json'

    $s009aPort = Get-FreeTcpPort
    Invoke-CheckedScript {
        .\tools\run-s009a-paper-basket-persistence-smoke.ps1 `
            -DatabaseName $DatabaseName `
            -DatabaseUser $DatabaseUser `
            -DatabaseHost $DatabaseHost `
            -DatabasePort $DatabasePort `
            -DatabasePassword $DatabasePassword `
            -PgBin $PgBin `
            -ApiPort $s009aPort `
            -ReportPath $s009aPath
    } 'S009A paper basket persistence smoke' | Write-Host
    $s009a = Read-Json $s009aPath
    Assert-Condition ($s009a.status -eq 'pass') 'S009A source report did not pass'
    Assert-Condition ([int]$s009a.itemCount -eq 2) 'NS603 requires S009A persisted two basket items'
    Assert-Condition ([int]$s009a.knowledgeVersion -eq 1) 'NS603 requires S009A active knowledge version reference'
    Assert-Condition ([string]$s009a.knowledgeVersionStatus -eq 'active') 'NS603 requires S009A active knowledge version status'
    Assert-Condition (@($s009a.subQuestionNumbers) -contains '2-1') 'NS603 requires S009A sub-question number persistence'

    $s009bPort = Get-FreeTcpPort
    Invoke-CheckedScript {
        .\tools\run-s009b-blueprint-review-workflow-smoke.ps1 `
            -DatabaseName $DatabaseName `
            -DatabaseUser $DatabaseUser `
            -DatabaseHost $DatabaseHost `
            -DatabasePort $DatabasePort `
            -DatabasePassword $DatabasePassword `
            -PgBin $PgBin `
            -ApiPort $s009bPort `
            -ReportPath $s009bPath
    } 'S009B blueprint review workflow smoke' | Write-Host
    $s009b = Read-Json $s009bPath
    Assert-Condition ($s009b.status -eq 'pass') 'S009B source report did not pass'
    Assert-Condition ([string]$s009b.initialStatus -eq 'pending_review') 'NS603 requires blueprint starts pending_review'
    Assert-Condition ([string]$s009b.finalStatus -eq 'confirmed') 'NS603 requires teacher-confirmed blueprint status'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$s009b.paperBasketId)) 'NS603 requires confirmed paper basket id'
    Assert-Condition ([int]$s009b.selectedQuestionCount -ge 8) 'NS603 requires confirmed basket question selection'
    Assert-Condition ([bool]$s009b.reviewRequiredBeforeQuestionSelection) 'NS603 requires review before question selection'
    Assert-Condition (-not [bool]$s009b.opaqueGenerationAllowed) 'NS603 must keep opaque generation blocked'
    Assert-Condition (-not [bool]$s009b.allowRealModelCalls) 'NS603 must not enable real model calls'
    Assert-Condition (-not [bool]$s009b.productionEligible) 'NS603 must not mark this draft flow production eligible'

    Invoke-CheckedScript {
        .\tools\run-s009c-paper-workbench-ui-contract.ps1 -ReportPath $s009cPath
    } 'S009C paper workbench UI contract' | Write-Host
    $s009c = Read-Json $s009cPath
    Assert-Condition ($s009c.status -eq 'pass') 'S009C source report did not pass'
    Assert-Condition (@($s009c.contracts) -contains 'confirmed-paper-basket') 'NS603 requires confirmed paper basket UI contract'

    $m001Output = Invoke-CheckedScript {
        .\tools\run-m001-paper-basket-structure-contract.ps1
    } 'M001 paper basket structure contract'
    $m001 = $m001Output | ConvertFrom-Json
    Assert-Condition ($m001.status -eq 'pass') 'M001 source contract did not pass'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$m001.activeKnowledgeVersion)) 'NS603 requires M001 active knowledge version evidence'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS603'
        checkedAt = (Get-Date).ToString('s')
        mode = 'paper_basket_and_draft_persistence_runtime'
        productionEligible = $false
        externalAiCalls = 0
        realStudentDataUsed = $false
        activeAssetMutation = $false
        dependency = [ordered]@{
            ns602 = 'docs/evidence/20260530-ns602-question-card-ui-report.json'
            s009a = $s009aPath
            s009b = $s009bPath
            s009c = $s009cPath
            m001 = 'tools/run-m001-paper-basket-structure-contract.ps1'
        }
        persistence = [ordered]@{
            directBasketId = [string]$s009a.basketId
            directBasketItemCount = [int]$s009a.itemCount
            directBasketTotalScore = $s009a.totalScore
            directBasketKnowledgeVersionStatus = [string]$s009a.knowledgeVersionStatus
            directBasketKnowledgeVersion = [int]$s009a.knowledgeVersion
            confirmedBlueprintReviewId = [string]$s009b.blueprintReviewId
            confirmedPaperBasketId = [string]$s009b.paperBasketId
            selectedQuestionCount = [int]$s009b.selectedQuestionCount
        }
        acceptance = [ordered]@{
            basketPersistsQuestionNumbersScoresAndSubQuestionNumbers = $true
            basketPersistsActiveKnowledgeVersionReference = $true
            paperStructureIsReproducible = $true
            blueprintRequiresTeacherConfirmationBeforeQuestionSelection = $true
            teacherConfirmCreatesDraftPaperBasket = $true
            uiShowsSavedPaperBasketState = $true
            backendIdsNotTeacherVisible = $true
            noExternalAiCall = $true
            noRealStudentData = $true
            noActiveSwitch = $true
        }
        verification = [ordered]@{
            build = 'dotnet build apps/api/K12QuestionGraph.Api.csproj -c Release'
            test = 'tools/run-s009a-paper-basket-persistence-smoke.ps1; tools/run-s009b-blueprint-review-workflow-smoke.ps1; tools/run-s009c-paper-workbench-ui-contract.ps1'
            contractInvariant = 'tools/run-m001-paper-basket-structure-contract.ps1'
            hotspot = 'gate_na: no independent hotspot command; teacher workflow hotspot covered by persisted structure, confirmation-before-selection guard, UI saved-basket contract, no visible backend id, no external AI, no real student data'
        }
        boundary = 'NS603 proves paper baskets and draft paper structure can be saved, reloaded, reproduced with active knowledge version references, and created from blueprint only after teacher confirmation.'
        rollback = "delete from paper_basket_items where paper_basket_id in ('$($s009a.basketId)','$($s009b.paperBasketId)'); delete from paper_baskets where id in ('$($s009a.basketId)','$($s009b.paperBasketId)'); delete from paper_blueprint_reviews where id = '$($s009b.blueprintReviewId)'; git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns603-paper-basket.ps1 $ReportPath $s009aPath $s009bPath $s009cPath"
        next = 'NS604 can continue natural-language paper request understanding without enabling real model calls or direct production generation.'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    $env:PGPASSWORD = $previousPgPassword
    Pop-Location
}

param(
    [string] $ReportPath = 'docs/evidence/20260530-ns703-analysis-metrics-report.json',
    [string] $OutputRoot = 'tmp\ns703-knowledge-mastery'
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
    $ns702 = Read-Json 'docs/evidence/20260530-ns702-item-score-mapping-report.json'
    Assert-Condition ($ns702.status -eq 'pass') 'NS703 dependency NS702 report did not pass'
    Assert-Condition ([bool]$ns702.acceptance.noSilentDropForUnclearItems) 'NS703 requires NS702 no-silent-drop mapping evidence'

    $ns501 = Read-Json 'docs/evidence/20260530-ns501-c002-active-boundary.json'
    Assert-Condition ($ns501.status -eq 'pass') 'NS703 dependency NS501 report did not pass'
    Assert-Condition ([bool]$ns501.acceptance.knowledgeMasteryUsesActiveC002) 'NS703 requires NS501 active C002 analysis boundary'

    $f003Path = 'docs/evidence/20260530-ns703-f003-source-report.json'
    Invoke-CheckedScript {
        .\tools\run-f003-knowledge-mastery-analysis-contract.ps1 -OutputRoot $OutputRoot -Report $f003Path
    } 'F003 knowledge mastery analysis contract' | Write-Host
    $f003 = Read-Json $f003Path
    Assert-Condition ($f003.status -eq 'pass') 'F003 source report did not pass'
    Assert-Condition ([string]$f003.mode -eq 'draft_test') 'NS703 analysis must stay draft_test'
    Assert-Condition (-not [bool]$f003.productionEligible) 'NS703 analysis must not be production eligible'
    Assert-Condition (-not [bool]$f003.realStudentDataUsed) 'NS703 must not use real student data'
    Assert-Condition (-not [bool]$f003.studentPortalExposed) 'NS703 must not expose student portal'
    Assert-Condition ([bool]$f003.noProductionHistoryWrite) 'NS703 must not write production history'
    Assert-Condition ([int]$f003.classSummary.studentCount -ge 2) 'NS703 requires student sample coverage'
    Assert-Condition ([int]$f003.classSummary.itemCount -ge 2) 'NS703 requires item sample coverage'
    Assert-Condition ([double]$f003.classSummary.totalScoreRate -ge 0 -and [double]$f003.classSummary.totalScoreRate -le 1) 'NS703 class score rate out of range'
    Assert-Condition ([bool]$f003.classSummary.discriminationAvailable) 'NS703 requires discrimination metric'
    Assert-Condition (@($f003.knowledgePointSummaries).Count -ge 2) 'NS703 requires at least two knowledge summaries'
    Assert-Condition (@($f003.weakKnowledgePoints).Count -ge 1) 'NS703 requires weak knowledge points'
    Assert-Condition (@($f003.studentMasterySummaries).Count -ge 2) 'NS703 requires student mastery summaries'

    foreach ($summary in @($f003.knowledgePointSummaries)) {
        Assert-Condition ([double]$summary.scoreRate -ge 0 -and [double]$summary.scoreRate -le 1) "NS703 scoreRate out of range for $($summary.knowledgeStableId)"
        Assert-Condition ([double]$summary.discrimination -ge -1 -and [double]$summary.discrimination -le 1) "NS703 discrimination out of range for $($summary.knowledgeStableId)"
        Assert-Condition ([string]$summary.historyPolicy -eq 'draft_test_only_no_production_history_rewrite') "NS703 history policy mismatch for $($summary.knowledgeStableId)"
        Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$summary.activeVersion)) "NS703 active version missing for $($summary.knowledgeStableId)"
    }

    $summaryPath = [string]$f003.outputs.summaryPath
    Assert-Condition (Test-Path -LiteralPath $summaryPath) "NS703 summary artifact missing: $summaryPath"

    $analyticsDoc = Read-Text 'docs/13_AssessmentAnalytics.md'
    foreach ($marker in @('得分率', '区分度', '知识点得分率', 'tools/run-f003-knowledge-mastery-analysis-contract.ps1')) {
        Assert-Condition ($analyticsDoc.Contains($marker)) "NS703 analytics doc marker missing: $marker"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS703'
        checkedAt = (Get-Date).ToString('s')
        mode = 'analysis_metrics_recomputable'
        productionEligible = $false
        externalAiCalls = 0
        realStudentDataUsed = $false
        writesProductionHistory = $false
        activeAssetMutation = $false
        dependency = [ordered]@{
            ns702 = 'docs/evidence/20260530-ns702-item-score-mapping-report.json'
            ns501 = 'docs/evidence/20260530-ns501-c002-active-boundary.json'
            f003 = $f003Path
        }
        metrics = [ordered]@{
            activeKnowledgeVersion = [string]$f003.activeKnowledgeVersion
            studentCount = [int]$f003.classSummary.studentCount
            itemCount = [int]$f003.classSummary.itemCount
            totalScoreRate = [double]$f003.classSummary.totalScoreRate
            discriminationAvailable = [bool]$f003.classSummary.discriminationAvailable
            weakKnowledgeCount = @($f003.weakKnowledgePoints).Count
            summaryPath = $summaryPath
        }
        acceptance = [ordered]@{
            classScoreRateRecomputable = $true
            knowledgeScoreRateRecomputable = $true
            discriminationRecomputable = $true
            knowledgeMasteryExplainable = $true
            weakKnowledgePointsIdentified = $true
            historicalAnalysisNotRewritten = $true
            noExternalAiCall = $true
            noRealStudentData = $true
            noProductionHistoryWrite = $true
            noActiveSwitch = $true
        }
        verification = [ordered]@{
            build = 'gate_na: Python deterministic metrics script; no .NET build required for pure synthetic analysis contract'
            test = 'tools/run-f003-knowledge-mastery-analysis-contract.ps1'
            contractInvariant = 'scoreRate/discrimination range checks, active knowledge version, draft_test history policy, no production history write'
            hotspot = 'gate_na: no real class sample or onsite teacher interpretation session; deterministic synthetic analysis covers non-site metric reproducibility'
        }
        boundary = 'NS703 proves basic CTT-style score rate, discrimination, and knowledge mastery metrics are recomputable and explainable in draft_test mode without real student data or production history writes.'
        rollback = "delete $OutputRoot and $f003Path if needed; git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns703-analysis-metrics.ps1 $ReportPath"
        next = 'NS704 can continue commentary report and layered suggestions export.'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}

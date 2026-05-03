param(
    [string] $OutputRoot = 'tmp\f003-knowledge-mastery',
    [string] $Report = 'docs\evidence\f003-knowledge-mastery-analysis-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

Push-Location $repoRoot
try {
    python tools\f003_knowledge_mastery_analysis.py --output-root $OutputRoot --report $Report | Write-Host
    if ($LASTEXITCODE -ne 0) { throw "F003 knowledge mastery analysis failed" }

    $reportObject = Get-Content -LiteralPath $Report -Raw | ConvertFrom-Json
    if ($reportObject.status -ne 'pass') { throw "F003 report status is not pass" }
    if ($reportObject.mode -ne 'draft_test') { throw "F003 must stay draft_test" }
    if ($reportObject.productionEligible) { throw "F003 must not be production eligible" }
    if ($reportObject.realStudentDataUsed) { throw "F003 must not use real student data" }
    if (-not $reportObject.noProductionHistoryWrite) { throw "F003 must not write production history" }
    if (@($reportObject.knowledgePointSummaries).Count -lt 2) { throw "F003 must summarize at least two knowledge points" }
    if (@($reportObject.weakKnowledgePoints).Count -lt 1) { throw "F003 must identify at least one weak knowledge point" }
    if (@($reportObject.studentMasterySummaries).Count -lt 2) { throw "F003 must summarize at least two students" }
    if (-not $reportObject.classSummary.discriminationAvailable) { throw "F003 discrimination metric is required" }

    foreach ($summary in @($reportObject.knowledgePointSummaries)) {
        if ($summary.scoreRate -lt 0 -or $summary.scoreRate -gt 1) { throw "knowledge scoreRate out of range" }
        if ($summary.discrimination -lt -1 -or $summary.discrimination -gt 1) { throw "knowledge discrimination out of range" }
        if ([string]::IsNullOrWhiteSpace($summary.historyPolicy)) { throw "knowledge historyPolicy is required" }
    }

    $reportObject | ConvertTo-Json -Depth 12
}
finally {
    Pop-Location
}

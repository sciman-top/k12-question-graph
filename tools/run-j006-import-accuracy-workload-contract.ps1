$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$reportPath = Join-Path $repoRoot 'docs\evidence\j006-import-accuracy-workload-report.json'

Push-Location $repoRoot
try {
    foreach ($gate in @(
        'tools\run-j001-openxml-docx-adapter-contract.ps1',
        'tools\run-j002-text-pdf-adapter-contract.ps1',
        'tools\run-j003-scanned-ocr-adapter-contract.ps1',
        'tools\run-j004-fidelity-regression-contract.ps1',
        'tools\run-j005-adapter-diagnostic-supply-chain-contract.ps1'
    )) {
        pwsh -NoProfile -ExecutionPolicy Bypass -File $gate | Write-Host
        if ($LASTEXITCODE -ne 0) { throw "J006 prerequisite gate failed: $gate" }
    }

    python tools\j006_import_accuracy_workload.py | Write-Host
    if ($LASTEXITCODE -ne 0) { throw "J006 import accuracy workload report failed" }

    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    if ($report.status -ne 'pass') { throw "J006 report status is not pass" }
    if ($report.mode -ne 'draft_test') { throw "J006 must stay draft_test" }
    if ($report.productionEligible) { throw "J006 must not be production eligible" }
    if ($report.externalAiCalls -ne 0) { throw "J006 must not call external AI" }
    if ($report.realStudentDataUsed) { throw "J006 must not use real student data" }
    if (-not $report.proxyBaseline) { throw "J006 must identify this as a proxy baseline" }
    if ([decimal]$report.accuracy.sourceRegionAccuracy -lt 1) { throw "J006 source region baseline regressed" }
    if ([decimal]$report.accuracy.blockPreservationAccuracy -lt 1) { throw "J006 block preservation baseline regressed" }
    if ($report.accuracy.automatedCutCaseCount -ne 0) { throw "J006 must not claim automated cutting cases" }
    if ($null -ne $report.accuracy.autoCutAccuracy) { throw "J006 autoCutAccuracy must stay null before golden-set cut accuracy exists" }
    if (-not $report.accuracy.realOcrTextRecognized) { throw "J006 must record real local OCR text recognition" }
    if ($report.teacherWorkload.confirmationItemCount -lt 1) { throw "J006 confirmation item count missing" }
    if ($report.teacherWorkload.failureTakeoverStepCount -lt 1) { throw "J006 failure takeover steps missing" }
    if (-not $report.hotspot.doesNotClaimAiAutomation) { throw "J006 must explicitly avoid AI automation claims" }
    if (-not $report.evidence.j003.takeoverRequired) { throw "J006 scanned baseline must require takeover" }
    if (-not $report.evidence.j003.realOcrTextRecognized) { throw "J006 must claim scanned OCR text recognition after J003 local OCR landed" }

    [ordered]@{
        status = 'pass'
        task = 'J006'
        mode = [string]$report.mode
        sampleCount = [int]$report.accuracy.goldenSamples.Count
        sourceRegionAccuracy = [decimal]$report.accuracy.sourceRegionAccuracy
        blockPreservationAccuracy = [decimal]$report.accuracy.blockPreservationAccuracy
        realOcrTextRecognized = [bool]$report.accuracy.realOcrTextRecognized
        automatedCutCaseCount = [int]$report.accuracy.automatedCutCaseCount
        confirmationItemCount = [int]$report.teacherWorkload.confirmationItemCount
        failureTakeoverStepCount = [int]$report.teacherWorkload.failureTakeoverStepCount
        estimatedTeacherMinutes = [int]$report.teacherWorkload.estimatedTeacherMinutes
    } | ConvertTo-Json -Depth 6
}
finally {
    Pop-Location
}

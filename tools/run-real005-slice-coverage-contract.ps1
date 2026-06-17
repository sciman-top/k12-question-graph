param(
    [string] $ReportPath = '',
    [string] $MarkdownReportPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = 'tmp/real005-slice-coverage-contract/real005-closure-standard-report.json'
}

if ([string]::IsNullOrWhiteSpace($MarkdownReportPath)) {
    $MarkdownReportPath = 'tmp/real005-slice-coverage-contract/real005-closure-standard-report.md'
}

$reportFullPath = if ([System.IO.Path]::IsPathRooted($ReportPath)) {
    $ReportPath
}
else {
    Join-Path $repoRoot ($ReportPath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
}

$markdownFullPath = if ([System.IO.Path]::IsPathRooted($MarkdownReportPath)) {
    $MarkdownReportPath
}
else {
    Join-Path $repoRoot ($MarkdownReportPath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
}

New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
& (Join-Path $repoRoot 'tools\run-real005-guangzhou-2015-2025-closure-standard.ps1') `
    -JsonReportPath $ReportPath `
    -MarkdownReportPath $MarkdownReportPath | Out-Null

Assert-True (Test-Path -LiteralPath $reportFullPath) "missing REAL005 report: $ReportPath"
$report = Get-Content -LiteralPath $reportFullPath -Raw | ConvertFrom-Json

Assert-True ([string]$report.status -eq 'pass') 'REAL005 report must pass'
Assert-True ([string]$report.closureStatus -eq 'not_closed') 'REAL005 report must remain not_closed for current truth'

$sliceCoverage = $report.sliceCoverage
Assert-True ($null -ne $sliceCoverage) 'REAL005 report must expose sliceCoverage'

foreach ($sliceId in @('REAL005A', 'REAL005B', 'REAL005C', 'REAL005D')) {
    $slice = $sliceCoverage.$sliceId
    Assert-True ($null -ne $slice) "REAL005 report missing sliceCoverage.$sliceId"
    Assert-True (@($slice.criteriaIds).Count -ge 1) "REAL005 report sliceCoverage.$sliceId must list criteriaIds"
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$slice.status)) "REAL005 report sliceCoverage.$sliceId must expose status"
}

$sliceA = $sliceCoverage.REAL005A
Assert-True ((@($sliceA.criteriaIds)) -contains 'RG001') 'REAL005A must include RG001'
Assert-True ((@($sliceA.criteriaIds)) -contains 'RG002') 'REAL005A must include RG002'
Assert-True ([string]$sliceA.status -eq 'pass') 'REAL005A should currently pass after RG001/RG002 repo-side evidence is complete'
Assert-True (@($sliceA.blockers).Count -eq 0) 'REAL005A must not list blockers after RG001/RG002 pass'

$sliceB = $sliceCoverage.REAL005B
Assert-True ((@($sliceB.criteriaIds)) -contains 'RG003') 'REAL005B must include RG003'
Assert-True ((@($sliceB.criteriaIds)) -contains 'RG009') 'REAL005B must include RG009'
Assert-True ([string]$sliceB.status -eq 'pass') 'REAL005B should now pass after reviewed-question source review closure is proven'
Assert-True ($null -ne $sliceB.detailedSliceCoverage) 'REAL005B must expose detailedSliceCoverage'
Assert-True ([string]$sliceB.nextDetailedSlice -eq 'none') 'REAL005B next detailed slice should be exhausted once B1-B6 all pass'
Assert-True (-not [bool]$sliceB.nextDetailedSliceReady) 'REAL005B should not keep a ready detailed slice after B1-B6 all pass'
foreach ($sliceId in @('REAL005B1','REAL005B2','REAL005B3','REAL005B4','REAL005B5','REAL005B6')) {
    Assert-True ($null -ne $sliceB.detailedSliceCoverage.$sliceId) "REAL005B detailed slice missing: $sliceId"
}
Assert-True ([string]$sliceB.detailedSliceCoverage.REAL005B1.status -eq 'pass') 'REAL005B1 should currently pass with RG003 coverage'
Assert-True ([string]$sliceB.detailedSliceCoverage.REAL005B2.status -eq 'pass') 'REAL005B2 should currently pass after repo-side answer anchor and hash proof'
Assert-True ([string]$sliceB.detailedSliceCoverage.REAL005B3.status -eq 'pass') 'REAL005B3 should pass after 2016-2025 source-region screenshot evidence is generated'
Assert-True ([string]$sliceB.detailedSliceCoverage.REAL005B4.status -eq 'pass') 'REAL005B4 should currently pass after structured-question coverage closes RG006'
Assert-True ([string]$sliceB.detailedSliceCoverage.REAL005B5.status -eq 'pass') 'REAL005B5 should currently pass after tagging/no-active-write coverage closes RG007'
Assert-True ([string]$sliceB.detailedSliceCoverage.REAL005B6.status -eq 'pass') 'REAL005B6 should pass once RG008 and RG009 are both proven'

$sliceC = $sliceCoverage.REAL005C
Assert-True ((@($sliceC.criteriaIds)) -contains 'RG010') 'REAL005C must include RG010'
Assert-True ((@($sliceC.criteriaIds)) -contains 'RG016') 'REAL005C must include RG016'
Assert-True ([string]$sliceC.status -eq 'partial') 'REAL005C should now be partial after RG010 passes while RG011-RG016 remain open'
Assert-True ($null -ne $sliceC.detailedSliceCoverage) 'REAL005C must expose detailedSliceCoverage'
Assert-True ([string]$sliceC.criteriaStatus.RG010 -eq 'pass') 'REAL005C must expose RG010 pass after the reviewed real question search/export smoke'
Assert-True ([string]$sliceC.criteriaStatus.RG011 -eq 'pass') 'REAL005C must expose RG011 pass after the reviewed real question analysis smoke'
Assert-True ([string]$sliceC.criteriaStatus.RG012 -eq 'pass') 'REAL005C must expose RG012 pass after the rollback/privacy/no-active-write report'
Assert-True ([string]$sliceC.criteriaStatus.RG013 -eq 'pass') 'REAL005C must expose RG013 pass after the layout/noise report'
Assert-True ([string]$sliceC.criteriaStatus.RG014 -eq 'pass') 'REAL005C must expose RG014 pass after the formula fidelity report'
Assert-True ([string]$sliceC.criteriaStatus.RG015 -eq 'pass') 'REAL005C must expose RG015 pass after the table structuring report'
Assert-True ([string]$sliceC.nextDetailedSlice -eq 'REAL005C5') 'REAL005C next detailed slice must now advance to REAL005C5'
Assert-True ([bool]$sliceC.nextDetailedSliceReady) 'REAL005C next detailed slice should become ready once REAL005B passes'

$sliceD = $sliceCoverage.REAL005D
Assert-True ((@($sliceD.criteriaIds)) -contains 'DOCS') 'REAL005D must include docs closeout marker'
Assert-True (@($sliceD.blockers).Count -ge 1) 'REAL005D must remain blocked while closureStatus is not_closed'

$nextDetailedOpen = $report.nextDetailedOpen
Assert-True ($null -ne $nextDetailedOpen) 'REAL005 report must expose nextDetailedOpen'
Assert-True ([string]$nextDetailedOpen.parentSlice -eq 'REAL005C') 'REAL005 nextDetailedOpen parent must currently be REAL005C'
Assert-True ([string]$nextDetailedOpen.sliceId -eq 'REAL005C5') 'REAL005 nextDetailedOpen slice must currently be REAL005C5'
Assert-True ([bool]$nextDetailedOpen.ready) 'REAL005 nextDetailedOpen must currently be actionable repo-side'

[ordered]@{
    status = 'pass'
    taskId = 'REAL005_SLICE_COVERAGE_CONTRACT'
    checkedAt = (Get-Date).ToString('s')
    reportPath = $ReportPath
    markdownReportPath = $MarkdownReportPath
    boundary = 'REAL005 report must expose closeout-slice level coverage so REAL005A/B/C/D can be advanced from evidence rather than prose-only interpretation'
} | ConvertTo-Json -Depth 5

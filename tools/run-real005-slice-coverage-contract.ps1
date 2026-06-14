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
Assert-True ([string]$sliceB.status -ne 'pass') 'REAL005B must not pass before per-question structure and review coverage is closed'

$sliceC = $sliceCoverage.REAL005C
Assert-True ((@($sliceC.criteriaIds)) -contains 'RG010') 'REAL005C must include RG010'
Assert-True ((@($sliceC.criteriaIds)) -contains 'RG016') 'REAL005C must include RG016'
Assert-True ([string]$sliceC.status -ne 'pass') 'REAL005C must not pass before usage/export/analysis coverage is closed'

$sliceD = $sliceCoverage.REAL005D
Assert-True ((@($sliceD.criteriaIds)) -contains 'DOCS') 'REAL005D must include docs closeout marker'
Assert-True (@($sliceD.blockers).Count -ge 1) 'REAL005D must remain blocked while closureStatus is not_closed'

[ordered]@{
    status = 'pass'
    taskId = 'REAL005_SLICE_COVERAGE_CONTRACT'
    checkedAt = (Get-Date).ToString('s')
    reportPath = $ReportPath
    markdownReportPath = $MarkdownReportPath
    boundary = 'REAL005 report must expose closeout-slice level coverage so REAL005A/B/C/D can be advanced from evidence rather than prose-only interpretation'
} | ConvertTo-Json -Depth 5

param(
    [string] $RoleMapPath = 'configs\knowledge\guangzhou-exam-source-role-map.json',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabaseUser = 'postgres',
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $ManifestPath = 'tmp\cek012\guangzhou-exam-evidence-index.json',
    [string] $ReportPath = 'docs\evidence\cek012-guangzhou-exam-evidence-index.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword $DatabasePassword
Assert-True (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'database password required'

$roleMap = [IO.Path]::GetFullPath((Join-Path $repoRoot $RoleMapPath))
$manifest = [IO.Path]::GetFullPath((Join-Path $repoRoot $ManifestPath))
$report = [IO.Path]::GetFullPath((Join-Path $repoRoot $ReportPath))
$connection = "host=$DatabaseHost port=$DatabasePort dbname=$DatabaseName user=$DatabaseUser"
$previousPassword = $env:PGPASSWORD
$env:PGPASSWORD = $DatabasePassword

Push-Location $repoRoot
try {
    python -m unittest tests.workers.test_guangzhou_exam_evidence_index
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-12 unit tests failed'

    python tools/guangzhou_exam_evidence_index.py `
        --role-map $roleMap `
        --connection-string $connection `
        --output $manifest `
        --report $report
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-12 evidence index generation failed'

    $summary = Get-Content -Raw $report | ConvertFrom-Json
    $index = Get-Content -Raw $manifest | ConvertFrom-Json
    Assert-True ($summary.status -eq 'pass') 'CEK-12 report status mismatch'
    Assert-True ($summary.questions -eq 234) 'CEK-12 question count mismatch'
    Assert-True ($index.blockers.Count -eq 0) 'CEK-12 blocker list is not empty'
    Assert-True ($index.sourceCoverage.paper.Count -eq 11) 'CEK-12 paper year coverage mismatch'
    Assert-True ($index.sourceCoverage.answer.Count -eq 11) 'CEK-12 answer year coverage mismatch'
    Assert-True ($index.sourceCoverage.report.Count -eq 11) 'CEK-12 report year coverage mismatch'
    Assert-True ($summary.readiness.questionCorpusReady -eq $true) 'CEK-12 question corpus is not ready for assessment-target extraction'
    Assert-True ($summary.readiness.assessmentTargetExtractionReady -eq $true) 'CEK-12 assessment-target extraction prerequisite mismatch'
    Assert-True ($summary.readiness.questionCount -eq 234) 'CEK-12 readiness question count mismatch'
    Assert-True ($summary.readiness.stemCount -eq 234) 'CEK-12 readiness stem count mismatch'
    Assert-True ($summary.readiness.answerContentCount -eq 234) 'CEK-12 readiness answer content count mismatch'
    Assert-True ($summary.readiness.paperAnchorCount -eq 234) 'CEK-12 readiness paper anchor count mismatch'
    Assert-True ($summary.readiness.answerAnchorCount -eq 234) 'CEK-12 readiness answer anchor count mismatch'
    Assert-True ($summary.databaseWrite -eq $false) 'CEK-12 must remain read-only'
    Assert-True ($summary.activeWrite -eq $false) 'CEK-12 must not write active data'

    $summary | ConvertTo-Json -Depth 20
}
finally {
    $env:PGPASSWORD = $previousPassword
    Pop-Location
}

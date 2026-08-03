param(
    [string] $ScopePath = 'tmp\cek010\question-scope-manifest.json',
    [string] $AlignmentPath = 'tmp\cek013\guangzhou-three-source-alignment.candidate.json',
    [string] $OutputPath = 'tmp\cek014\assessment-targets.candidate.json',
    [string] $SchemaPath = 'schemas\ai\assessment_target_extraction.schema.json',
    [string] $EvalPath = 'configs\ai-evals\assessment-target-extraction.sample.json',
    [string] $ReportPath = 'docs\evidence\cek014-assessment-target-extraction-eval.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

Push-Location $repoRoot
try {
    python -m unittest tests.workers.test_assessment_target_extraction
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-14 unit tests failed'

    python tools/assessment_target_extraction.py `
        --scopes $ScopePath --alignments $AlignmentPath `
        --output $OutputPath --report $ReportPath
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-14 candidate generation failed'

    $json = Get-Content -Raw $OutputPath
    Assert-True ($json | Test-Json -SchemaFile $SchemaPath) 'CEK-14 output schema validation failed'
    $eval = Get-Content -Raw $EvalPath | ConvertFrom-Json
    Assert-True ($eval.allowRealModelCalls -eq $false) 'CEK-14 eval must not allow real model calls'
    $report = Get-Content -Raw $ReportPath | ConvertFrom-Json
    Assert-True ($report.status -eq 'pass') 'CEK-14 report status mismatch'
    Assert-True ($report.targetCandidates -eq 444) 'CEK-14 target scope count mismatch'
    Assert-True ($report.reviewItems -eq 444) 'CEK-14 review queue count mismatch'
    Assert-True ($report.externalModelCalls -eq 0) 'CEK-14 unexpectedly called an external model'
    $report | ConvertTo-Json -Depth 20
}
finally {
    Pop-Location
}

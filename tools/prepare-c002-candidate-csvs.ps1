param(
    [string] $InputDir = 'c002-k12-question-graph-candidate-csvs',
    [string] $OutputDir = 'c002-k12-question-graph-candidate-csvs\cleaned',
    [string] $ReportPath = 'c002-k12-question-graph-candidate-csvs\cleaned\validation-report.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

Push-Location $repoRoot
try {
    python tools/prepare_c002_candidate_csvs.py --input-dir $InputDir --output-dir $OutputDir --report-path $ReportPath
    if ($LASTEXITCODE -ne 0) {
        throw "prepare_c002_candidate_csvs.py failed"
    }
}
finally {
    Pop-Location
}

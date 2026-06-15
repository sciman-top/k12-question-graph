param(
    [string] $ReportPath = '',
    [string] $MarkdownReportPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runDate = Get-Date -Format 'yyyyMMdd'

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = ('docs/evidence/{0}-real005b-question-structure-diagnostics.json' -f $runDate)
}

if ([string]::IsNullOrWhiteSpace($MarkdownReportPath)) {
    $MarkdownReportPath = ('docs/evidence/{0}-real005b-question-structure-diagnostics.md' -f $runDate)
}

Push-Location $repoRoot
try {
    & pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-real005b-source-region-screenshots.ps1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "REAL005B source-region screenshot evidence failed with exit code $LASTEXITCODE"
    }
    & pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-real005b-structured-question-diagnostics.ps1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "REAL005B structured question evidence failed with exit code $LASTEXITCODE"
    }

    $env:PYTHONIOENCODING = 'utf-8'
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

    & python tools/real005b_question_structure_diagnostics.py `
        --output $ReportPath `
        --markdown-output $MarkdownReportPath
    if ($LASTEXITCODE -ne 0) {
        throw "REAL005B question structure diagnostics failed with exit code $LASTEXITCODE"
    }

    $report = Get-Content -LiteralPath (Join-Path $repoRoot $ReportPath) -Raw | ConvertFrom-Json
    if ($report.status -ne 'pass') {
        throw "expected REAL005B diagnostics status=pass, got $($report.status)"
    }
    if (@($report.criteriaIds).Count -ne 7) {
        throw "expected 7 REAL005B criteria rows, got $(@($report.criteriaIds).Count)"
    }
    if ($report.criteria.RG003.status -ne 'pass') {
        throw "expected RG003 question count coverage to pass, got $($report.criteria.RG003.status)"
    }
    if ($report.criteria.RG004.status -ne 'pass') {
        throw "expected RG004 answer alignment coverage to pass after repo-side anchor/hash proof, got $($report.criteria.RG004.status)"
    }
    if ($report.real005BStatus -eq 'pass') {
        throw 'REAL005B must not pass until RG004-RG009 all have per-question review/source evidence'
    }
    if ($report.activeWrite -ne $false -or $report.externalAiCalls -ne 0 -or $report.realStudentDataUsed -ne $false) {
        throw 'REAL005B diagnostics must stay read-only with no external AI or real student data'
    }

    $report | ConvertTo-Json -Depth 12
}
finally {
    Pop-Location
}

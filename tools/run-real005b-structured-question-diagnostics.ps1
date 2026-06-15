param(
    [string] $ReportPath = '',
    [string] $MarkdownReportPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runDate = Get-Date -Format 'yyyyMMdd'

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = ('docs/evidence/{0}-real005b-structured-question-diagnostics.json' -f $runDate)
}

if ([string]::IsNullOrWhiteSpace($MarkdownReportPath)) {
    $MarkdownReportPath = ('docs/evidence/{0}-real005b-structured-question-diagnostics.md' -f $runDate)
}

Push-Location $repoRoot
try {
    $env:PYTHONIOENCODING = 'utf-8'
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

    & python tools/real005b_structured_question_diagnostics.py `
        --output $ReportPath `
        --markdown-output $MarkdownReportPath
    if ($LASTEXITCODE -ne 0) {
        throw "REAL005B structured question diagnostics failed with exit code $LASTEXITCODE"
    }

    $report = Get-Content -LiteralPath (Join-Path $repoRoot $ReportPath) -Raw | ConvertFrom-Json
    if ($report.status -ne 'pass') {
        throw "expected REAL005B structured question diagnostics status=pass, got $($report.status)"
    }
    if (@($report.years).Count -ne 10) {
        throw "expected 10 yearly structured question rows, got $(@($report.years).Count)"
    }
    if ($report.structuredQuestionCoveragePass -ne $true) {
        throw 'REAL005B structured question coverage must pass'
    }
    if ($report.activeWrite -ne $false -or $report.externalAiCalls -ne 0 -or $report.realStudentDataUsed -ne $false) {
        throw 'REAL005B structured question evidence must stay read-only'
    }

    $report | ConvertTo-Json -Depth 12
}
finally {
    Pop-Location
}

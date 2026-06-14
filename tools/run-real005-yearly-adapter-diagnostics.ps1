param(
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [string] $ReportPath = '',
    [string] $MarkdownReportPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runDate = Get-Date -Format 'yyyyMMdd'

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = ('docs/evidence/{0}-real005-yearly-adapter-diagnostics.json' -f $runDate)
}

if ([string]::IsNullOrWhiteSpace($MarkdownReportPath)) {
    $MarkdownReportPath = ('docs/evidence/{0}-real005-yearly-adapter-diagnostics.md' -f $runDate)
}

Push-Location $repoRoot
try {
    $env:PYTHONIOENCODING = 'utf-8'
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

    & python tools/real005_yearly_adapter_diagnostics.py `
        --file-root $FileStoreRoot `
        --output $ReportPath `
        --markdown-output $MarkdownReportPath
    if ($LASTEXITCODE -ne 0) {
        throw "REAL005 yearly adapter diagnostics failed with exit code $LASTEXITCODE"
    }

    $report = Get-Content -LiteralPath (Join-Path $repoRoot $ReportPath) -Raw | ConvertFrom-Json
    if ($report.status -ne 'pass') {
        throw "expected yearly adapter diagnostics status=pass, got $($report.status)"
    }
    if (@($report.years).Count -ne 11) {
        throw "expected 11 yearly diagnostic rows, got $(@($report.years).Count)"
    }
    if (@($report.blockedYears).Count -ne 0) {
        throw "yearly adapter diagnostics blocked years: $(@($report.blockedYears) -join ',')"
    }
    if ($report.activeWrite -ne $false -or $report.externalAiCalls -ne 0 -or $report.realStudentDataUsed -ne $false) {
        throw 'yearly adapter diagnostics must stay read-only with no external AI or real student data'
    }

    $report | ConvertTo-Json -Depth 12
}
finally {
    Pop-Location
}

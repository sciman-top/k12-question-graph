param(
    [ValidateSet('list', 'quick', 'roadmap', 'ui', 'pqr', 'full')]
    [string] $Group = 'list'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$results = New-Object System.Collections.Generic.List[object]

function Invoke-GateCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [Parameter(Mandatory = $true)]
        [scriptblock] $Script
    )

    $started = Get-Date
    try {
        & $Script
        $results.Add([ordered]@{
            name = $Name
            status = 'pass'
            durationMs = [int]((Get-Date) - $started).TotalMilliseconds
        })
    }
    catch {
        $results.Add([ordered]@{
            name = $Name
            status = 'fail'
            durationMs = [int]((Get-Date) - $started).TotalMilliseconds
            error = $_.Exception.Message
        })
        throw
    }
}

function Invoke-QuickGroup {
    Invoke-GateCommand 'c002 dry-run suite' {
        & (Join-Path $PSScriptRoot 'run-c002-dry-run-suite.ps1') | Write-Host
    }
    Invoke-GateCommand 'roadmap guard' {
        & (Join-Path $PSScriptRoot 'run-roadmap-guard.ps1') | Write-Host
    }
}

function Invoke-RoadmapGroup {
    Invoke-GateCommand 'roadmap guard' {
        & (Join-Path $PSScriptRoot 'run-roadmap-guard.ps1') | Write-Host
    }
    Invoke-GateCommand 's001 completion-state dashboard' {
        & (Join-Path $PSScriptRoot 'run-s001-completion-state-dashboard.ps1') | Write-Host
    }
    Invoke-GateCommand 's0 execution plan guard' {
        & (Join-Path $PSScriptRoot 'run-s0-execution-plan-guard.ps1') | Write-Host
    }
    Invoke-GateCommand 'automation-first feature contract guard' {
        & (Join-Path $PSScriptRoot 'run-automation-first-feature-contract-guard.ps1') | Write-Host
    }
    Invoke-GateCommand 'reference-basis diff-aware contract' {
        & (Join-Path $PSScriptRoot 'run-reference-basis-diff-aware-contract.ps1') | Write-Host
    }
    Invoke-GateCommand 'non-site implementation plan guard' {
        & (Join-Path $PSScriptRoot 'run-non-site-implementation-plan-guard.ps1') | Write-Host
    }
}

function Invoke-UiGroup {
    foreach ($scriptName in @(
        'run-i001-teacher-home-ui-contract.ps1',
        'run-i002-import-wizard-ui-contract.ps1',
        'run-i003-review-queue-ui-contract.ps1',
        'run-i004-paper-workbench-ui-contract.ps1',
        'run-i005-score-analysis-workbench-ui-contract.ps1',
        'run-i006-starter-defaults-ui-contract.ps1',
        'run-i007-frontend-boundary-contract.ps1',
        'run-i008-teacher-simplification-contract.ps1'
    )) {
        Invoke-GateCommand ($scriptName -replace '^run-', '' -replace '\.ps1$', '') {
            & (Join-Path $PSScriptRoot $scriptName) | Write-Host
        }
    }
}

function Invoke-PqrGroup {
    $reportRoot = 'tmp/gate-group-pqr'
    New-Item -ItemType Directory -Path (Join-Path $repoRoot $reportRoot) -Force | Out-Null
    Invoke-GateCommand 'p0-live-preflight-refresh-path-contract' {
        & (Join-Path $PSScriptRoot 'run-p0-live-preflight-refresh-path-contract.ps1') | Write-Host
    }
    Invoke-GateCommand 'repo-side-guard-fresh-report-path-contract' {
        & (Join-Path $PSScriptRoot 'run-repo-side-guard-fresh-report-path-contract.ps1') | Write-Host
    }
    Invoke-GateCommand 'pqr-full-gate-path-contract' {
        & (Join-Path $PSScriptRoot 'run-pqr-full-gate-path-contract.ps1') | Write-Host
    }
    Invoke-GateCommand 'live-pilot-closeout-import-contract' {
        & (Join-Path $PSScriptRoot 'run-live-pilot-closeout-import-contract.ps1') | Write-Host
    }
    Invoke-GateCommand 'real005-report-write-lock-contract' {
        & (Join-Path $PSScriptRoot 'run-real005-report-write-lock-contract.ps1') | Write-Host
    }
    Invoke-GateCommand 'real005-slice-coverage-contract' {
        $real005JsonPath = Join-Path $reportRoot 'real005-closure-standard-report.json'
        $real005MarkdownPath = Join-Path $reportRoot 'real005-closure-standard-report.md'
        & (Join-Path $PSScriptRoot 'run-real005-slice-coverage-contract.ps1') `
            -ReportPath $real005JsonPath `
            -MarkdownReportPath $real005MarkdownPath | Write-Host
    }
    Invoke-GateCommand 'real005b-question-structure-diagnostics' {
        & (Join-Path $PSScriptRoot 'run-real005b-question-structure-diagnostics.ps1') `
            -ReportPath (Join-Path $reportRoot 'real005b-question-structure-diagnostics.json') `
            -MarkdownReportPath (Join-Path $reportRoot 'real005b-question-structure-diagnostics.md') | Write-Host
    }
    Invoke-GateCommand 'pqr-preflight-pack-contract' {
        & (Join-Path $PSScriptRoot 'run-pqr-preflight-pack-contract.ps1') `
            -ReportPath (Join-Path $reportRoot 'pqr-preflight-pack-report.json') | Write-Host
    }
    Invoke-GateCommand 'pqr-preflight-freshness-guard' {
        & (Join-Path $PSScriptRoot 'run-pqr-preflight-freshness-guard.ps1') `
            -ReportPath (Join-Path $reportRoot 'pqr-preflight-freshness-report.json') | Write-Host
    }
    Invoke-GateCommand 'pqr-preflight-dashboard-contract' {
        & (Join-Path $PSScriptRoot 'run-pqr-preflight-dashboard-contract.ps1') `
            -DashboardJsonPath (Join-Path $reportRoot 'pqr-preflight-dashboard.json') `
            -DashboardMarkdownPath (Join-Path $reportRoot 'pqr-preflight-dashboard.md') | Write-Host
    }
    Invoke-GateCommand 'repo-preflight-local-api-detection-contract' {
        & (Join-Path $PSScriptRoot 'run-repo-preflight-local-api-detection-contract.ps1') `
            -ReportPath (Join-Path $reportRoot 'repo-preflight-local-api-detection-contract.json') | Write-Host
    }
    Invoke-GateCommand 'pqr-orchestration-consistency-guard' {
        & (Join-Path $PSScriptRoot 'run-pqr-orchestration-consistency-guard.ps1') `
            -ReportPath (Join-Path $reportRoot 'pqr-orchestration-consistency-report.json') | Write-Host
    }
}

Push-Location $repoRoot
try {
    switch ($Group) {
        'list' {
            [ordered]@{
                status = 'pass'
                groups = @(
                    [ordered]@{ name = 'quick'; description = 'Database-free C002 daily feedback plus roadmap guard.' },
                    [ordered]@{ name = 'roadmap'; description = 'Roadmap, completion-state, S0 plan, automation-first, and non-site implementation guards.' },
                    [ordered]@{ name = 'ui'; description = 'Teacher-facing UI source-contract guards I001-I008.' },
                    [ordered]@{ name = 'pqr'; description = 'P/Q/R preflight pack, report-write lock, freshness, dashboard, and orchestration guards.' },
                    [ordered]@{ name = 'full'; description = 'Fallback to tools/run-gates.ps1 without changing full-gate semantics.' }
                )
            } | ConvertTo-Json -Depth 5
            return
        }
        'quick' { Invoke-QuickGroup }
        'roadmap' { Invoke-RoadmapGroup }
        'ui' { Invoke-UiGroup }
        'pqr' { Invoke-PqrGroup }
        'full' {
            Invoke-GateCommand 'full fallback run-gates' {
                & (Join-Path $PSScriptRoot 'run-gates.ps1') | Write-Host
            }
        }
    }

    [ordered]@{
        status = 'pass'
        group = $Group
        steps = $results
    } | ConvertTo-Json -Depth 6
}
finally {
    Pop-Location
}

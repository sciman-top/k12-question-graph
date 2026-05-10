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
    foreach ($scriptName in @(
        'run-pqr-preflight-pack-contract.ps1',
        'run-pqr-preflight-freshness-guard.ps1',
        'run-pqr-preflight-dashboard-contract.ps1',
        'run-pqr-orchestration-consistency-guard.ps1'
    )) {
        Invoke-GateCommand ($scriptName -replace '^run-', '' -replace '\.ps1$', '') {
            & (Join-Path $PSScriptRoot $scriptName) | Write-Host
        }
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
                    [ordered]@{ name = 'roadmap'; description = 'Roadmap, completion-state, S0 plan, and automation-first guards.' },
                    [ordered]@{ name = 'ui'; description = 'Teacher-facing UI source-contract guards I001-I008.' },
                    [ordered]@{ name = 'pqr'; description = 'P/Q/R preflight pack, freshness, dashboard, and orchestration guards.' },
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

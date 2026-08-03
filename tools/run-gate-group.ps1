param(
    [ValidateSet('list', 'quick', 'roadmap', 'ui', 'full', 'legacy-audit')]
    [string] $Group = 'list',
    [switch] $AuthorizeStateful
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
    Invoke-GateCommand 'reference-basis adoption record contract' {
        & (Join-Path $PSScriptRoot 'run-reference-basis-adoption-record-contract.ps1') | Write-Host
    }
    Invoke-GateCommand 'reference-basis onsite adoption contract' {
        & (Join-Path $PSScriptRoot 'run-reference-basis-onsite-adoption-contract.ps1') | Write-Host
    }
    Invoke-GateCommand 'non-site implementation plan guard' {
        & (Join-Path $PSScriptRoot 'run-non-site-implementation-plan-guard.ps1') | Write-Host
    }
}

function Invoke-UiGroup {
    Invoke-GateCommand 'ui behavior contract guard' {
        & (Join-Path $PSScriptRoot 'run-ui-behavior-contract-guard.ps1') `
            -JsonReportPath 'tmp/gate-group-ui/ui-behavior-contract.json' | Write-Host
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
                    [ordered]@{ name = 'ui'; description = 'Teacher-facing behavior tests plus the reviewed legacy-to-behavior coverage map.' },
                    [ordered]@{ name = 'full'; description = 'Default focused Release core; requires -AuthorizeStateful.' },
                    [ordered]@{ name = 'legacy-audit'; description = 'Optional compatibility audit; never part of default Release.' }
                )
            } | ConvertTo-Json -Depth 5
            return
        }
        'quick' { Invoke-QuickGroup }
        'roadmap' { Invoke-RoadmapGroup }
        'ui' { Invoke-UiGroup }
        'full' {
            Invoke-GateCommand 'focused release core' {
                & (Join-Path $PSScriptRoot 'run-verification.ps1') -Profile Release -AuthorizeStateful:$AuthorizeStateful -ReportRoot 'tmp/gate-group-release' | Write-Host
            }
        }
        'legacy-audit' {
            Invoke-GateCommand 'explicit legacy compatibility audit' {
                & (Join-Path $PSScriptRoot 'run-verification.ps1') -Profile Release -AuthorizeStateful:$AuthorizeStateful -IncludeLegacyCompatibility -ReportRoot 'tmp/gate-group-legacy-audit' | Write-Host
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

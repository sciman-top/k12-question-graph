$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$results = New-Object System.Collections.Generic.List[object]

function Invoke-SuiteStep([string] $Name, [scriptblock] $Script) {
    $started = Get-Date
    try {
        & $Script | Write-Host
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

Push-Location $repoRoot
try {
    Invoke-SuiteStep 'c002 source material admission guard' {
        .\tools\run-c002-source-material-guard.ps1
    }

    Invoke-SuiteStep 'c002b replacement mapping contract' {
        .\tools\run-c002b-replacement-mapping-contract.ps1
    }

    Invoke-SuiteStep 'c002c migration impact contract' {
        .\tools\run-c002c-migration-impact-contract.ps1
    }

    Invoke-SuiteStep 'c002d source-derived admission contract' {
        .\tools\run-c002d-source-derived-admission-contract.ps1
    }

    Invoke-SuiteStep 'c002e activation guard contract' {
        .\tools\run-c002e-activation-guard-contract.ps1
    }

    [ordered]@{
        status = 'pass'
        suite = 'c002-dynamic-assets-dry-run'
        steps = $results
        databaseRequired = $false
        productionActivationAllowed = $false
    } | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}

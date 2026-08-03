param(
    [string] $ReportPath = 'tmp/verification/ns104-endpoint-source-tests/report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path

Push-Location $repoRoot
try {
    & (Join-Path $repoRoot 'tools/run-ns104-application-service-boundary.ps1') -ReportPath $ReportPath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "NS104 guard failed with exit code $LASTEXITCODE"
    }

    $report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
    $scoreImport = @($report.serviceBackedEndpoints | Where-Object { $_.route -eq '/score-imports' })
    if ($scoreImport.Count -ne 1) {
        throw 'expected exactly one /score-imports endpoint result'
    }
    if ($scoreImport[0].sourcePath -ne 'apps/api/Endpoints/ScoreEndpoints.cs') {
        throw "unexpected /score-imports source: $($scoreImport[0].sourcePath)"
    }
    if (-not $scoreImport[0].pass) {
        throw '/score-imports service boundary did not pass'
    }

    [pscustomobject]@{
        status = 'pass'
        route = $scoreImport[0].route
        sourcePath = $scoreImport[0].sourcePath
        assertion = 'modularized endpoint source is discovered without weakening service-boundary checks'
    } | ConvertTo-Json
}
finally {
    Pop-Location
}

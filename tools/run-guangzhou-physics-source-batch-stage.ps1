param(
    [string] $SourceRoot = 'D:\KQG_Data\guangzhou_physics_2015_2025',
    [string] $DestinationRoot = 'D:\KQG_Data\source_materials\imported\guangzhou_physics_2015_2025\20260726-v2\raw',
    [string] $ReportPath = 'docs\evidence\20260726-guangzhou-physics-source-batch-stage.json',
    [string] $InventoryCsvPath = 'docs\evidence\20260726-guangzhou-physics-source-batch-inventory.csv',
    [switch] $Apply,
    [switch] $Rollback,
    [switch] $ValidateRollback,
    [switch] $RefreshInventory
)

$ErrorActionPreference = 'Stop'
$env:PYTHONIOENCODING = 'utf-8'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

$selectedModes = @($Apply.IsPresent, $Rollback.IsPresent, $ValidateRollback.IsPresent, $RefreshInventory.IsPresent)
if (@($selectedModes | Where-Object { $_ }).Count -gt 1) {
    throw '-Apply, -Rollback, -ValidateRollback, and -RefreshInventory are mutually exclusive'
}

Push-Location $repoRoot
try {
    $arguments = @(
        'tools\guangzhou_physics_source_batch.py',
        '--source-root', $SourceRoot,
        '--destination-root', $DestinationRoot,
        '--report', $ReportPath,
        '--inventory-csv', $InventoryCsvPath
    )
    if ($Apply) {
        $arguments += '--apply'
    }
    elseif ($Rollback) {
        $arguments += '--rollback'
    }
    elseif ($ValidateRollback) {
        $arguments += '--validate-rollback'
    }
    elseif ($RefreshInventory) {
        $arguments += '--refresh-inventory'
    }

    & python @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Guangzhou physics source batch stage failed with exit code $LASTEXITCODE"
    }

    $report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
    if ($report.status -ne 'pass' -or $report.physicalFileCount -ne 33 -or $report.logicalSourceCount -ne 33) {
        throw 'Source batch report did not satisfy the 33 physical / 33 logical source contract'
    }
    if ($report.pdfIntegrityPass -ne $true -or $report.yearsCovered.Count -ne 11) {
        throw 'Source batch report did not satisfy PDF integrity or 2015-2025 coverage'
    }
    if (($Apply -or $Rollback) -and ($report.hashParityChecked -ne $true -or $report.hashParityPass -ne $true)) {
        throw 'Source batch move did not satisfy hash parity'
    }
}
finally {
    Pop-Location
}

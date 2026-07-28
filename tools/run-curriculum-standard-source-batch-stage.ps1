param(
    [string] $SourceFile = 'D:\KQG_Data\source_materials\imported\《义务教育物理课程标准·日常修订版》(2022年版2025年修订).pdf',
    [string] $DestinationRoot = 'D:\KQG_Data\source_materials\imported\curriculum_standards\physics\junior_middle_school\2022-2025-revision\raw',
    [string] $ManifestPath = 'configs\knowledge\source-material-manifest.local.json',
    [string] $ReportPath = '',
    [string] $InventoryCsvPath = '',
    [switch] $Apply,
    [switch] $Rollback,
    [switch] $ValidateRollback
)

$ErrorActionPreference = 'Stop'
$env:PYTHONIOENCODING = 'utf-8'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

$selectedModes = @($Apply.IsPresent, $Rollback.IsPresent, $ValidateRollback.IsPresent)
if (@($selectedModes | Where-Object { $_ }).Count -gt 1) {
    throw '-Apply, -Rollback, and -ValidateRollback are mutually exclusive'
}

$modeName = if ($Apply) { 'apply' } elseif ($Rollback) { 'rollback' } elseif ($ValidateRollback) { 'rollback-validation' } else { 'dry-run' }
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = if ($Apply) {
        'docs\evidence\cek002-curriculum-standard-migration.json'
    }
    elseif ($Rollback) {
        'docs\evidence\cek002-curriculum-standard-rollback.json'
    }
    elseif ($ValidateRollback) {
        'docs\evidence\cek002-curriculum-standard-rollback-validation.json'
    }
    else {
        'docs\evidence\cek001-curriculum-standard-source-batch.json'
    }
}
if ([string]::IsNullOrWhiteSpace($InventoryCsvPath)) {
    $InventoryCsvPath = "docs\evidence\cek001-curriculum-standard-source-inventory-$modeName.csv"
}

Push-Location $repoRoot
try {
    & git check-ignore --quiet -- $ManifestPath
    if ($LASTEXITCODE -ne 0) {
        throw "Local source manifest must be ignored by git: $ManifestPath"
    }

    $arguments = @(
        'tools\curriculum_standard_source_batch.py',
        '--source-file', $SourceFile,
        '--destination-root', $DestinationRoot,
        '--manifest', $ManifestPath,
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

    & python @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Curriculum standard source batch stage failed with exit code $LASTEXITCODE"
    }

    $report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
    $expectedHash = 'e00a5665e7e17ea6bdd6236d9366c51c63bbe6cc0eabf83ac3d0a529c487dd8c'
    if ($report.status -ne 'pass' -or $report.materialId -ne 'curriculum-physics-junior-2022-2025-revision') {
        throw 'Curriculum standard report did not satisfy the fixed material identity contract'
    }
    if ($report.physicalFileCount -ne 1 -or $report.inventory.pageCount -ne 67 -or $report.inventory.textCharacterCount -ne 37615) {
        throw 'Curriculum standard report did not satisfy the one-file, 67-page OCR text contract'
    }
    if ($report.inventory.sha256 -ne $expectedHash -or $report.pdfIntegrityPass -ne $true -or $report.textLayerPass -ne $true) {
        throw 'Curriculum standard report did not satisfy PDF integrity, text-layer, or hash facts'
    }
    if ($report.databaseWrite -ne $false -or $report.fileStoreWrite -ne $false -or $report.c002ActiveWrite -ne $false) {
        throw 'Curriculum standard staging unexpectedly reported a database, FileStore, or active write'
    }
    if (($Apply -or $Rollback) -and ($report.hashParityChecked -ne $true -or $report.hashParityPass -ne $true)) {
        throw 'Curriculum standard file move did not satisfy hash parity'
    }
}
finally {
    Pop-Location
}

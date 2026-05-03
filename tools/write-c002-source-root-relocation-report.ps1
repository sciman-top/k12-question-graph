param(
    [string] $SourceRoot = 'D:\KQG_Data\source_materials\imported\guangzhou_physics_2016_2025',
    [string] $PreviousSourceRoot = 'D:\CODE\k12-question-graph\广州中考',
    [string] $ReportPath = 'docs\evidence\c002-source-root-relocation-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$reportFullPath = Join-Path $repoRoot $ReportPath

if (-not (Test-Path -LiteralPath $SourceRoot)) {
    throw "C002 source root does not exist: $SourceRoot"
}

$files = @(Get-ChildItem -LiteralPath $SourceRoot -File -Recurse | Sort-Object FullName)
if ($files.Count -ne 33) {
    throw "Expected 33 C002 source files, got $($files.Count)"
}

$entries = @($files | ForEach-Object {
    $hash = Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
    [ordered]@{
        relativePath = [System.IO.Path]::GetRelativePath($SourceRoot, $_.FullName).Replace('\', '/')
        bytes = $_.Length
        sha256 = $hash.Hash.ToLowerInvariant()
    }
})

$report = [ordered]@{
    status = 'pass'
    task = 'C002_SOURCE_ROOT_RELOCATION'
    previousSourceRoot = $PreviousSourceRoot
    canonicalSourceRoot = $SourceRoot
    fileCount = $files.Count
    totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
    gitPolicy = 'raw PDF source materials stay outside git under D:\KQG_Data; structured C003 CSV/PDF evidence package remains in repo'
    importStatus = 'already imported into SourceDocument/FileAsset; relocation preserves raw re-import source only'
    files = $entries
}

New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
$report | ConvertTo-Json -Depth 4

param(
    [string] $ExternalManifestPath = 'D:\CODE\external\k12-question-graph-references\references.manifest.json',
    [string] $RequirementsPath = 'tasks/reference-basis-requirements.csv',
    [string] $ModuleMapPath = 'tasks/reference-basis-module-map.csv',
    [string] $SnapshotManifestPath = 'sources/reference-shelf.manifest.snapshot.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Resolve-RepoPath([string] $Path) {
    Join-Path $repoRoot $Path
}

function Split-Values([string] $Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    return @(
        $Value.Split(';') |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

$externalManifestFullPath = $ExternalManifestPath
$requirementsFullPath = Resolve-RepoPath $RequirementsPath
$moduleMapFullPath = Resolve-RepoPath $ModuleMapPath
$snapshotManifestFullPath = Resolve-RepoPath $SnapshotManifestPath

foreach ($path in @($externalManifestFullPath, $requirementsFullPath, $moduleMapFullPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "missing required file: $path"
    }
}

$externalManifest = Get-Content -LiteralPath $externalManifestFullPath -Raw | ConvertFrom-Json
$requirementsRows = @(Import-Csv -LiteralPath $requirementsFullPath -Encoding UTF8)
$moduleRows = @(Import-Csv -LiteralPath $moduleMapFullPath -Encoding UTF8)

$mandatoryByPath = @{}
foreach ($row in @($requirementsRows + $moduleRows)) {
    $taskIds = if ($row.PSObject.Properties.Name -contains 'task_ids') {
        Split-Values ([string] $row.task_ids)
    }
    else {
        @([string] $row.task_id)
    }

    foreach ($relativePath in (@(Split-Values ([string] $row.local_reference_paths)) + @(Split-Values ([string] $row.community_reference_paths)))) {
        if (-not $mandatoryByPath.ContainsKey($relativePath)) {
            $mandatoryByPath[$relativePath] = New-Object System.Collections.Generic.HashSet[string]
        }

        foreach ($taskId in $taskIds) {
            $null = $mandatoryByPath[$relativePath].Add($taskId)
        }
    }
}

$snapshotEntries = foreach ($entry in $externalManifest.entries) {
    $relativePath = [string] $entry.relativePath
    $taskIds = @()
    if ($mandatoryByPath.ContainsKey($relativePath)) {
        $taskIds = @($mandatoryByPath[$relativePath] | Sort-Object)
    }

    [ordered]@{
        group = [string] $entry.group
        category = [string] $entry.category
        relativePath = $relativePath
        upstream = [string] $entry.upstream
        lastVerifiedCommit = [string] $entry.lastVerifiedCommit
        notes = [string] $entry.notes
        mandatoryOnUse = if (([string] $entry.group) -eq 'optional' -and $taskIds.Count -gt 0) { $true } else { $null }
        mandatoryOnUseTaskIds = if (([string] $entry.group) -eq 'optional' -and $taskIds.Count -gt 0) { [string[]] $taskIds } else { $null }
    }
}

$snapshot = [ordered]@{
    schemaVersion = 1
    capturedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    source = $ExternalManifestPath
    entries = $snapshotEntries
}

New-Item -ItemType Directory -Path (Split-Path -Parent $snapshotManifestFullPath) -Force | Out-Null
$snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $snapshotManifestFullPath -Encoding UTF8
$snapshot | ConvertTo-Json -Depth 8

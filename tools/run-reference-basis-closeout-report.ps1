param(
    [string] $JsonReportPath = '',
    [string] $MarkdownReportPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$today = Get-Date -Format 'yyyyMMdd'

if ([string]::IsNullOrWhiteSpace($JsonReportPath)) {
    $JsonReportPath = "docs/evidence/$today-reference-basis-preflight-closeout.json"
}

if ([string]::IsNullOrWhiteSpace($MarkdownReportPath)) {
    $MarkdownReportPath = "docs/evidence/$today-reference-basis-preflight-closeout.md"
}

function Resolve-RepoPath([string] $Path) {
    Join-Path $repoRoot $Path
}

function Get-RepoRelativePath([string] $FullPath) {
    return Normalize-RepoPath ([System.IO.Path]::GetRelativePath($repoRoot, $FullPath))
}

function Normalize-RepoPath([string] $Path) {
    return ($Path -replace '\\', '/').Trim()
}

function Test-PathInSet([string] $Path, [System.Collections.Generic.HashSet[string]] $Set) {
    return $Set.Contains((Normalize-RepoPath $Path))
}

function Test-WildcardMatch([string] $Path, [string[]] $Patterns) {
    foreach ($pattern in $Patterns) {
        if ($Path -like $pattern) {
            return $true
        }
    }

    return $false
}

function ConvertTo-MarkdownRows($Entries) {
    $Entries = @($Entries)
    $rows = New-Object System.Collections.Generic.List[string]

    if ($Entries.Count -eq 0) {
        return @('- none')
    }

    $rows.Add('| Path | Git Status |')
    $rows.Add('| --- | --- |')
    foreach ($entry in ($Entries | Sort-Object path)) {
        $rows.Add("| $($entry.path) | $($entry.gitStatus) |")
    }

    return $rows.ToArray()
}

$dedicatedSlicePaths = @(
    '.github/workflows/repo-preflight.yml',
    'sources/reference-shelf.manifest.snapshot.json',
    'tasks/reference-basis-module-map.csv',
    'tasks/reference-basis-requirements.csv',
    'tools/run-reference-basis-guard.ps1',
    'tools/run-repo-preflight.ps1',
    'tools/run-reference-basis-closeout-report.ps1',
    'tools/sync-reference-shelf-snapshot.ps1'
)

$sharedTouchpointPaths = @(
    'README.md',
    'docs/26_References.md',
    'docs/111_ProjectNavigationOverview.md',
    'sources/references.md',
    'tools/README.md',
    'tools/run-gates.ps1'
)

$retainedEvidencePaths = @(
    'docs/evidence/20260609-reference-basis-guard.json',
    'docs/evidence/20260609-reference-basis-guard.md'
)

$retainedEvidencePatterns = @(
    'docs/evidence/*-reference-basis-guard.json',
    'docs/evidence/*-reference-basis-guard.md'
)

$generatedThisRunPaths = @(
    (Normalize-RepoPath $JsonReportPath),
    (Normalize-RepoPath $MarkdownReportPath)
)

$temporaryDirtyPatterns = @(
    'tmp/*',
    'apps/web/node_modules_broken_*'
)

$dedicatedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$sharedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$retainedEvidenceSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$generatedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($path in $dedicatedSlicePaths) {
    $null = $dedicatedSet.Add((Normalize-RepoPath $path))
}
foreach ($path in $sharedTouchpointPaths) {
    $null = $sharedSet.Add((Normalize-RepoPath $path))
}
foreach ($path in $retainedEvidencePaths) {
    $null = $retainedEvidenceSet.Add((Normalize-RepoPath $path))
}
foreach ($path in $generatedThisRunPaths) {
    $null = $generatedSet.Add((Normalize-RepoPath $path))
}

$gitStatusLines = @(git -C $repoRoot status --short --untracked-files=all)
if ($LASTEXITCODE -ne 0) {
    throw 'git status --short failed'
}

$dirtyEntries = New-Object System.Collections.Generic.List[object]
foreach ($line in $gitStatusLines) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) {
        continue
    }

    $status = $line.Substring(0, 2).Trim()
    $path = $line.Substring(3).Trim()

    if ($status.StartsWith('R', [System.StringComparison]::OrdinalIgnoreCase) -and $path.Contains(' -> ')) {
        $path = ($path -split ' -> ')[-1].Trim()
    }

    $dirtyEntries.Add([ordered]@{
        gitStatus = $status
        path = (Normalize-RepoPath $path)
    })
}

$dedicatedDirty = New-Object System.Collections.Generic.List[object]
$sharedDirty = New-Object System.Collections.Generic.List[object]
$retainedEvidenceDirty = New-Object System.Collections.Generic.List[object]
$generatedDirty = New-Object System.Collections.Generic.List[object]
$temporaryDirty = New-Object System.Collections.Generic.List[object]
$unrelatedDirty = New-Object System.Collections.Generic.List[object]

foreach ($entry in $dirtyEntries) {
    if (Test-PathInSet $entry.path $generatedSet) {
        $generatedDirty.Add($entry)
        continue
    }

    if (Test-PathInSet $entry.path $dedicatedSet) {
        $dedicatedDirty.Add($entry)
        continue
    }

    if (Test-PathInSet $entry.path $sharedSet) {
        $sharedDirty.Add($entry)
        continue
    }

    if (Test-PathInSet $entry.path $retainedEvidenceSet) {
        $retainedEvidenceDirty.Add($entry)
        continue
    }

    if (Test-WildcardMatch $entry.path $retainedEvidencePatterns) {
        $retainedEvidenceDirty.Add($entry)
        continue
    }

    if (Test-WildcardMatch $entry.path $temporaryDirtyPatterns) {
        $temporaryDirty.Add($entry)
        continue
    }

    $unrelatedDirty.Add($entry)
}

$temporaryOnDiskPaths = @()
foreach ($candidate in @('tmp/ci', 'tmp/repo-preflight')) {
    $fullPath = Resolve-RepoPath $candidate
    if (Test-Path -LiteralPath $fullPath) {
        $temporaryOnDiskPaths += (Normalize-RepoPath $candidate)
    }
}

$brokenNodeModulesDirs = @(Get-ChildItem -Path (Resolve-RepoPath 'apps/web') -Directory -Filter 'node_modules_broken_*' -ErrorAction SilentlyContinue)
foreach ($dir in $brokenNodeModulesDirs) {
    $temporaryOnDiskPaths += (Get-RepoRelativePath $dir.FullName)
}

$temporaryOnDiskPaths = @($temporaryOnDiskPaths | Sort-Object -Unique)

$missingDedicatedPaths = @(
    $dedicatedSlicePaths |
    Where-Object { -not (Test-Path -LiteralPath (Resolve-RepoPath $_)) }
)

$status = if ($missingDedicatedPaths.Count -gt 0) {
    'fail'
}
elseif ($unrelatedDirty.Count -gt 0 -or $temporaryDirty.Count -gt 0 -or $temporaryOnDiskPaths.Count -gt 0) {
    'pass_with_parallel_drift'
}
else {
    'pass'
}

$recommendation = if ($status -eq 'fail') {
    '先补齐缺失的 dedicated slice 文件，再考虑收口或挑选提交。'
}
elseif ($unrelatedDirty.Count -gt 0 -or $temporaryDirty.Count -gt 0 -or $temporaryOnDiskPaths.Count -gt 0) {
    '本次主线已可单独识别，但提交或交接时应只挑选 dedicated/shared/evidence 清单，不要混入并行脏改动或临时产物。'
}
else {
    '当前工作树与本次主线一致，可按 dedicated/shared/evidence 清单收口。'
}

$report = [pscustomobject]@{}
$report | Add-Member -NotePropertyName status -NotePropertyValue $status
$report | Add-Member -NotePropertyName checkedAt -NotePropertyValue ((Get-Date).ToString('s'))
$report | Add-Member -NotePropertyName repoRoot -NotePropertyValue $repoRoot
$report | Add-Member -NotePropertyName recommendation -NotePropertyValue $recommendation
$report | Add-Member -NotePropertyName dedicatedSlicePaths -NotePropertyValue ([string[]]$dedicatedSlicePaths)
$report | Add-Member -NotePropertyName sharedTouchpointPaths -NotePropertyValue ([string[]]$sharedTouchpointPaths)
$report | Add-Member -NotePropertyName retainedEvidencePaths -NotePropertyValue ([string[]]$retainedEvidencePaths)
$report | Add-Member -NotePropertyName generatedThisRunPaths -NotePropertyValue ([string[]]$generatedThisRunPaths)
$report | Add-Member -NotePropertyName temporaryDirtyPatterns -NotePropertyValue ([string[]]$temporaryDirtyPatterns)
$report | Add-Member -NotePropertyName missingDedicatedPaths -NotePropertyValue ([string[]]$missingDedicatedPaths)

$dirtyCounts = [pscustomobject]@{}
$dirtyCounts | Add-Member -NotePropertyName dedicated -NotePropertyValue $dedicatedDirty.Count
$dirtyCounts | Add-Member -NotePropertyName sharedTouchpoints -NotePropertyValue $sharedDirty.Count
$dirtyCounts | Add-Member -NotePropertyName retainedEvidence -NotePropertyValue $retainedEvidenceDirty.Count
$dirtyCounts | Add-Member -NotePropertyName generatedThisRun -NotePropertyValue $generatedDirty.Count
$dirtyCounts | Add-Member -NotePropertyName temporary -NotePropertyValue $temporaryDirty.Count
$dirtyCounts | Add-Member -NotePropertyName unrelated -NotePropertyValue $unrelatedDirty.Count

$report | Add-Member -NotePropertyName dirtyCounts -NotePropertyValue $dirtyCounts
$report | Add-Member -NotePropertyName dedicatedDirty -NotePropertyValue ($dedicatedDirty.ToArray())
$report | Add-Member -NotePropertyName sharedTouchpointDirty -NotePropertyValue ($sharedDirty.ToArray())
$report | Add-Member -NotePropertyName retainedEvidenceDirty -NotePropertyValue ($retainedEvidenceDirty.ToArray())
$report | Add-Member -NotePropertyName generatedThisRunDirty -NotePropertyValue ($generatedDirty.ToArray())
$report | Add-Member -NotePropertyName temporaryDirty -NotePropertyValue ($temporaryDirty.ToArray())
$report | Add-Member -NotePropertyName temporaryOnDiskPaths -NotePropertyValue ([string[]]$temporaryOnDiskPaths)
$report | Add-Member -NotePropertyName unrelatedDirty -NotePropertyValue ($unrelatedDirty.ToArray())

$jsonFullPath = Resolve-RepoPath $JsonReportPath
$markdownFullPath = Resolve-RepoPath $MarkdownReportPath

New-Item -ItemType Directory -Path (Split-Path -Parent $jsonFullPath) -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $markdownFullPath) -Force | Out-Null

$reportJson = $report | ConvertTo-Json -Depth 8
$reportJson | Set-Content -LiteralPath $jsonFullPath -Encoding UTF8

$markdownLines = New-Object System.Collections.Generic.List[string]
$markdownLines.Add('# Reference-Basis / Repo-Preflight Slice Closeout')
$markdownLines.Add('')
$markdownLines.Add(('- status: {0}' -f $status))
$markdownLines.Add(('- checkedAt: {0}' -f $report.checkedAt))
$markdownLines.Add("- recommendation: $recommendation")
$markdownLines.Add('')
$markdownLines.Add('## Dedicated Slice Dirty Paths')
foreach ($line in (ConvertTo-MarkdownRows $dedicatedDirty.ToArray())) {
    $markdownLines.Add($line)
}
$markdownLines.Add('')
$markdownLines.Add('## Shared Touchpoints Dirty Paths')
foreach ($line in (ConvertTo-MarkdownRows $sharedDirty.ToArray())) {
    $markdownLines.Add($line)
}
$markdownLines.Add('')
$markdownLines.Add('## Retained Evidence Dirty Paths')
foreach ($line in (ConvertTo-MarkdownRows $retainedEvidenceDirty.ToArray())) {
    $markdownLines.Add($line)
}
$markdownLines.Add('')
$markdownLines.Add('## Generated This Run Dirty Paths')
foreach ($line in (ConvertTo-MarkdownRows $generatedDirty.ToArray())) {
    $markdownLines.Add($line)
}
$markdownLines.Add('')
$markdownLines.Add('## Temporary / Host-Local Paths')
if ($temporaryDirty.Count -eq 0 -and $temporaryOnDiskPaths.Count -eq 0) {
    $markdownLines.Add('- none')
}
else {
    foreach ($line in (ConvertTo-MarkdownRows $temporaryDirty.ToArray())) {
        $markdownLines.Add($line)
    }
    if ($temporaryOnDiskPaths.Count -gt 0) {
        $markdownLines.Add('')
        $markdownLines.Add('On-disk temporary paths:')
        foreach ($path in $temporaryOnDiskPaths) {
            $markdownLines.Add(('- {0}' -f $path))
        }
    }
}
$markdownLines.Add('')
$markdownLines.Add('## Unrelated Dirty Paths')
foreach ($line in (ConvertTo-MarkdownRows $unrelatedDirty.ToArray())) {
    $markdownLines.Add($line)
}
$markdownLines.Add('')
$markdownLines.Add('## Missing Dedicated Paths')
if ($missingDedicatedPaths.Count -eq 0) {
    $markdownLines.Add('- none')
}
else {
    foreach ($path in $missingDedicatedPaths) {
        $markdownLines.Add(('- {0}' -f $path))
    }
}

$markdownLines | Set-Content -LiteralPath $markdownFullPath -Encoding UTF8
$reportJson

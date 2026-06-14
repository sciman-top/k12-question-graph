param(
    [ValidateSet('Local', 'Ci')]
    [string] $ValidationMode = 'Local',
    [string] $PolicyPath = 'tasks/reference-basis-policy.json',
    [string] $RequirementsPath = 'tasks/reference-basis-requirements.csv',
    [string] $ModuleMapPath = 'tasks/reference-basis-module-map.csv',
    [string] $AutomationContractPath = 'tasks/automation-first-contract.csv',
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ReferenceDocPath = 'docs/26_References.md',
    [string] $ReferenceUrlsPath = 'sources/references.md',
    [string] $ReadmePath = 'README.md',
    [string] $ToolsReadmePath = 'tools/README.md',
    [string] $NavigationPath = 'docs/111_ProjectNavigationOverview.md',
    [string] $SnapshotManifestPath = 'sources/reference-shelf.manifest.snapshot.json',
    [string] $ExternalReferenceRoot = 'D:\CODE\external\k12-question-graph-references',
    [string] $ExternalManifestPath = 'D:\CODE\external\k12-question-graph-references\references.manifest.json',
    [string[]] $ChangedPaths = @(),
    [string] $JsonReportPath = '',
    [string] $MarkdownReportPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runDate = Get-Date -Format 'yyyyMMdd'
$checkExternalDisk = $ValidationMode -eq 'Local'

function Resolve-RepoPath([string] $Path) {
    Join-Path $repoRoot $Path
}

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
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

function Normalize-RepoPath([string] $Path) {
    return ($Path -replace '\\', '/').Trim()
}

function Test-PathPrefixMatch([string] $ChangedPath, [string] $ModulePath) {
    $normalizedChangedPath = Normalize-RepoPath $ChangedPath
    $normalizedModulePath = Normalize-RepoPath $ModulePath

    if ([string]::IsNullOrWhiteSpace($normalizedChangedPath) -or [string]::IsNullOrWhiteSpace($normalizedModulePath)) {
        return $false
    }

    if ($normalizedChangedPath.Equals($normalizedModulePath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    if ($normalizedChangedPath.StartsWith($normalizedModulePath + '/', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    return $false
}

$policyFullPath = Resolve-RepoPath $PolicyPath
$requirementsFullPath = Resolve-RepoPath $RequirementsPath
$moduleMapFullPath = Resolve-RepoPath $ModuleMapPath
$automationContractFullPath = Resolve-RepoPath $AutomationContractPath
$backlogFullPath = Resolve-RepoPath $BacklogPath
$referenceDocFullPath = Resolve-RepoPath $ReferenceDocPath
$referenceUrlsFullPath = Resolve-RepoPath $ReferenceUrlsPath
$readmeFullPath = Resolve-RepoPath $ReadmePath
$toolsReadmeFullPath = Resolve-RepoPath $ToolsReadmePath
$navigationFullPath = Resolve-RepoPath $NavigationPath
$snapshotManifestFullPath = Resolve-RepoPath $SnapshotManifestPath

if ([string]::IsNullOrWhiteSpace($JsonReportPath)) {
    $JsonReportPath = ('docs/evidence/{0}-reference-basis-guard.json' -f $runDate)
}

if ([string]::IsNullOrWhiteSpace($MarkdownReportPath)) {
    $MarkdownReportPath = ('docs/evidence/{0}-reference-basis-guard.md' -f $runDate)
}

$jsonReportFullPath = Resolve-RepoPath $JsonReportPath
$markdownReportFullPath = Resolve-RepoPath $MarkdownReportPath

foreach ($path in @(
    $policyFullPath,
    $requirementsFullPath,
    $moduleMapFullPath,
    $automationContractFullPath,
    $backlogFullPath,
    $referenceDocFullPath,
    $referenceUrlsFullPath,
    $readmeFullPath,
    $toolsReadmeFullPath,
    $navigationFullPath,
    $snapshotManifestFullPath
)) {
    Assert-True (Test-Path -LiteralPath $path) "missing required file: $path"
}

if ($checkExternalDisk) {
    Assert-True (Test-Path -LiteralPath $ExternalManifestPath) "missing required file: $ExternalManifestPath"
}

$requiredTaskColumns = @(
    'task_id',
    'applies_when',
    'official_reference_urls',
    'local_reference_paths',
    'community_reference_paths',
    'why_required',
    'minimum_expectation'
)

$requiredModuleColumns = @(
    'module_id',
    'module_paths',
    'task_ids',
    'official_reference_urls',
    'local_reference_paths',
    'community_reference_paths',
    'adoption_mode',
    'why_required',
    'minimum_expectation'
)

$policy = Get-Content -LiteralPath $policyFullPath -Raw | ConvertFrom-Json
$expectedTaskIds = @($policy.expectedTaskIds | ForEach-Object { [string] $_ })
$expectedModuleIds = @($policy.expectedModuleIds | ForEach-Object { [string] $_ })
$allowedAdoptionModes = @($policy.allowedAdoptionModes | ForEach-Object { [string] $_ })

Assert-True ($expectedTaskIds.Count -gt 0) 'reference-basis policy must define expectedTaskIds'
Assert-True ($expectedModuleIds.Count -gt 0) 'reference-basis policy must define expectedModuleIds'
Assert-True ($allowedAdoptionModes.Count -gt 0) 'reference-basis policy must define allowedAdoptionModes'

$requirementsRows = @(Import-Csv -LiteralPath $requirementsFullPath -Encoding UTF8)
$moduleMapRows = @(Import-Csv -LiteralPath $moduleMapFullPath -Encoding UTF8)
$automationRows = @(Import-Csv -LiteralPath $automationContractFullPath -Encoding UTF8)
$backlogRows = @(Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8)
$referenceDocText = Get-Content -LiteralPath $referenceDocFullPath -Raw
$referenceUrlsText = Get-Content -LiteralPath $referenceUrlsFullPath -Raw
$readmeText = Get-Content -LiteralPath $readmeFullPath -Raw
$toolsReadmeText = Get-Content -LiteralPath $toolsReadmeFullPath -Raw
$navigationText = Get-Content -LiteralPath $navigationFullPath -Raw

$snapshotManifest = Get-Content -LiteralPath $snapshotManifestFullPath -Raw | ConvertFrom-Json
$snapshotManifestPaths = @($snapshotManifest.entries | ForEach-Object { [string] $_.relativePath })
$externalManifestAvailable = Test-Path -LiteralPath $ExternalManifestPath
$externalManifestPaths = @()
$manifestParity = 'external_unavailable'

if ($externalManifestAvailable) {
    $externalManifest = Get-Content -LiteralPath $ExternalManifestPath -Raw | ConvertFrom-Json
    $externalManifestPaths = @($externalManifest.entries | ForEach-Object { [string] $_.relativePath })

    $missingFromSnapshot = @($externalManifestPaths | Where-Object { $snapshotManifestPaths -notcontains $_ })
    $extraInSnapshot = @($snapshotManifestPaths | Where-Object { $externalManifestPaths -notcontains $_ })

    Assert-True ($missingFromSnapshot.Count -eq 0) ("snapshot manifest is missing external reference entries: {0}. run tools/sync-reference-shelf-snapshot.ps1" -f ($missingFromSnapshot -join ', '))
    Assert-True ($extraInSnapshot.Count -eq 0) ("snapshot manifest has entries not present in external manifest: {0}. run tools/sync-reference-shelf-snapshot.ps1" -f ($extraInSnapshot -join ', '))
    $manifestParity = 'match'
}

$referenceManifestPaths = if ($ValidationMode -eq 'Ci') {
    $snapshotManifestPaths
}
else {
    $externalManifestPaths
}

Assert-True ($requirementsRows.Count -eq $expectedTaskIds.Count) "unexpected reference-basis row count: expected $($expectedTaskIds.Count), actual $($requirementsRows.Count)"
Assert-True ($moduleMapRows.Count -eq $expectedModuleIds.Count) "unexpected reference-basis module row count: expected $($expectedModuleIds.Count), actual $($moduleMapRows.Count)"

foreach ($column in $requiredTaskColumns) {
    Assert-True ($requirementsRows[0].PSObject.Properties.Name -contains $column) "reference-basis csv missing column: $column"
}
foreach ($column in $requiredModuleColumns) {
    Assert-True ($moduleMapRows[0].PSObject.Properties.Name -contains $column) "reference-basis module map missing column: $column"
}

$requirementsById = @{}
foreach ($row in $requirementsRows) {
    $taskId = [string] $row.task_id
    Assert-True (-not [string]::IsNullOrWhiteSpace($taskId)) 'reference-basis row has blank task_id'
    Assert-True (-not $requirementsById.ContainsKey($taskId)) "duplicate reference-basis task_id: $taskId"
    $requirementsById[$taskId] = $row
    foreach ($column in $requiredTaskColumns) {
        if ($column -ne 'community_reference_paths') {
            Assert-True (-not [string]::IsNullOrWhiteSpace([string] $row.$column)) "reference-basis row ${taskId} missing $column"
        }
    }
}

$automationIds = @($automationRows | ForEach-Object { [string] $_.task_id })
$backlogIds = @($backlogRows | ForEach-Object { [string] $_.id })

for ($i = 0; $i -lt $expectedTaskIds.Count; $i++) {
    $expectedId = $expectedTaskIds[$i]
    $actualId = [string] $requirementsRows[$i].task_id
    Assert-True ($actualId -eq $expectedId) "reference-basis row order drift at position $($i + 1): expected $expectedId actual $actualId"
    Assert-True ($requirementsById.ContainsKey($expectedId)) "missing reference-basis row: $expectedId"
    Assert-True ($automationIds -contains $expectedId) "automation-first contract missing high-risk task: $expectedId"
    Assert-True ($backlogIds -contains $expectedId) "backlog missing high-risk task: $expectedId"

    $row = $requirementsById[$expectedId]
    $officialUrls = Split-Values $row.official_reference_urls
    $localPaths = Split-Values $row.local_reference_paths
    $communityPaths = Split-Values $row.community_reference_paths

    Assert-True ($officialUrls.Count -ge 1) "${expectedId} must bind at least one official reference URL"
    Assert-True ($localPaths.Count -ge 1) "${expectedId} must bind at least one local reference path"

    foreach ($url in $officialUrls) {
        Assert-True ($referenceUrlsText.Contains($url)) "${expectedId} official reference missing from sources/references.md: $url"
    }

    foreach ($relativePath in (@($localPaths) + @($communityPaths))) {
        Assert-True ($referenceManifestPaths -contains $relativePath) "${expectedId} local/community reference missing from manifest or snapshot: $relativePath"
        if ($checkExternalDisk) {
            $fullPath = Join-Path $ExternalReferenceRoot $relativePath
            Assert-True (Test-Path -LiteralPath $fullPath) "${expectedId} local/community reference path missing on disk: $relativePath"
        }
        Assert-True ($referenceDocText.Contains($relativePath)) "${expectedId} local/community reference missing from docs/26_References.md: $relativePath"
    }
}

$moduleRowsById = @{}
for ($i = 0; $i -lt $expectedModuleIds.Count; $i++) {
    $expectedId = $expectedModuleIds[$i]
    $row = $moduleMapRows[$i]
    $actualId = [string] $row.module_id
    Assert-True ($actualId -eq $expectedId) "reference-basis module row order drift at position $($i + 1): expected $expectedId actual $actualId"
    Assert-True (-not $moduleRowsById.ContainsKey($actualId)) "duplicate reference-basis module_id: $actualId"
    $moduleRowsById[$actualId] = $row

    foreach ($column in $requiredModuleColumns) {
        if ($column -ne 'community_reference_paths') {
            Assert-True (-not [string]::IsNullOrWhiteSpace([string] $row.$column)) "reference-basis module row ${actualId} missing $column"
        }
    }

    Assert-True ($allowedAdoptionModes -contains [string] $row.adoption_mode) "unsupported adoption_mode for ${actualId}: $($row.adoption_mode)"

    $modulePaths = Split-Values $row.module_paths
    $taskIds = Split-Values $row.task_ids
    $officialUrls = Split-Values $row.official_reference_urls
    $localPaths = Split-Values $row.local_reference_paths
    $communityPaths = Split-Values $row.community_reference_paths

    Assert-True ($modulePaths.Count -ge 1) "${actualId} must bind at least one repo module path"
    Assert-True ($taskIds.Count -ge 1) "${actualId} must bind at least one guarded task id"
    Assert-True ($officialUrls.Count -ge 1) "${actualId} must bind at least one official reference URL"
    Assert-True ($localPaths.Count -ge 1) "${actualId} must bind at least one local reference path"

    foreach ($modulePath in $modulePaths) {
        Assert-True (Test-Path -LiteralPath (Resolve-RepoPath $modulePath)) "${actualId} module path missing in repo: $modulePath"
    }
    foreach ($taskId in $taskIds) {
        Assert-True ($requirementsById.ContainsKey($taskId)) "${actualId} references unknown guarded task id: $taskId"
        Assert-True ($backlogIds -contains $taskId) "${actualId} task id missing from backlog: $taskId"
    }
    foreach ($url in $officialUrls) {
        Assert-True ($referenceUrlsText.Contains($url)) "${actualId} official reference missing from sources/references.md: $url"
    }
    foreach ($relativePath in (@($localPaths) + @($communityPaths))) {
        Assert-True ($referenceManifestPaths -contains $relativePath) "${actualId} local/community reference missing from manifest or snapshot: $relativePath"
        if ($checkExternalDisk) {
            $fullPath = Join-Path $ExternalReferenceRoot $relativePath
            Assert-True (Test-Path -LiteralPath $fullPath) "${actualId} local/community reference path missing on disk: $relativePath"
        }
        Assert-True ($referenceDocText.Contains($relativePath)) "${actualId} local/community reference missing from docs/26_References.md: $relativePath"
    }
}

$globalRow = @($automationRows | Where-Object { [string] $_.task_id -eq 'GLOBAL' })
Assert-True ($globalRow.Count -eq 1) 'automation-first contract must keep exactly one GLOBAL row'
Assert-True ($globalRow[0].dedicated_surface -match 'reference-basis-requirements\.csv') 'automation-first GLOBAL row must mention reference-basis-requirements.csv'
Assert-True ($globalRow[0].evidence_command -match 'run-reference-basis-guard\.ps1') 'automation-first GLOBAL row must mention run-reference-basis-guard.ps1'

foreach ($keyword in @(
    'tasks/reference-basis-requirements.csv',
    'tasks/reference-basis-module-map.csv',
    'sources/reference-shelf.manifest.snapshot.json',
    'tools/run-reference-basis-guard.ps1'
)) {
    Assert-True ($readmeText.Contains($keyword)) "README missing keyword: $keyword"
    Assert-True ($toolsReadmeText.Contains($keyword)) "tools/README.md missing keyword: $keyword"
    Assert-True ($referenceDocText.Contains($keyword)) "docs/26_References.md missing keyword: $keyword"
    Assert-True ($navigationText.Contains($keyword)) "docs/111_ProjectNavigationOverview.md missing keyword: $keyword"
}

$communityTaskCount = @($requirementsRows | Where-Object { (Split-Values $_.community_reference_paths).Count -gt 0 }).Count

$normalizedChangedPaths = @(
    $ChangedPaths |
    ForEach-Object { Normalize-RepoPath $_ } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Sort-Object -Unique
)
$impactedModuleIds = New-Object System.Collections.Generic.List[string]
$impactedTaskIds = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
$changedPathsOutsideGuardedModules = New-Object System.Collections.Generic.List[string]

foreach ($changedPath in $normalizedChangedPaths) {
    $matchedModuleIds = @()

    foreach ($moduleId in $expectedModuleIds) {
        $moduleRow = $moduleRowsById[$moduleId]
        $modulePaths = Split-Values $moduleRow.module_paths
        if (@($modulePaths | Where-Object { Test-PathPrefixMatch $changedPath $_ }).Count -gt 0) {
            $matchedModuleIds += $moduleId

            if ($impactedModuleIds -notcontains $moduleId) {
                $impactedModuleIds.Add($moduleId)
            }

            foreach ($taskId in (Split-Values $moduleRow.task_ids)) {
                $null = $impactedTaskIds.Add($taskId)
            }
        }
    }

    if ($matchedModuleIds.Count -eq 0) {
        $changedPathsOutsideGuardedModules.Add($changedPath)
    }
}

$report = [ordered]@{
    status = 'pass'
    taskId = 'REFERENCE_BASIS_GUARD'
    checkedAt = (Get-Date).ToString('s')
    validationMode = $ValidationMode
    policyPath = $PolicyPath
    requirementsPath = $RequirementsPath
    moduleMapPath = $ModuleMapPath
    snapshotManifestPath = $SnapshotManifestPath
    rowCount = $requirementsRows.Count
    moduleRowCount = $moduleMapRows.Count
    taskIds = $expectedTaskIds
    moduleIds = $expectedModuleIds
    communityTaskCount = $communityTaskCount
    externalReferenceRoot = $ExternalReferenceRoot
    externalManifestFound = ($referenceManifestPaths.Count -gt 0)
    externalManifestAvailable = $externalManifestAvailable
    effectiveManifestSource = if ($ValidationMode -eq 'Ci') { 'snapshot' } else { 'external' }
    snapshotEntryCount = $snapshotManifestPaths.Count
    externalEntryCount = $externalManifestPaths.Count
    snapshotParity = $manifestParity
    physicalExternalCheck = $checkExternalDisk
    changedPathCount = $normalizedChangedPaths.Count
    changedPaths = $normalizedChangedPaths
    impactedModuleIds = @($impactedModuleIds)
    impactedTaskIds = @($impactedTaskIds | Sort-Object)
    changedPathsOutsideGuardedModules = @($changedPathsOutsideGuardedModules)
    enforcedBoundary = 'high-risk tasks and guarded repo modules must register official references plus local reference corpus anchors before they can claim gate-ready evidence'
}

New-Item -ItemType Directory -Path (Split-Path -Parent $jsonReportFullPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonReportFullPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# Reference Basis Guard')
$lines.Add('')
$lines.Add("- status: pass")
$lines.Add("- checked_at: $($report.checkedAt)")
$lines.Add("- validation_mode: $ValidationMode")
$lines.Add("- policy_path: $PolicyPath")
$lines.Add("- requirements_path: $RequirementsPath")
$lines.Add("- module_map_path: $ModuleMapPath")
$lines.Add("- snapshot_manifest_path: $SnapshotManifestPath")
$lines.Add("- row_count: $($requirementsRows.Count)")
$lines.Add("- module_row_count: $($moduleMapRows.Count)")
$lines.Add("- community_task_count: $communityTaskCount")
$lines.Add("- effective_manifest_source: $($report.effectiveManifestSource)")
$lines.Add("- snapshot_entry_count: $($report.snapshotEntryCount)")
$lines.Add("- external_entry_count: $($report.externalEntryCount)")
$lines.Add("- snapshot_parity: $($report.snapshotParity)")
$lines.Add("- physical_external_check: $checkExternalDisk")
$lines.Add("- changed_path_count: $($report.changedPathCount)")
$lines.Add('')
$lines.Add('## Changed Paths')
if ($normalizedChangedPaths.Count -eq 0) {
    $lines.Add('- none')
}
else {
    foreach ($changedPath in $normalizedChangedPaths) {
        $lines.Add("- $changedPath")
    }
}
$lines.Add('')
$lines.Add('## Impacted Tasks')
if (@($report.impactedTaskIds).Count -eq 0) {
    $lines.Add('- none')
}
else {
    foreach ($taskId in $report.impactedTaskIds) {
        $lines.Add("- $taskId")
    }
}
$lines.Add('')
$lines.Add('## Impacted Modules')
if (@($report.impactedModuleIds).Count -eq 0) {
    $lines.Add('- none')
}
else {
    foreach ($moduleId in $report.impactedModuleIds) {
        $lines.Add("- $moduleId")
    }
}
$lines.Add('')
$lines.Add('## Changed Paths Outside Guarded Modules')
if (@($report.changedPathsOutsideGuardedModules).Count -eq 0) {
    $lines.Add('- none')
}
else {
    foreach ($path in $report.changedPathsOutsideGuardedModules) {
        $lines.Add("- $path")
    }
}
$lines.Add('')
$lines.Add('## Covered Tasks')
foreach ($taskId in $expectedTaskIds) {
    $lines.Add("- $taskId")
}
$lines.Add('')
$lines.Add('## Covered Modules')
foreach ($moduleId in $expectedModuleIds) {
    $lines.Add("- $moduleId")
}
$lines.Add('')
$lines.Add('## Boundary')
$lines.Add('This guard proves that guarded tasks and module surfaces have declared official references plus reference-basis anchors.')
$lines.Add('Local mode also requires the external corpus to exist on disk. CI mode falls back to the snapshot manifest and only verifies the repo-side declarations, docs, and mappings.')
$lines.Add('It does not prove the implementation used those references correctly, so feature-specific contracts and review are still required.')
New-Item -ItemType Directory -Path (Split-Path -Parent $markdownReportFullPath) -Force | Out-Null
$lines | Set-Content -LiteralPath $markdownReportFullPath -Encoding UTF8

$report | ConvertTo-Json -Depth 8

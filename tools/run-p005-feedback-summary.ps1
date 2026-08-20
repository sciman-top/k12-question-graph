param(
    [ValidateSet('DryRun', 'Collect')]
    [string] $Mode = 'DryRun',
    [Parameter(Mandatory = $true)][string] $InputPath,
    [string] $OutputPath = 'tmp/verification/p005-feedback-summary.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Resolve-RepoPath([string] $Path) {
    if ([System.IO.Path]::IsPathFullyQualified($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
}

function Normalize-Text([object] $Value) {
    if ($null -eq $Value) { return '' }
    return ([string] $Value).Trim().ToLowerInvariant() -replace '\s+', ' '
}

function Get-FirstValue([object] $Object, [string[]] $Names) {
    foreach ($name in $Names) {
        if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $name) {
            $value = [string] $Object.$name
            if (-not [string]::IsNullOrWhiteSpace($value)) { return $value.Trim() }
        }
    }
    return ''
}

$inputFullPath = Resolve-RepoPath $InputPath
if (-not (Test-Path -LiteralPath $inputFullPath -PathType Leaf)) {
    throw "feedback input missing: $InputPath"
}

try {
    $input = Get-Content -LiteralPath $inputFullPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
catch {
    throw "feedback input is not valid JSON: $InputPath"
}

$rawItems = @()
if ($input.PSObject.Properties.Name -contains 'items') {
    $rawItems = @($input.items)
}
elseif ($input.PSObject.Properties.Name -contains 'frictionItems') {
    $rawItems = @($input.frictionItems | ForEach-Object {
        [pscustomobject]@{
            id = ''
            title = ''
            sourceStep = 'other'
            description = [string] $_.detail
            teacherEfficiencyImpact = if ([string] $_.severity -eq 'high') { 'high' } elseif ([string] $_.severity -eq 'medium') { 'medium' } else { 'low' }
            frequency = 'single'
            risk = [string] $_.severity
            cost = 'review_required'
            decision = 'review_required'
            owner = ''
            targetArtifact = ''
            rollbackOrFallback = ''
        }
    })
}

$normalized = New-Object System.Collections.Generic.List[object]
foreach ($item in $rawItems) {
    $description = Get-FirstValue $item @('description', 'detail', 'title')
    if ([string]::IsNullOrWhiteSpace($description) -or $description -like '<*>' -or $description -eq 'string') { continue }
    $normalized.Add([pscustomobject]@{
        id = Get-FirstValue $item @('id')
        title = Get-FirstValue $item @('title')
        sourceStep = Get-FirstValue $item @('sourceStep', 'step', 'category')
        description = $description
        key = Normalize-Text $description
        teacherEfficiencyImpact = Get-FirstValue $item @('teacherEfficiencyImpact', 'efficiency')
        frequency = Get-FirstValue $item @('frequency')
        risk = Get-FirstValue $item @('risk', 'severity')
        cost = Get-FirstValue $item @('cost')
        decision = Get-FirstValue $item @('decision')
        owner = Get-FirstValue $item @('owner')
        targetArtifact = Get-FirstValue $item @('targetArtifact')
        rollbackOrFallback = Get-FirstValue $item @('rollbackOrFallback', 'rollbackAction')
    })
}

$clusters = New-Object System.Collections.Generic.List[object]
foreach ($group in @($normalized | Group-Object -Property key)) {
    $first = @($group.Group)[0]
    $count = @($group.Group).Count
    $existingDecisions = @($group.Group | ForEach-Object { $_.decision } | Where-Object { $_ -and $_ -ne 'review_required' } | Select-Object -Unique)
    $clusterNumber = $clusters.Count + 1
    $clusters.Add([pscustomobject][ordered]@{
        clusterId = 'feedback-{0}' -f $clusterNumber.ToString('000')
        sourceStep = [string] $first.sourceStep
        title = [string] $first.title
        description = [string] $first.description
        occurrenceCount = $count
        candidateFrequency = if ($count -ge 3) { 'high' } elseif ($count -eq 2) { 'medium' } else { 'single' }
        teacherEfficiencyImpact = [string] $first.teacherEfficiencyImpact
        risk = [string] $first.risk
        cost = [string] $first.cost
        existingDecisions = $existingDecisions
        candidateDecision = if ($existingDecisions.Count -eq 1) { [string] $existingDecisions[0] } else { 'review_required' }
        sourceIds = @($group.Group | ForEach-Object { $_.id } | Where-Object { $_ })
        owners = @($group.Group | ForEach-Object { $_.owner } | Where-Object { $_ } | Select-Object -Unique)
        fallbackNotes = @($group.Group | ForEach-Object { $_.rollbackOrFallback } | Where-Object { $_ } | Select-Object -Unique)
    })
}

$status = if ($clusters.Count -gt 0) { 'pass' } else { 'blocked' }
$report = [ordered]@{
    schemaVersion = 'p005-feedback-summary.v1'
    status = $status
    mode = $Mode
    checkedAt = (Get-Date).ToString('o')
    inputPath = $InputPath
    inputSha256 = (Get-FileHash -LiteralPath $inputFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    rawItemCount = $rawItems.Count
    usableItemCount = $normalized.Count
    clusterCount = $clusters.Count
    clusters = $clusters.ToArray()
    candidateSummary = [ordered]@{
        highFrequencyCount = @($clusters | Where-Object candidateFrequency -eq 'high').Count
        highRiskCount = @($clusters | Where-Object risk -eq 'high').Count
        efficiencyImpactHighCount = @($clusters | Where-Object teacherEfficiencyImpact -eq 'high').Count
        reviewRequiredCount = @($clusters | Where-Object candidateDecision -eq 'review_required').Count
    }
    humanReviewRequired = 'Product owner reviews scope, cost, risk, conflicts, and final keep/modify/defer/do_not_do decision. The summary never edits backlog or scope documents.'
    boundary = 'Deterministic deduplication and grouping only; no AI claim, no invented feedback, no automatic backlog update, no signoff substitution.'
}
$json = $report | ConvertTo-Json -Depth 10
if ($Mode -eq 'Collect') {
    $outputFullPath = Resolve-RepoPath $OutputPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $outputFullPath) -Force | Out-Null
    $json | Set-Content -LiteralPath $outputFullPath -Encoding UTF8
}
$json
if ($status -ne 'pass') { throw 'feedback summary blocked: no usable structured feedback items' }

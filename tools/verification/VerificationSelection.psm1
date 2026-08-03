Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-VerificationSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $RepoRoot,
        [string[]] $ChangedPaths = @(),
        [string] $TaskId = '',
        [string] $RulesPath = 'configs/verification/slice-selection.rules.json'
    )

    $rules = Get-Content -LiteralPath (Join-Path $RepoRoot $RulesPath) -Raw -Encoding UTF8 | ConvertFrom-Json
    $catalog = @{}
    foreach ($command in $rules.commandCatalog) { $catalog[[string]$command.id] = $command }
    $selectedReasons = @{}
    $pathDecisions = New-Object System.Collections.Generic.List[object]
    $unknownPaths = New-Object System.Collections.Generic.List[string]
    $releasePaths = New-Object System.Collections.Generic.List[string]

    foreach ($rawPath in @($ChangedPaths)) {
        foreach ($pathPart in ([string]$rawPath -split ',')) {
        $path = $pathPart.Trim().Trim("'`"") -replace '\\', '/'
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        $matched = $null
        foreach ($rule in $rules.pathRules) {
            if ($path -like [string]$rule.pattern) {
                $matched = $rule
                break
            }
        }
        if ($null -eq $matched) {
            $unknownPaths.Add($path)
            $pathDecisions.Add([pscustomobject]@{ path = $path; profile = 'Unknown'; owner = ''; reason = 'no path rule'; commands = @() })
            continue
        }
        if ([string]$matched.profile -eq 'Release') { $releasePaths.Add($path) }
        foreach ($commandId in @($matched.commands)) {
            if (-not $catalog.ContainsKey([string]$commandId)) { throw "path rule references unknown command: $commandId" }
            if (-not $selectedReasons.ContainsKey([string]$commandId)) { $selectedReasons[[string]$commandId] = New-Object System.Collections.Generic.List[string] }
            $selectedReasons[[string]$commandId].Add("path:$path")
        }
        $pathDecisions.Add([pscustomobject]@{
            path = $path
            profile = [string]$matched.profile
            owner = [string]$matched.owner
            reason = [string]$matched.reason
            commands = @($matched.commands)
        })
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($TaskId)) {
        foreach ($taskRule in $rules.taskRules) {
            if ($TaskId -like [string]$taskRule.pattern) {
                foreach ($commandId in @($taskRule.commands)) {
                    if (-not $catalog.ContainsKey([string]$commandId)) { throw "task rule references unknown command: $commandId" }
                    if (-not $selectedReasons.ContainsKey([string]$commandId)) { $selectedReasons[[string]$commandId] = New-Object System.Collections.Generic.List[string] }
                    $selectedReasons[[string]$commandId].Add("task:$TaskId")
                }
            }
        }
    }

    $selected = New-Object System.Collections.Generic.List[object]
    $skipped = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $rules.commandCatalog) {
        $id = [string]$entry.id
        if ($selectedReasons.ContainsKey($id)) {
            $selected.Add([pscustomobject]@{
                id = $id
                command = [string]$entry.command
                reason = @($selectedReasons[$id].ToArray())
                side_effects = [string]$entry.sideEffects
            })
        }
        else {
            $skipped.Add([pscustomobject]@{ id = $id; reason = 'no task or changed-path match' })
        }
    }

    $noSelection = $selected.Count -eq 0 -and $unknownPaths.Count -eq 0 -and $releasePaths.Count -eq 0
    $escalatedProfile = if ($unknownPaths.Count -gt 0 -or $releasePaths.Count -gt 0) { 'Release' } else { 'Slice' }
    return [pscustomobject][ordered]@{
        schemaVersion = 1
        status = if ($unknownPaths.Count -gt 0 -or $noSelection) { 'blocked' } elseif ($releasePaths.Count -gt 0) { 'escalated' } else { 'pass' }
        taskId = $TaskId
        changedPaths = @($ChangedPaths)
        selected = $selected.ToArray()
        skipped = $skipped.ToArray()
        pathDecisions = $pathDecisions.ToArray()
        unknownPaths = $unknownPaths.ToArray()
        releasePaths = $releasePaths.ToArray()
        noSelection = $noSelection
        escalatedProfile = $escalatedProfile
        sideEffectSummary = @($selected | ForEach-Object { "$($_.id): $($_.side_effects)" })
    }
}

Export-ModuleMember -Function Get-VerificationSelection

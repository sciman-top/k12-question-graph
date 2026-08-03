Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-StableGateId {
    param([Parameter(Mandatory = $true)][string] $Name)

    $slug = $Name.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $slug = $slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        throw "gate step name cannot produce a stable id: $Name"
    }
    return "legacy-$slug"
}

function Get-StepOwner {
    param(
        [Parameter(Mandatory = $true)][string] $SearchText,
        [Parameter(Mandatory = $true)] $Rules
    )

    foreach ($rule in $Rules.ownerRules) {
        if ($SearchText -match [string]$rule.pattern) {
            return [string]$rule.owner
        }
    }
    return 'governance'
}

function Get-LegacyGateInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $RepoRoot,
        [string] $RulesPath = 'configs/verification/legacy-gate-classification.rules.json'
    )

    $rulesFullPath = Join-Path $RepoRoot $RulesPath
    $rules = Get-Content -LiteralPath $rulesFullPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $gateFullPath = Join-Path $RepoRoot ([string]$rules.sourceScript)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($gateFullPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "legacy gate PowerShell parse failed: $($parseErrors[0].Message)"
    }

    $commands = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Invoke-GateStep'
    }, $true))

    $quickNames = @{}
    foreach ($name in $rules.quickStepNames) { $quickNames[[string]$name] = $true }
    $steps = New-Object System.Collections.Generic.List[object]

    foreach ($commandAst in $commands) {
        if ($commandAst.CommandElements.Count -lt 3) {
            throw "Invoke-GateStep at line $($commandAst.Extent.StartLineNumber) is missing name or body"
        }
        $nameNode = $commandAst.CommandElements[1]
        if ($nameNode -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {
            throw "Invoke-GateStep at line $($commandAst.Extent.StartLineNumber) must use a literal name"
        }

        $name = [string]$nameNode.Value
        $body = [string]$commandAst.CommandElements[2].Extent.Text
        $searchText = "$name $body"
        $invokedScripts = @([regex]::Matches($body, 'run-[a-z0-9-]+\.ps1', 'IgnoreCase') |
            ForEach-Object { $_.Value.ToLowerInvariant() } | Sort-Object -Unique)
        $commandLocator = if ($invokedScripts.Count -gt 0) {
            ($invokedScripts | ForEach-Object { "tools/$_" }) -join ';'
        }
        else {
            "inline:$name"
        }

        $owner = Get-StepOwner -SearchText $searchText -Rules $rules
        $triggerProperty = $rules.triggerPathsByOwner.PSObject.Properties[$owner]
        if ($null -eq $triggerProperty) {
            throw "missing trigger path mapping for owner: $owner"
        }

        $requiresDatabase = $searchText -match '(?i)Database(Name|Host|Port|User|Password)|PGPASSWORD|psql|pg_dump|pg_restore|KQG_CONNECTION_STRING|DbContext|migration'
        $stopsProcess = $searchText -match '(?i)Stop-Process|\.Kill\(|Kill\(\)|stop repo api|pause.*api'
        $writesRepo = $searchText -match '(?i)docs[\\/]evidence|Set-Content[^\r\n]*(docs|tasks|configs|schemas)[\\/]'
        $writesFilestore = $searchText -match '(?i)FileStoreRoot|KqgPaths__FileStoreRoot|file_store'
        $requiresExternalTool = $searchText -match '(?i)psql|pg_dump|pg_restore|libreoffice|soffice|pandoc|tesseract|curl\.exe'
        $triggerOnly = $name -match [string]$rules.futureTriggerOnlyNameRegex
        $profile = if ($quickNames.ContainsKey($name)) { 'Quick' } else { 'Release' }
        $risk = if ($profile -eq 'Quick') {
            'low'
        }
        elseif ($requiresDatabase -or $stopsProcess -or $writesFilestore -or $triggerOnly) {
            'high'
        }
        else {
            'medium'
        }
        $evidenceOutput = if ($writesRepo) { @('dynamic:docs/evidence') } else { @() }

        $steps.Add([pscustomobject][ordered]@{
            id = ConvertTo-StableGateId -Name $name
            name = $name
            command = $commandLocator
            owner_module = $owner
            profile = $profile
            risk = $risk
            requires_database = [bool]$requiresDatabase
            stops_process = [bool]$stopsProcess
            writes_repo = [bool]$writesRepo
            writes_filestore = [bool]$writesFilestore
            requires_external_tool = [bool]$requiresExternalTool
            trigger_paths = @($triggerProperty.Value)
            trigger_only = [bool]$triggerOnly
            supersedes = @()
            evidence_output = $evidenceOutput
            source_line = [int]$commandAst.Extent.StartLineNumber
            automatable_repo_side = ($profile -ne 'Onsite')
        })
    }

    return [pscustomobject]@{
        rules = $rules
        sourceScript = [string]$rules.sourceScript
        sourceFullPath = $gateFullPath
        steps = $steps.ToArray()
    }
}

function Test-LegacyGateInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]] $Steps,
        [Parameter(Mandatory = $true)][int] $ExpectedStepCount,
        [string[]] $AllowedProfiles = @('Quick', 'Slice', 'Release', 'Onsite')
    )

    if ($Steps.Count -ne $ExpectedStepCount) {
        throw "legacy gate step count mismatch: expected=$ExpectedStepCount actual=$($Steps.Count)"
    }

    $requiredFields = @(
        'id', 'name', 'command', 'owner_module', 'profile', 'risk',
        'requires_database', 'stops_process', 'writes_repo', 'writes_filestore',
        'requires_external_tool', 'trigger_paths', 'trigger_only', 'supersedes',
        'evidence_output', 'source_line', 'automatable_repo_side'
    )
    $seenIds = @{}
    $seenNames = @{}

    foreach ($step in $Steps) {
        foreach ($field in $requiredFields) {
            if ($step.PSObject.Properties.Name -notcontains $field) {
                throw "gate step is missing required field: $field"
            }
        }
        foreach ($field in @('id', 'name', 'command', 'owner_module', 'profile', 'risk')) {
            if ([string]::IsNullOrWhiteSpace([string]$step.$field)) {
                throw "gate step has blank required field: $field"
            }
        }
        if ($seenIds.ContainsKey([string]$step.id)) { throw "duplicate gate step id: $($step.id)" }
        if ($seenNames.ContainsKey([string]$step.name)) { throw "duplicate gate step name: $($step.name)" }
        $seenIds[[string]$step.id] = $true
        $seenNames[[string]$step.name] = $true

        if ($AllowedProfiles -notcontains [string]$step.profile) {
            throw "unknown verification profile for $($step.id): $($step.profile)"
        }
        if (@('low', 'medium', 'high') -notcontains [string]$step.risk) {
            throw "unknown risk for $($step.id): $($step.risk)"
        }
        if (@($step.trigger_paths).Count -eq 0) {
            throw "gate step has no trigger paths: $($step.id)"
        }
        if ($step.profile -eq 'Quick' -and ($step.requires_database -or $step.stops_process -or $step.writes_repo -or $step.writes_filestore)) {
            throw "Quick gate step has forbidden side effect: $($step.id)"
        }
        if ($step.trigger_only -and $step.profile -eq 'Quick') {
            throw "trigger-only future step cannot enter Quick: $($step.id)"
        }
        if ($step.profile -eq 'Onsite' -and $step.automatable_repo_side) {
            throw "Onsite step cannot be repo-side automatable: $($step.id)"
        }
    }

    return [pscustomobject]@{
        stepCount = $Steps.Count
        profileCounts = [ordered]@{
            Quick = @($Steps | Where-Object profile -eq 'Quick').Count
            Slice = @($Steps | Where-Object profile -eq 'Slice').Count
            Release = @($Steps | Where-Object profile -eq 'Release').Count
            Onsite = @($Steps | Where-Object profile -eq 'Onsite').Count
        }
    }
}

Export-ModuleMember -Function ConvertTo-StableGateId, Get-LegacyGateInventory, Test-LegacyGateInventory

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-RepoRelativePath {
    param(
        [Parameter(Mandatory = $true)][string] $RepoRoot,
        [Parameter(Mandatory = $true)][string] $Path
    )

    $normalized = $Path.Trim() -replace '\\', '/'
    if ($normalized.StartsWith('./')) { $normalized = $normalized.Substring(2) }
    if ([System.IO.Path]::IsPathRooted($normalized)) {
        return ([System.IO.Path]::GetRelativePath($RepoRoot, $normalized) -replace '\\', '/')
    }
    return $normalized
}

function Get-ApiTestSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $RepoRoot,
        [AllowEmptyCollection()][string[]] $ChangedPaths = @()
    )

    $testRoot = Join-Path $RepoRoot 'tests/api/K12QuestionGraph.Api.Tests'
    $testFiles = @(Get-ChildItem -LiteralPath $testRoot -Recurse -Filter '*.cs' -File |
        Where-Object { $_.Name -notmatch '\.(Designer|g)\.cs$' })
    $sharedFileNames = @('WorkerTestHarness.cs', 'PostgresGatedSmokeTests.cs')
    $sharedTests = @($testFiles |
        Where-Object { $_.Name -in $sharedFileNames } |
        ForEach-Object { ConvertTo-RepoRelativePath $RepoRoot $_.FullName })

    $selectedTests = New-Object System.Collections.Generic.List[string]
    $unmapped = New-Object System.Collections.Generic.List[string]

    function Resolve-FullSelection([string] $Reason) {
        [pscustomobject][ordered]@{
            status = 'full'
            reason = $Reason
            selectedPaths = @($ChangedPaths)
            sharedTests = @($sharedTests)
        }
    }

    foreach ($rawPath in @($ChangedPaths)) {
        foreach ($part in ([string]$rawPath -split ',')) {
            $path = ConvertTo-RepoRelativePath $RepoRoot $part
            if ([string]::IsNullOrWhiteSpace($path)) { continue }

            if ($path -like 'tests/api/*.cs') {
                if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $path) -PathType Leaf)) { continue }
                if ($sharedTests -notcontains $path -and $selectedTests -notcontains $path) {
                    $selectedTests.Add($path)
                }
                continue
            }

            if ($path -notlike 'apps/api/*.cs') { continue }
            if ($path -like 'apps/api/Data/Migrations/*' -or
                $path -like 'apps/api/Program.cs' -or
                $path -like 'apps/api/*.csproj' -or
                $path -like 'apps/api/Properties/*') {
                Write-Output (Resolve-FullSelection 'cross-cutting API composition, migration, or assembly boundary changed')
                return
            }

            if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $path) -PathType Leaf)) {
                $unmapped.Add($path)
                continue
            }

            $sourceFileName = [System.IO.Path]::GetFileNameWithoutExtension($path)
            $testSuffix = $sourceFileName -replace 'Store$', ''
            $testBaseNames = @(
                ($testSuffix + 'Tests')
                (($testSuffix + 'Store') + 'Tests')
            )
            if ([string]::Equals($sourceFileName, 'P0Entities', [StringComparison]::Ordinal)) {
                Write-Output (Resolve-FullSelection 'shared domain model changed')
                return
            }

            $foundNameMatch = $false
            foreach ($testFile in $testFiles) {
                $baseName = [string]$testFile.BaseName
                $isNameMatch = $false
                foreach ($candidateBaseName in $testBaseNames) {
                    if ([string]::Equals($baseName, [string]$candidateBaseName, [StringComparison]::Ordinal)) {
                        $isNameMatch = $true
                        break
                    }
                }
                if (-not $isNameMatch) { continue }
                $relativeMatch = ConvertTo-RepoRelativePath $RepoRoot $testFile.FullName
                if (-not $selectedTests.Contains($relativeMatch)) { $selectedTests.Add($relativeMatch) }
                $foundNameMatch = $true
            }
            if ($foundNameMatch) {
                continue
            }

            $pattern = "(?<![A-Za-z0-9_])$([regex]::Escape($sourceFileName))(?![A-Za-z0-9_])"
            $contentMatched = $false
            foreach ($testFile in $testFiles) {
                $testRelative = ConvertTo-RepoRelativePath $RepoRoot $testFile.FullName
                if ($sharedTests -contains $testRelative) { continue }
                if (Select-String -LiteralPath $testFile.FullName -Pattern $pattern -Quiet) {
                    if (-not $selectedTests.Contains($testRelative)) { $selectedTests.Add($testRelative) }
                    $contentMatched = $true
                }
            }
            if (-not $contentMatched) { $unmapped.Add($path) }
        }
    }

    if ($selectedTests.Count -eq 0) {
        Write-Output (Resolve-FullSelection 'no direct test reference found for changed API source')
        return
    }

    $classNames = New-Object System.Collections.Generic.List[string]
    foreach ($selectedTest in $selectedTests) {
        $testSource = Get-Content -LiteralPath (Join-Path $RepoRoot $selectedTest) -Raw
        foreach ($match in [regex]::Matches($testSource, '(?m)^\s*public\s+(?:sealed\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)')) {
            $className = $match.Groups[1].Value
            if (-not $classNames.Contains($className)) { $classNames.Add($className) }
        }
    }

    if ($classNames -contains 'ModelRoutingProjectionParityTests') {
        Write-Output (Resolve-FullSelection 'shared model routing configuration parity requires full API verification')
        return
    }
    if ($classNames.Count -eq 0) {
        Write-Output (Resolve-FullSelection 'could not resolve a test class name for a focused filter')
        return
    }

    $filterParts = @($classNames | ForEach-Object { "FullyQualifiedName~$_" })
    Write-Output ([pscustomobject][ordered]@{
        status = 'focused'
        reason = 'direct test naming or reference closure'
        selectedPaths = @($selectedTests)
        testFiles = @($selectedTests)
        sharedTests = @($sharedTests)
        unmappedPaths = @($unmapped | Sort-Object -Unique)
        totalTestFiles = $testFiles.Count
        testFilterExpression = ($filterParts -join '|')
    })
}

function Get-FrontendTestSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $RepoRoot,
        [AllowEmptyCollection()][string[]] $ChangedPaths = @()
    )

    $srcRoot = Join-Path (Join-Path $RepoRoot 'apps/web') 'src'
    $testFiles = @(Get-ChildItem -LiteralPath $srcRoot -Recurse -File |
        Where-Object { $_.Name -match '\.(test|spec)\.(ts|tsx)$' })
    $crossCutting = @('apps/web/package.json', 'apps/web/package-lock.json', 'apps/web/vite.config.ts',
        'apps/web/tsconfig.json', 'apps/web/tsconfig.app.json', 'apps/web/tsconfig.node.json',
        'apps/web/eslint.config.js', 'apps/web/eslint.config.ts')

    $selectedTests = New-Object System.Collections.Generic.List[string]
    $selectedSources = New-Object System.Collections.Generic.List[string]
    $unmapped = New-Object System.Collections.Generic.List[string]

    foreach ($rawPath in @($ChangedPaths)) {
        foreach ($part in ([string]$rawPath -split ',')) {
            $path = ConvertTo-RepoRelativePath $RepoRoot $part
            if ([string]::IsNullOrWhiteSpace($path)) { continue }
            if ($crossCutting -contains $path -or
                $path -like 'apps/web/src/test/*' -or
                $path -like 'apps/web/vite/*') {
                Write-Output ([pscustomobject][ordered]@{
                    status = 'full'
                    reason = 'shared frontend build, test setup, or proxy contract changed'
                    selectedPaths = @($ChangedPaths)
                })
                return
            }

            if ($path -like 'apps/web/src/*.test.ts' -or $path -like 'apps/web/src/*.test.tsx' -or
                $path -like 'apps/web/src/*.spec.ts' -or $path -like 'apps/web/src/*.spec.tsx') {
                if ((Test-Path -LiteralPath (Join-Path $RepoRoot $path) -PathType Leaf) -and -not $selectedTests.Contains($path)) {
                    $selectedTests.Add($path)
                }
                continue
            }

            if ($path -notlike 'apps/web/src/*.ts' -and $path -notlike 'apps/web/src/*.tsx') { continue }
            if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $path) -PathType Leaf)) {
                $unmapped.Add($path)
                continue
            }
            if (-not $selectedSources.Contains($path)) { $selectedSources.Add($path) }
        }
    }

    foreach ($sourcePath in $selectedSources) {
        $sourceBaseName = [System.IO.Path]::GetFileNameWithoutExtension($sourcePath)
        $directNames = @(
            "$($sourceBaseName).test.ts",
            "$($sourceBaseName).test.tsx",
            "$($sourceBaseName).spec.ts",
            "$($sourceBaseName).spec.tsx"
        )
        foreach ($directMatch in @($testFiles | Where-Object { $_.Name -in $directNames })) {
            $relativeMatch = ConvertTo-RepoRelativePath $RepoRoot $directMatch.FullName
            if (-not $selectedTests.Contains($relativeMatch)) { $selectedTests.Add($relativeMatch) }
        }
    }

    if ($selectedTests.Count -eq 0) {
        Write-Output ([pscustomobject][ordered]@{
            status = 'full'
            reason = 'no direct frontend test reference found'
            selectedPaths = @($ChangedPaths)
        })
        return
    }

    $runAll = $selectedTests.Count -gt [Math]::Ceiling($testFiles.Count / 2)
    $vitestPaths = @($selectedTests | ForEach-Object {
        $normalizedTestPath = ([string]$_ -replace '\\', '/')
        if ($normalizedTestPath.StartsWith('apps/web/', [StringComparison]::Ordinal)) {
            $normalizedTestPath.Substring('apps/web/'.Length)
        }
        else {
            $normalizedTestPath
        }
    })
    Write-Output ([pscustomobject][ordered]@{
        status = if ($runAll) { 'full' } else { 'focused' }
        reason = if ($runAll) { 'direct references span most frontend tests' } else { 'direct frontend test closure' }
        selectedPaths = @($selectedTests)
        vitestPaths = @($vitestPaths)
        unmappedPaths = @($unmapped | Sort-Object -Unique)
        totalTestFiles = $testFiles.Count
    })
}

Export-ModuleMember -Function Get-ApiTestSelection, Get-FrontendTestSelection

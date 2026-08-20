Set-StrictMode -Version Latest

function Invoke-KqgPowerShellParseSweep {
    param(
        [Parameter(Mandatory = $true)][string] $RepoRoot,
        [string[]] $ChangedPaths = @()
    )

    $errors = New-Object System.Collections.Generic.List[object]
    $scripts = if ($ChangedPaths.Count -eq 0) {
        @(Get-ChildItem -Path (Join-Path $RepoRoot 'tools') -Recurse -Include *.ps1 -File)
    }
    else {
        @($ChangedPaths |
            Where-Object { $_ -like 'tools/*.ps1' } |
            ForEach-Object { Join-Path $RepoRoot ($_ -replace '/', '\\') } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            ForEach-Object { Get-Item -LiteralPath $_ } |
            Sort-Object FullName -Unique)
    }
    $scripts = @($scripts)

    foreach ($script in $scripts) {
        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) {
            $errors.Add([ordered]@{
                path = ([System.IO.Path]::GetRelativePath($RepoRoot, $script.FullName) -replace '\\', '/')
                errors = @($parseErrors | ForEach-Object {
                    [ordered]@{
                        message = $_.Message
                        line = $_.Extent.StartLineNumber
                        column = $_.Extent.StartColumnNumber
                    }
                })
            })
        }
    }

    return [ordered]@{
        scriptCount = $scripts.Count
        errors = $errors
    }
}
function Invoke-KqgPythonCompileSweep {
    param(
        [Parameter(Mandatory = $true)][string] $RepoRoot,
        [string[]] $ChangedPaths = @()
    )

    $targets = if ($ChangedPaths.Count -eq 0) {
        @(
            Get-ChildItem -Path (Join-Path $RepoRoot 'tools') -Recurse -Include *.py -File -ErrorAction SilentlyContinue
            Get-ChildItem -Path (Join-Path $RepoRoot 'workers') -Recurse -Include *.py -File -ErrorAction SilentlyContinue
        ) | Sort-Object FullName -Unique
    }
    else {
        @($ChangedPaths |
            Where-Object { ($_ -like 'tools/*.py') -or ($_ -like 'workers/*.py') } |
            ForEach-Object { Join-Path $RepoRoot ($_ -replace '/', '\\') } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            ForEach-Object { Get-Item -LiteralPath $_ } |
            Sort-Object FullName -Unique)
    }
    $targets = @($targets)

    $failures = New-Object System.Collections.Generic.List[object]
    foreach ($target in $targets) {
        python -m py_compile $target.FullName 2>&1 | Out-String | ForEach-Object {
            if ($LASTEXITCODE -ne 0) {
                $failures.Add([ordered]@{
                    path = ([System.IO.Path]::GetRelativePath($RepoRoot, $target.FullName) -replace '\\', '/')
                    error = $_.Trim()
                })
            }
        }
    }

    return [ordered]@{
        scriptCount = $targets.Count
        errors = $failures
    }
}

function Assert-KqgQualitySweepPassed {
    param(
        [Parameter(Mandatory = $true)][hashtable] $Result,
        [Parameter(Mandatory = $true)][string] $Label
    )

    if ($Result.errors.Count -gt 0) {
        $json = $Result.errors | ConvertTo-Json -Depth 6
        throw "$Label failed: $json"
    }
}

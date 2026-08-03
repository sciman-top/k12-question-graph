param(
    [ValidateSet('Quick', 'Slice', 'Release', 'Onsite')]
    [string] $Profile = 'Quick',
    [string] $TaskId = '',
    [string[]] $ChangedPaths = @(),
    [string] $ReportRoot = 'tmp/verification/current',
    [switch] $DryRun,
    [switch] $AuthorizeStateful,
    [switch] $IncludeLegacyCompatibility
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$reportRootFullPath = Join-Path $repoRoot $ReportRoot
New-Item -ItemType Directory -Path $reportRootFullPath -Force | Out-Null

function Get-TrackedWorktreeSnapshot {
    return @(
        git -C $repoRoot status --porcelain=v1 --untracked-files=all |
            Where-Object { $_ -notmatch '^.. tmp[\\/]' } |
            Sort-Object
    ) -join "`n"
}

function Get-RepoProcessSnapshot {
    $normalizedRoot = $repoRoot.ToLowerInvariant()
    return @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -in @('dotnet.exe', 'K12QuestionGraph.Api.exe', 'node.exe') -and
                ([string]$_.CommandLine).ToLowerInvariant().Contains($normalizedRoot)
            } |
            Sort-Object ProcessId |
            ForEach-Object { "{0}:{1}" -f $_.ProcessId, $_.Name }
    )
}

function Invoke-VerifiedStep {
    param(
        [Parameter(Mandatory = $true)][string] $Id,
        [Parameter(Mandatory = $true)][scriptblock] $Action,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]] $Results
    )

    $logPath = Join-Path $reportRootFullPath "$Id.log"
    $started = Get-Date
    try {
        # Capture after the child process exits so Vitest/Vite cannot retain the log handle.
        $capturedOutput = @(& $Action *>&1)
        $capturedOutput | Set-Content -LiteralPath $logPath -Encoding UTF8
        $Results.Add([pscustomobject]@{
            id = $Id
            status = 'pass'
            durationMs = [int]((Get-Date) - $started).TotalMilliseconds
            log = (([System.IO.Path]::GetRelativePath($repoRoot, $logPath)) -replace '\\', '/')
        })
    }
    catch {
        $_ | Out-String | Add-Content -LiteralPath $logPath -Encoding UTF8
        $Results.Add([pscustomobject]@{
            id = $Id
            status = 'fail'
            durationMs = [int]((Get-Date) - $started).TotalMilliseconds
            log = (([System.IO.Path]::GetRelativePath($repoRoot, $logPath)) -replace '\\', '/')
            error = $_.Exception.Message
        })
        throw
    }
}

function Invoke-QuickProfile([AllowEmptyCollection()][System.Collections.Generic.List[object]] $Results) {
    $steps = @(
        [pscustomobject]@{ id = 'profile-inventory'; action = {
            & (Join-Path $PSScriptRoot 'run-verification-profile-inventory-guard.ps1') -JsonReportPath (Join-Path $ReportRoot 'profile-inventory.json') | Out-Null
        } },
        [pscustomobject]@{ id = 'backend-build'; action = {
            & dotnet build tests/api/K12QuestionGraph.Api.Tests/K12QuestionGraph.Api.Tests.csproj --no-restore
            if ($LASTEXITCODE -ne 0) { throw 'backend build failed' }
        } },
        [pscustomobject]@{ id = 'frontend-build'; action = {
            & npm --prefix apps/web run build
            if ($LASTEXITCODE -ne 0) { throw 'frontend build failed' }
        } },
        [pscustomobject]@{ id = 'frontend-lint'; action = {
            & npm --prefix apps/web run lint
            if ($LASTEXITCODE -ne 0) { throw 'frontend lint failed' }
        } },
        [pscustomobject]@{ id = 'script-quality'; action = {
            & (Join-Path $PSScriptRoot 'run-script-quality-sweep.ps1') -JsonReportPath (Join-Path $ReportRoot 'script-quality.json') | Out-Null
        } },
        [pscustomobject]@{ id = 'backend-tests'; action = {
            & dotnet test tests/api/K12QuestionGraph.Api.Tests/K12QuestionGraph.Api.Tests.csproj --no-restore --no-build
            if ($LASTEXITCODE -ne 0) { throw 'backend tests failed' }
        } },
        [pscustomobject]@{ id = 'frontend-tests'; action = {
            & npm --prefix apps/web run test
            if ($LASTEXITCODE -ne 0) { throw 'frontend tests failed' }
        } },
        [pscustomobject]@{ id = 'worker-tests'; action = {
            & python -m unittest discover -s tests/workers -p 'test_*.py'
            if ($LASTEXITCODE -ne 0) { throw 'worker tests failed' }
        } }
    )

    foreach ($step in $steps) {
        if ($DryRun) {
            $Results.Add([pscustomobject]@{ id = $step.id; status = 'selected'; durationMs = 0; log = $null })
        }
        else {
            Invoke-VerifiedStep -Id $step.id -Action $step.action -Results $Results
        }
    }
}

function Invoke-SliceStep {
    param(
        [Parameter(Mandatory = $true)][string] $Id,
        [Parameter(Mandatory = $true)][scriptblock] $Action,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]] $Results
    )

    if ($DryRun) {
        $Results.Add([pscustomobject]@{ id = $Id; status = 'selected'; durationMs = 0; log = $null })
    }
    else {
        Invoke-VerifiedStep -Id $Id -Action $Action -Results $Results
    }
}

function Invoke-ReleaseCoreProfile([AllowEmptyCollection()][System.Collections.Generic.List[object]] $Results) {
    $real005Entry = & (Join-Path $PSScriptRoot 'get-current-evidence.ps1') -Id 'real005-closure-standard' | ConvertFrom-Json
    $real005ReportPath = [string]$real005Entry.currentPath
    if ([string]::IsNullOrWhiteSpace($real005ReportPath)) {
        throw 'REAL005 current evidence path is missing'
    }

    $steps = @(
        [pscustomobject]@{ id = 'release-contracts'; action = {
            & (Join-Path $PSScriptRoot 'run-ns102-migration-baseline.ps1') -ReportPath (Join-Path $ReportRoot 'ns102-migration-baseline.json') | Out-Null
            & (Join-Path $PSScriptRoot 'run-ns203-privacy-license-scan.ps1') -ReportPath (Join-Path $ReportRoot 'ns203-privacy-license-scan.json') | Out-Null
            & (Join-Path $PSScriptRoot 'run-ns204-no-active-write-guard.ps1') -ReportPath (Join-Path $ReportRoot 'ns204-no-active-write.json') | Out-Null
            & (Join-Path $PSScriptRoot 'run-ns103-api-snapshot.ps1') -ReportPath (Join-Path $ReportRoot 'ns103-api-snapshot.md') | Out-Null
            & (Join-Path $PSScriptRoot 'run-ns104-application-service-boundary.ps1') -ReportPath (Join-Path $ReportRoot 'ns104-application-service-boundary.json') | Out-Null
        } },
        [pscustomobject]@{ id = 'release-upgrade-recovery'; action = {
            & (Join-Path $PSScriptRoot 'run-ns806-upgrade-bundle.ps1') `
                -ReportPath (Join-Path $ReportRoot 'ns806-upgrade-bundle.json') `
                -O007ReportPath (Join-Path $ReportRoot 'ns806-o007-source-report.json') `
                -O007RecoveryReportPath (Join-Path $ReportRoot 'ns806-o003-recovery-drill.json') | Out-Null
        } },
        [pscustomobject]@{ id = 'release-closure-invariants'; action = {
            & (Join-Path $PSScriptRoot 'run-scope-freeze-guard.ps1') -JsonReportPath (Join-Path $ReportRoot 'scope-freeze.json') | Out-Null
            & (Join-Path $PSScriptRoot 'run-reference-basis-guard.ps1') -ValidationMode Local -JsonReportPath (Join-Path $ReportRoot 'reference-basis.json') -MarkdownReportPath (Join-Path $ReportRoot 'reference-basis.md') | Out-Null
            & (Join-Path $PSScriptRoot 'run-evidence-index-guard.ps1') -JsonReportPath (Join-Path $ReportRoot 'evidence-index.json') | Out-Null
            & (Join-Path $PSScriptRoot 'run-release-coverage-reconciliation.ps1') -JsonReportPath (Join-Path $ReportRoot 'release-coverage.json') | Out-Null
            & (Join-Path $PSScriptRoot 'run-product-hotspot-budget-guard.ps1') -JsonReportPath (Join-Path $ReportRoot 'product-hotspot-budget.json') | Out-Null
            & (Join-Path $PSScriptRoot 'run-ui-behavior-contract-guard.ps1') -SkipTests -JsonReportPath (Join-Path $ReportRoot 'ui-behavior-contract.json') | Out-Null
            & (Join-Path $PSScriptRoot 'run-ns1308-release-evidence-pack-contract.ps1') -ReportPath (Join-Path $ReportRoot 'ns1308-release-evidence-pack.json') | Out-Null
            & (Join-Path $PSScriptRoot 'run-live-pilot-closeout-plan-guard.ps1') `
                -Real005ReportPath $real005ReportPath `
                -JsonReportPath (Join-Path $ReportRoot 'live-pilot-closeout-plan.json') `
                -MarkdownReportPath (Join-Path $ReportRoot 'live-pilot-closeout-plan.md') | Out-Null
            & (Join-Path $PSScriptRoot 'run-roadmap-guard.ps1') | Out-Null
        } }
    )

    foreach ($step in $steps) {
        if ($DryRun) {
            $Results.Add([pscustomobject]@{ id = $step.id; status = 'selected'; durationMs = 0; log = $null })
        }
        else {
            Invoke-VerifiedStep -Id $step.id -Action $step.action -Results $Results
        }
    }
}

function Invoke-SliceFocusedCommand {
    param(
        [Parameter(Mandatory = $true)][string] $Id,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]] $Results
    )

    switch ($Id) {
        'backend-tests' {
            Invoke-SliceStep -Id 'slice-backend-build' -Results $Results -Action {
                & dotnet build tests/api/K12QuestionGraph.Api.Tests/K12QuestionGraph.Api.Tests.csproj --no-restore
                if ($LASTEXITCODE -ne 0) { throw 'slice backend build failed' }
            }
            Invoke-SliceStep -Id 'slice-backend-tests' -Results $Results -Action {
                & dotnet test tests/api/K12QuestionGraph.Api.Tests/K12QuestionGraph.Api.Tests.csproj --no-restore --no-build
                if ($LASTEXITCODE -ne 0) { throw 'slice backend tests failed' }
            }
        }
        'frontend-tests' {
            Invoke-SliceStep -Id 'slice-frontend-build' -Results $Results -Action {
                & npm --prefix apps/web run build
                if ($LASTEXITCODE -ne 0) { throw 'slice frontend build failed' }
            }
            Invoke-SliceStep -Id 'slice-frontend-lint' -Results $Results -Action {
                & npm --prefix apps/web run lint
                if ($LASTEXITCODE -ne 0) { throw 'slice frontend lint failed' }
            }
            Invoke-SliceStep -Id 'slice-frontend-tests' -Results $Results -Action {
                & npm --prefix apps/web run test
                if ($LASTEXITCODE -ne 0) { throw 'slice frontend tests failed' }
            }
        }
        'worker-tests' {
            Invoke-SliceStep -Id 'slice-worker-compile' -Results $Results -Action {
                & python -m compileall -q workers
                if ($LASTEXITCODE -ne 0) { throw 'slice worker compile failed' }
            }
            Invoke-SliceStep -Id 'slice-worker-tests' -Results $Results -Action {
                & python -m unittest discover -s tests/workers -p 'test_*.py'
                if ($LASTEXITCODE -ne 0) { throw 'slice worker tests failed' }
            }
        }
        'script-quality' {
            Invoke-SliceStep -Id 'slice-script-quality' -Results $Results -Action {
                & (Join-Path $PSScriptRoot 'run-script-quality-sweep.ps1') -JsonReportPath (Join-Path $ReportRoot 'slice-script-quality.json') | Out-Null
            }
        }
        'verification-governance' {
            Invoke-SliceStep -Id 'slice-verification-governance' -Results $Results -Action {
                & (Join-Path $repoRoot 'tests/verification/run-verification-profile-parser-tests.ps1') | Out-Null
                & (Join-Path $repoRoot 'tests/verification/run-verification-slice-selector-tests.ps1') | Out-Null
                & (Join-Path $PSScriptRoot 'run-verification-profile-inventory-guard.ps1') -JsonReportPath (Join-Path $ReportRoot 'slice-profile-inventory.json') | Out-Null
            }
        }
        'governance-contracts' {
            Invoke-SliceStep -Id 'slice-governance-contracts' -Results $Results -Action {
                & (Join-Path $PSScriptRoot 'run-scope-freeze-guard.ps1') -JsonReportPath (Join-Path $ReportRoot 'scope-freeze.json') | Out-Null
                & (Join-Path $PSScriptRoot 'run-automation-first-feature-contract-guard.ps1') -JsonReportPath (Join-Path $ReportRoot 'automation-first.json') | Out-Null
                & (Join-Path $PSScriptRoot 'run-s001-completion-state-dashboard.ps1') -JsonReportPath (Join-Path $ReportRoot 'dashboard.json') -MarkdownReportPath (Join-Path $ReportRoot 'dashboard.md') | Out-Null
                & (Join-Path $PSScriptRoot 'run-s0-execution-plan-guard.ps1') -JsonReportPath (Join-Path $ReportRoot 's0.json') | Out-Null
                & (Join-Path $PSScriptRoot 'run-reference-basis-guard.ps1') -ValidationMode Ci -JsonReportPath (Join-Path $ReportRoot 'reference.json') -MarkdownReportPath (Join-Path $ReportRoot 'reference.md') | Out-Null
            }
        }
        'evidence-index' {
            Invoke-SliceStep -Id 'slice-evidence-index' -Results $Results -Action {
                $guard = Join-Path $PSScriptRoot 'run-evidence-index-guard.ps1'
                if (-not (Test-Path -LiteralPath $guard)) { throw 'evidence index guard is not installed' }
                & $guard -JsonReportPath (Join-Path $ReportRoot 'evidence-index.json') | Out-Null
            }
        }
        'ui-behavior' {
            Invoke-SliceStep -Id 'slice-ui-behavior' -Results $Results -Action {
                & (Join-Path $PSScriptRoot 'run-ui-behavior-contract-guard.ps1') -SkipTests -JsonReportPath (Join-Path $ReportRoot 'ui-behavior.json') | Out-Null
            }
        }
        'hotspot-budget' {
            Invoke-SliceStep -Id 'slice-hotspot-budget' -Results $Results -Action {
                & (Join-Path $PSScriptRoot 'run-product-hotspot-budget-guard.ps1') -JsonReportPath (Join-Path $ReportRoot 'hotspot-budget.json') | Out-Null
            }
        }
        default { throw "unknown focused Slice command: $Id" }
    }
}

$beforeWorktree = Get-TrackedWorktreeSnapshot
$beforeProcesses = @(Get-RepoProcessSnapshot)
$results = New-Object System.Collections.Generic.List[object]
$selection = $null
$releaseStateReconciliation = $null
$status = 'pass'
$failure = $null

try {
    Push-Location $repoRoot
    try {
        switch ($Profile) {
            'Quick' {
                Invoke-QuickProfile -Results $results
            }
            'Slice' {
                Import-Module (Join-Path $PSScriptRoot 'verification/VerificationSelection.psm1') -Force
                if ($ChangedPaths.Count -eq 0) {
                    $ChangedPaths = @(git status --porcelain=v1 --untracked-files=all | ForEach-Object {
                        $value = [string]$_
                        if ($value.Length -ge 4) { ($value.Substring(3) -split ' -> ')[-1] }
                    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                }
                $selection = Get-VerificationSelection -RepoRoot $repoRoot -ChangedPaths $ChangedPaths -TaskId $TaskId
                $selection | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $reportRootFullPath 'slice-selection.json') -Encoding UTF8
                if ($selection.status -ne 'pass') {
                    throw "Slice selection blocked or requires $($selection.escalatedProfile): unknown=$($selection.unknownPaths.Count) release=$($selection.releasePaths.Count) empty=$($selection.noSelection)"
                }
                foreach ($selected in $selection.selected) {
                    Invoke-SliceFocusedCommand -Id ([string]$selected.id) -Results $results
                }
            }
            'Release' {
                if (-not $DryRun -and -not $AuthorizeStateful) {
                    throw 'Release profile requires -AuthorizeStateful because release-core uses PostgreSQL plus isolated backup, restore, and upgrade rehearsal'
                }
                Invoke-QuickProfile -Results $results
                if (-not $DryRun) {
                    & (Join-Path $PSScriptRoot 'get-release-state-fingerprint.ps1') `
                        -JsonReportPath (Join-Path $ReportRoot 'release-state-before.json') | Out-Null
                }
                try {
                    Invoke-ReleaseCoreProfile -Results $results
                    if ($IncludeLegacyCompatibility) {
                        if ($DryRun) {
                            $results.Add([pscustomobject]@{ id = 'legacy-compatibility-audit'; status = 'selected'; durationMs = 0; log = $null })
                        }
                        else {
                            Invoke-VerifiedStep -Id 'legacy-compatibility-audit' -Results $results -Action {
                                $legacyFileStoreRoot = Join-Path $reportRootFullPath 'legacy-file-store'
                                & (Join-Path $PSScriptRoot 'run-gates.ps1') -FileStoreRoot $legacyFileStoreRoot
                            }
                        }
                    }
                }
                finally {
                    if (-not $DryRun) {
                            & (Join-Path $PSScriptRoot 'get-release-state-fingerprint.ps1') `
                                -JsonReportPath (Join-Path $ReportRoot 'release-state-after.json') | Out-Null
                            $beforeState = Get-Content -LiteralPath (Join-Path $reportRootFullPath 'release-state-before.json') -Raw | ConvertFrom-Json
                            $afterState = Get-Content -LiteralPath (Join-Path $reportRootFullPath 'release-state-after.json') -Raw | ConvertFrom-Json
                            $script:releaseStateReconciliation = [ordered]@{
                                migrationFilesUnchanged = $beforeState.migrationFileCount -eq $afterState.migrationFileCount -and $beforeState.migrationListingHash -eq $afterState.migrationListingHash
                                databaseShapeUnchanged = $beforeState.database.schemaTableCount -eq $afterState.database.schemaTableCount -and $beforeState.database.migrationCount -eq $afterState.database.migrationCount
                                databaseRowDataCompared = $false
                                fileStoreChanged = $beforeState.fileStore.fileCount -ne $afterState.fileStore.fileCount -or $beforeState.fileStore.totalBytes -ne $afterState.fileStore.totalBytes -or $beforeState.fileStore.listingHash -ne $afterState.fileStore.listingHash
                                fileStoreFileDelta = [int]$afterState.fileStore.fileCount - [int]$beforeState.fileStore.fileCount
                                fileStoreByteDelta = [long]$afterState.fileStore.totalBytes - [long]$beforeState.fileStore.totalBytes
                                sharedFileStoreWriteExpected = $false
                                boundary = 'Default release-core permits PostgreSQL read/migration rehearsal and isolated tmp backup/restore only; shared FileStore and migration shape must remain unchanged. Database row-level equality is not claimed.'
                            }
                            if (-not $script:releaseStateReconciliation.migrationFilesUnchanged -or
                                -not $script:releaseStateReconciliation.databaseShapeUnchanged -or
                                $script:releaseStateReconciliation.fileStoreChanged) {
                                throw 'release-core state reconciliation failed: migration, database shape, or shared FileStore changed'
                            }
                        }
                }
                }
            'Onsite' {
                throw 'Onsite profile cannot be completed by repo-side automation; import real environment, operator, input, timestamp, and signed acceptance evidence'
            }
        }
    }
    finally {
        Pop-Location
    }
}
catch {
    $status = 'fail'
    $failure = $_.Exception.Message
}

$afterWorktree = Get-TrackedWorktreeSnapshot
$afterProcesses = @(Get-RepoProcessSnapshot)
if ($Profile -in @('Quick', 'Slice', 'Release') -and -not $DryRun) {
    for ($attempt = 0; $attempt -lt 10 -and ((@($beforeProcesses) -join "`n") -ne (@($afterProcesses) -join "`n")); $attempt++) {
        Start-Sleep -Milliseconds 500
        $afterProcesses = @(Get-RepoProcessSnapshot)
    }
}
$worktreeUnchanged = $beforeWorktree -eq $afterWorktree
$processesUnchanged = (@($beforeProcesses) -join "`n") -eq (@($afterProcesses) -join "`n")
if (($Profile -in @('Quick', 'Slice') -or ($Profile -eq 'Release' -and -not $IncludeLegacyCompatibility)) -and (-not $worktreeUnchanged -or -not $processesUnchanged)) {
    $status = 'fail'
    $failure = "side-effect boundary violated: worktreeUnchanged=$worktreeUnchanged processesUnchanged=$processesUnchanged"
}

$report = [ordered]@{
    schemaVersion = 1
    status = $status
    profile = $Profile
    taskId = $TaskId
    dryRun = [bool]$DryRun
    checkedAt = (Get-Date).ToString('s')
    reportRoot = $ReportRoot
    worktreeUnchanged = $worktreeUnchanged
    processesUnchanged = $processesUnchanged
    selected = if ($null -eq $selection) { @() } else { @($selection.selected) }
    skipped = if ($null -eq $selection) { @() } else { @($selection.skipped) }
    sideEffectSummary = if ($null -eq $selection) { @() } else { @($selection.sideEffectSummary) }
    releaseCoreIncluded = $Profile -eq 'Release'
    legacyCompatibilityIncluded = $Profile -eq 'Release' -and [bool]$IncludeLegacyCompatibility
    releaseStateReconciliation = $releaseStateReconciliation
    steps = $results.ToArray()
    failure = $failure
    boundary = if ($Profile -eq 'Onsite') { 'not repo-side automatable' } else { 'repo-side verification only' }
}
$reportPath = Join-Path $reportRootFullPath 'verification-summary.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8

if ($status -ne 'pass') { throw $failure }

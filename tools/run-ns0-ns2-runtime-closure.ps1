param(
    [string] $ReportPath = 'docs/evidence/20260531-ns0-ns2-runtime-closure.json',
    [string] $PlanPath = 'tasks/non-site-implementation-plan.csv',
    [string] $RoadmapPath = 'docs/101_NonSiteCapabilityImplementationRoadmap.md',
    [string] $CompletionDashboardPath = 'tasks/completion-state-dashboard.csv',
    [string] $FullGateLogPath = 'docs/evidence/20260531-run-gates-ns1104-after-s012a-fix-2.log'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Resolve-RepoPath([string] $Path) {
    return Join-Path $repoRoot $Path
}

function Invoke-JsonGate([string] $Name, [string] $ScriptPath) {
    $started = Get-Date
    $fullPath = Resolve-RepoPath $ScriptPath
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing gate script for ${Name}: $ScriptPath"

    $output = & $fullPath 2>&1
    $exitCode = if ($LASTEXITCODE -is [int]) { $LASTEXITCODE } else { 0 }
    Assert-Condition ($exitCode -eq 0) "${Name} failed with exit code $exitCode"
    $text = ($output | Out-String).Trim()
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($text)) "${Name} produced empty output"

    $json = $text | ConvertFrom-Json
    Assert-Condition ($json.status -eq 'pass') "${Name} status is not pass"

    return [ordered]@{
        name = $Name
        script = $ScriptPath
        status = $json.status
        taskId = $json.taskId
        durationMs = [int]((Get-Date) - $started).TotalMilliseconds
    }
}

Push-Location $repoRoot
try {
    $closureIds = @(
        'NS001',
        'NS002',
        'NS003',
        'NS004',
        'NS005',
        'NS103',
        'NS105',
        'NS106',
        'NS201',
        'NS202',
        'NS203',
        'NS204'
    )

    foreach ($path in @($PlanPath, $RoadmapPath, $CompletionDashboardPath)) {
        Assert-Condition (Test-Path -LiteralPath (Resolve-RepoPath $path)) "missing closure input: $path"
    }

    $rows = @(Import-Csv -LiteralPath (Resolve-RepoPath $PlanPath) -Encoding UTF8)
    $rowById = @{}
    foreach ($row in $rows) {
        $rowById[$row.id] = $row
    }

    foreach ($id in $closureIds) {
        Assert-Condition ($rowById.ContainsKey($id)) "missing non-site row: $id"
        Assert-Condition ($rowById[$id].status -in @('repo_landed', 'runtime_verified')) "unexpected status for ${id}: $($rowById[$id].status)"
        $evidencePath = $rowById[$id].evidence
        Assert-Condition (-not [string]::IsNullOrWhiteSpace($evidencePath)) "missing evidence path for $id"
        Assert-Condition (Test-Path -LiteralPath (Resolve-RepoPath $evidencePath)) "evidence path missing for ${id}: $evidencePath"
    }

    $roadmap = Get-Content -LiteralPath (Resolve-RepoPath $RoadmapPath) -Raw
    foreach ($status in @('planned', 'contract_only', 'repo_landed', 'runtime_verified', 'non_site_validated', 'blocked_by_onsite')) {
        Assert-Condition ($roadmap.Contains($status)) "roadmap missing status definition: $status"
    }
    Assert-Condition ($roadmap.Contains('tasks/non-site-implementation-plan.csv')) 'roadmap missing machine-readable plan link'

    $completionRows = @(Import-Csv -LiteralPath (Resolve-RepoPath $CompletionDashboardPath) -Encoding UTF8)
    Assert-Condition ($completionRows.Count -ge 20) "completion dashboard row count too low: $($completionRows.Count)"
    foreach ($column in @('area_id', 'current_state', 'usable_today', 'blocking_gap', 'next_task')) {
        Assert-Condition ($completionRows[0].PSObject.Properties.Name -contains $column) "completion dashboard missing column: $column"
    }

    $moduleEvidence = Get-Content -LiteralPath (Resolve-RepoPath 'docs/evidence/20260528-ns003-module-ownership.md') -Raw
    foreach ($marker in @('apps/api', 'apps/web', 'workers/document', 'tools', 'tests', 'docs/evidence')) {
        Assert-Condition ($moduleEvidence.Contains($marker)) "module ownership evidence missing marker: $marker"
        $rootPath = Resolve-RepoPath $marker
        Assert-Condition (Test-Path -LiteralPath $rootPath) "module root missing: $marker"
    }

    $fixturePolicyPath = Resolve-RepoPath 'docs/102_NonSiteFixturePrivacyPolicy.md'
    $fixtureEvidencePath = Resolve-RepoPath 'docs/evidence/20260528-ns005-fixture-policy.md'
    $goldenPrivacyPath = Resolve-RepoPath 'tests/golden-import/privacy_and_license.md'
    $rawIgnorePath = Resolve-RepoPath 'sources/raw/.gitignore'
    foreach ($path in @($fixturePolicyPath, $fixtureEvidencePath, $goldenPrivacyPath, $rawIgnorePath)) {
        Assert-Condition (Test-Path -LiteralPath $path) "missing fixture/privacy boundary file: $path"
    }
    $fixtureText = (Get-Content -LiteralPath $fixturePolicyPath -Raw) + "`n" + (Get-Content -LiteralPath $goldenPrivacyPath -Raw)
    foreach ($marker in @('synthetic_fixture', 'authorized_anonymized_material', 'sources/raw')) {
        Assert-Condition ($fixtureText.Contains($marker)) "fixture/privacy policy missing marker: $marker"
    }
    Assert-Condition (($fixtureText.Contains('外部 AI') -or $fixtureText.Contains('External AI') -or $fixtureText.Contains('externalAi'))) 'fixture/privacy policy missing external AI boundary marker'

    $trackedRaw = @(git ls-files sources/raw)
    Assert-Condition (@($trackedRaw | Where-Object { $_ -ne 'sources/raw/.gitignore' }).Count -eq 0) 'sources/raw has tracked raw material beyond .gitignore'

    $ns103Report = 'docs/evidence/20260531-ns103-api-snapshot.md'
    & (Resolve-RepoPath 'tools/run-ns103-api-snapshot.ps1') -ReportPath $ns103Report | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) 'NS103 API snapshot refresh failed'
    Assert-Condition (Test-Path -LiteralPath (Resolve-RepoPath $ns103Report)) "NS103 refreshed report missing: $ns103Report"
    $ns103Text = Get-Content -LiteralPath (Resolve-RepoPath $ns103Report) -Raw
    foreach ($marker in @('状态：`pass`', 'API endpoint count', 'typed client function count', 'error code count')) {
        Assert-Condition ($ns103Text.Contains($marker)) "NS103 snapshot missing marker: $marker"
    }

    $runtimeGates = New-Object System.Collections.Generic.List[object]
    $runtimeGates.Add((Invoke-JsonGate 'NS004 non-site implementation plan guard' 'tools/run-non-site-implementation-plan-guard.ps1'))
    $runtimeGates.Add((Invoke-JsonGate 'NS105 teacher route typed client boundary' 'tools/run-ns105-teacher-route-client-boundary.ps1'))
    $runtimeGates.Add((Invoke-JsonGate 'NS106 feature profile guard' 'tools/run-ns106-feature-profile-guard.ps1'))
    $runtimeGates.Add((Invoke-JsonGate 'NS201 role audit baseline' 'tools/run-ns201-role-audit-baseline.ps1'))
    $runtimeGates.Add((Invoke-JsonGate 'NS202 admin internal fail closed' 'tools/run-ns202-admin-internal-fail-closed.ps1'))
    $runtimeGates.Add((Invoke-JsonGate 'NS203 privacy license scan' 'tools/run-ns203-privacy-license-scan.ps1'))
    $runtimeGates.Add((Invoke-JsonGate 'NS204 no active write guard' 'tools/run-ns204-no-active-write-guard.ps1'))
    $runtimeGateSummaries = @(
        foreach ($gate in $runtimeGates) {
            [ordered]@{
                name = [string]$gate.name
                script = [string]$gate.script
                status = [string]$gate.status
                taskId = [string]$gate.taskId
                durationMs = [int]$gate.durationMs
            }
        }
    )

    $fullGateEvidence = [ordered]@{
        path = $FullGateLogPath
        present = $false
        failStatusCount = $null
        exceptionCount = $null
    }
    if (Test-Path -LiteralPath (Resolve-RepoPath $FullGateLogPath)) {
        $fullGateLog = Resolve-RepoPath $FullGateLogPath
        $fullGateEvidence['present'] = $true
        $fullGateEvidence['failStatusCount'] = @(Select-String -Path $fullGateLog -Pattern '"status"\s*:\s*"fail"').Count
        $fullGateEvidence['exceptionCount'] = @(Select-String -Path $fullGateLog -Pattern 'Exception:|ParserError|CommandNotFoundException|UnauthorizedAccessException').Count
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS0_NS2_RUNTIME_CLOSURE'
        checkedAt = (Get-Date).ToString('s')
        mode = 'repo_landed_to_runtime_verified_closure_guard'
        targetRows = @($closureIds)
        productionEligible = $false
        externalAiCalls = 0
        realStudentDataUsed = $false
        writesProductionHistory = $false
        activeAssetMutation = $false
        documentEvidence = [ordered]@{
            roadmapStatusDictionary = $true
            completionDashboardRows = $completionRows.Count
            moduleOwnershipMarkers = @('apps/api', 'apps/web', 'workers/document', 'tools', 'tests', 'docs/evidence')
            fixturePolicyPresent = $true
            rawSourcesTrackedOnlyGitignore = $true
            ns103Snapshot = $ns103Report
        }
        runtimeGates = $runtimeGateSummaries
        fullGateEvidence = $fullGateEvidence
        acceptance = [ordered]@{
            ns001StatusDictionaryVerified = $true
            ns002CompletionDashboardParsed = $true
            ns003ModuleOwnershipVerified = $true
            ns004PlanGuardPassed = $true
            ns005FixturePrivacyPolicyVerified = $true
            ns103ApiSnapshotRefreshed = $true
            ns105TeacherRouteBoundaryPassed = $true
            ns106FeatureProfileGuardPassed = $true
            ns201RoleAuditBaselinePassed = $true
            ns202AdminInternalFailClosedPassed = $true
            ns203PrivacyLicenseScanPassed = $true
            ns204NoActiveWriteGuardPassed = $true
            noRawSourceTracked = $true
            noProductionWrite = $true
        }
        verification = [ordered]@{
            build = 'NS103 runs dotnet build before snapshot refresh'
            test = 'NS004/NS105/NS106/NS201/NS202/NS203/NS204 gates plus document/CSV/privacy probes'
            contractInvariant = 'NS0 state dictionary, dashboard, module ownership, fixture policy, API typed snapshot, feature/security/privacy/no-active-write boundaries are current and concrete'
            hotspot = 'gate_na: this is a governance/runtime-boundary closure pack; teacher-facing workflow hotspots are covered by later NS3-NS9 runtime scripts and full gate'
        }
        boundary = 'This closure pack upgrades early repo_landed NS0/NS1/NS2 governance and safety rows to runtime evidence. It does not change production defaults, process real student data, enable external AI, or close onsite/live pilot blockers.'
        rollback = 'git restore tasks/non-site-implementation-plan.csv tools/README.md; git clean -f -- tools/run-ns0-ns2-runtime-closure.ps1 docs/evidence/20260531-ns0-ns2-runtime-closure.json docs/evidence/20260531-ns103-api-snapshot.md'
        next = 'If this report passes, NS001-NS005, NS103, NS105, NS106, and NS201-NS204 can be marked runtime_verified while NS1001-NS1005 remain blocked_by_onsite.'
    }

    $reportFullPath = Resolve-RepoPath $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}

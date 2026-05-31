param(
    [string] $ReportPath = 'docs/evidence/20260531-ns1205-multischool-admission.json',
    [string] $NonSitePlanPath = 'tasks/non-site-implementation-plan.csv',
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $R005ReportPath = 'docs/evidence/20260521-r005-public-multischool-deploy-admission-report.json',
    [string] $R005DecisionPath = 'docs/decisions/ADR-007-public-multischool-deploy-admission.md',
    [string] $R005ChecklistPath = 'docs/templates/r005-public-multischool-deploy-eval-checklist.md',
    [string] $R005PreflightEvidencePath = 'docs/evidence/20260505-r005-public-multischool-deploy-eval-preflight.md',
    [string] $NS904ReportPath = 'docs/evidence/20260530-ns904-p001-readiness.json',
    [string] $CompletionDashboardPath = 'tasks/completion-state-dashboard.csv'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Resolve-InRepoPath([string] $RelativePath) {
    return Join-Path $repoRoot ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
}

function Read-Json([string] $Path) {
    $fullPath = Resolve-InRepoPath $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing json report: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Get-RequiredRow([object[]] $Rows, [string] $Id, [string] $Column = 'id') {
    $matches = @($Rows | Where-Object { [string]$_.$Column -eq $Id })
    Assert-Condition ($matches.Count -eq 1) "expected exactly one $Column=$Id row"
    return $matches[0]
}

function Assert-TextContains([string] $Text, [string[]] $Needles, [string] $Label) {
    foreach ($needle in $Needles) {
        Assert-Condition ($Text.Contains($needle)) "$Label missing text: $needle"
    }
}

function Find-CodePatternHits([string[]] $RelativeRoots, [string[]] $Patterns) {
    $hits = @()
    foreach ($relativeRoot in $RelativeRoots) {
        $fullRoot = Resolve-InRepoPath $relativeRoot
        if (-not (Test-Path -LiteralPath $fullRoot)) { continue }

        $files = @(Get-ChildItem -LiteralPath $fullRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $_.FullName -notmatch '\\(bin|obj|node_modules)\\'
        })
        foreach ($file in $files) {
            foreach ($pattern in $Patterns) {
                $matches = @(Select-String -LiteralPath $file.FullName -Pattern $pattern -CaseSensitive:$false -ErrorAction SilentlyContinue)
                foreach ($match in $matches) {
                    $hits += [ordered]@{
                        path = $file.FullName.Substring($repoRoot.Length + 1)
                        line = $match.LineNumber
                        pattern = $pattern
                    }
                }
            }
        }
    }

    return @($hits)
}

Push-Location $repoRoot
try {
    $planFullPath = Resolve-InRepoPath $NonSitePlanPath
    $backlogFullPath = Resolve-InRepoPath $BacklogPath
    $decisionFullPath = Resolve-InRepoPath $R005DecisionPath
    $checklistFullPath = Resolve-InRepoPath $R005ChecklistPath
    $preflightEvidenceFullPath = Resolve-InRepoPath $R005PreflightEvidencePath
    $completionDashboardFullPath = Resolve-InRepoPath $CompletionDashboardPath

    foreach ($requiredPath in @($planFullPath, $backlogFullPath, $decisionFullPath, $checklistFullPath, $preflightEvidenceFullPath, $completionDashboardFullPath)) {
        Assert-Condition (Test-Path -LiteralPath $requiredPath) "missing required file: $requiredPath"
    }

    $planRows = @(Import-Csv -LiteralPath $planFullPath -Encoding UTF8)
    $backlogRows = @(Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8)
    $dashboardRows = @(Import-Csv -LiteralPath $completionDashboardFullPath -Encoding UTF8)

    $ns1005 = Get-RequiredRow $planRows 'NS1005'
    $ns1205 = Get-RequiredRow $planRows 'NS1205'
    Assert-Condition ($ns1005.status -eq 'blocked_by_onsite') 'NS1205 must inherit NS1005 release-decision blocked_by_onsite boundary'
    Assert-Condition ($ns1205.depends_on -eq 'NS1005') 'NS1205 must continue to depend on NS1005'
    Assert-Condition ($ns1205.status -in @('planned','runtime_verified')) "NS1205 has unsupported status: $($ns1205.status)"
    Assert-Condition ($ns1205.acceptance -match '数据责任' -and $ns1205.acceptance -match '采购' -and $ns1205.acceptance -match 'SaaS' -and $ns1205.acceptance -match '多租户') 'NS1205 acceptance must keep public/multischool admission boundary'

    $p001 = Get-RequiredRow $backlogRows 'P001'
    $p006 = Get-RequiredRow $backlogRows 'P006'
    $r005 = Get-RequiredRow $backlogRows 'R005'
    Assert-Condition ($p001.status -eq '待办') 'NS1205 must not skip P001 isolated-machine evidence'
    Assert-Condition ($p006.status -eq '待办') 'NS1205 must not skip P006 release decision'
    Assert-Condition ($r005.status -eq '待办') 'NS1205 must not close R005 without public/multischool feature-admission evidence'
    Assert-Condition ($r005.depends_on -eq 'P006') 'R005 must continue to depend on P006'

    $r005Report = Read-Json $R005ReportPath
    $ns904Report = Read-Json $NS904ReportPath
    Assert-Condition ($r005Report.status -eq 'pass') 'NS1205 requires R005 admission report to pass'
    Assert-Condition (-not [bool]$r005Report.closeTaskAllowed) 'R005 closeTaskAllowed must remain false'
    Assert-Condition ($r005Report.currentDecision -eq 'keep_R005_todo_fail_closed_for_public_multischool') 'R005 decision must remain fail-closed for public/multischool'
    Assert-Condition ($ns904Report.status -eq 'pass') 'NS1205 requires NS904 readiness pack to pass'
    Assert-Condition (-not [bool]$ns904Report.p001CanClose) 'NS904 must keep P001 open'
    Assert-Condition (-not [bool]$ns904Report.releaseReady) 'NS904 must not claim release ready'
    Assert-Condition (-not [bool]$ns904Report.nonSiteValidated) 'NS904 must not claim non_site_validated'

    $matrixByKind = @{}
    foreach ($entry in @($r005Report.admissionMatrix)) {
        $matrixByKind[[string]$entry.deploymentKind] = $entry
    }
    foreach ($kind in @('single_school_lan', 'public_internet_exposure', 'multi_school_shared_deployment', 'multi_tenant_saas')) {
        Assert-Condition ($matrixByKind.ContainsKey($kind)) "R005 admission matrix missing: $kind"
    }
    Assert-Condition ($matrixByKind['single_school_lan'].currentDecision -eq 'preferred_default_after_p001_p006') 'single-school LAN must remain preferred default after P001/P006'
    Assert-Condition ($matrixByKind['public_internet_exposure'].currentDecision -eq 'blocked') 'public internet exposure must remain blocked'
    Assert-Condition ($matrixByKind['multi_school_shared_deployment'].currentDecision -eq 'blocked') 'multi-school shared deployment must remain blocked'
    Assert-Condition ($matrixByKind['multi_tenant_saas'].currentDecision -eq 'blocked') 'multi-tenant SaaS must remain blocked'

    $decisionText = Get-Content -LiteralPath $decisionFullPath -Raw
    Assert-TextContains $decisionText @(
        'ADR-007',
        'fail-closed',
        'Windows-first',
        'public internet exposure',
        'multi-school shared deployment',
        'multi-tenant SaaS',
        'tenant isolation',
        'rollback'
    ) 'ADR-007'

    $checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
    Assert-TextContains $checklistText @(
        'SaaS',
        '多租户',
        '采购',
        '运维边界',
        'tenant isolation',
        'rollback',
        'fail-closed'
    ) 'R005 checklist'

    $preflightText = Get-Content -LiteralPath $preflightEvidenceFullPath -Raw
    Assert-TextContains $preflightText @(
        'R005',
        'platform_na',
        'gate_na',
        '公网',
        'fail-closed'
    ) 'R005 preflight evidence'

    $deploymentArea = Get-RequiredRow $dashboardRows 'deployment-install' 'area_id'
    $livePilotArea = Get-RequiredRow $dashboardRows 'live-pilot' 'area_id'
    $backupRestoreArea = Get-RequiredRow $dashboardRows 'backup-restore' 'area_id'
    Assert-Condition ($deploymentArea.usable_today -eq '不可发布使用') 'deployment-install must remain not releasable'
    Assert-Condition ($livePilotArea.usable_today -eq '不可使用') 'live-pilot must remain unavailable'
    Assert-Condition ($backupRestoreArea.blocking_gap -match 'P001') 'backup-restore must retain P001 operational review boundary'

    $codePatternHits = Find-CodePatternHits @('apps/api', 'apps/web/src', 'configs', 'schemas', 'workers') @(
        '\bTenant\b',
        '\bMultiTenant\b',
        'tenant\s+isolation',
        'public\s+internet',
        'ReverseProxy',
        '\bYARP\b',
        'Kubernetes',
        'Ingress',
        'LetsEncrypt',
        'certbot'
    )
    Assert-Condition ($codePatternHits.Count -eq 0) 'NS1205 found product code/config that appears to enable public/multischool/SaaS deployment'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS1205'
        checkedAt = (Get-Date).ToString('s')
        mode = 'public_multischool_deploy_admission_boundary'
        productionEligible = $false
        nonSiteValidated = $false
        releaseReady = $false
        externalAiCalls = 0
        realStudentDataUsed = $false
        containsStudentPii = $false
        writesProductionHistory = $false
        activeAssetMutation = $false
        dependency = [ordered]@{
            ns1005 = $NonSitePlanPath
            ns904 = $NS904ReportPath
            r005Report = $R005ReportPath
            r005Decision = $R005DecisionPath
            r005Checklist = $R005ChecklistPath
            r005PreflightEvidence = $R005PreflightEvidencePath
            completionDashboard = $CompletionDashboardPath
        }
        backlog = [ordered]@{
            p001Status = [string]$p001.status
            p006Status = [string]$p006.status
            r005Status = [string]$r005.status
            r005CloseTaskAllowed = $false
            ns1005Status = [string]$ns1005.status
            ns1205StatusAtCheck = [string]$ns1205.status
            ns1205DependsOn = [string]$ns1205.depends_on
        }
        admissionDecision = [ordered]@{
            singleSchoolLan = [string]$matrixByKind['single_school_lan'].currentDecision
            publicInternetExposure = [string]$matrixByKind['public_internet_exposure'].currentDecision
            multiSchoolSharedDeployment = [string]$matrixByKind['multi_school_shared_deployment'].currentDecision
            multiTenantSaas = [string]$matrixByKind['multi_tenant_saas'].currentDecision
            currentDecision = [string]$r005Report.currentDecision
        }
        blockerSummary = [ordered]@{
            p001CanClose = [bool]$ns904Report.p001CanClose
            releaseReady = [bool]$ns904Report.releaseReady
            nonSiteValidated = [bool]$ns904Report.nonSiteValidated
            remainingSiteBlockerCount = @($ns904Report.remainingSiteBlockers).Count
        }
        codeScan = [ordered]@{
            searchedRoots = @('apps/api', 'apps/web/src', 'configs', 'schemas', 'workers')
            blockedPatterns = @('Tenant', 'MultiTenant', 'tenant isolation', 'public internet', 'ReverseProxy', 'YARP', 'Kubernetes', 'Ingress', 'LetsEncrypt', 'certbot')
            hitCount = [int]$codePatternHits.Count
            noPublicExposureRoute = $true
            noTenantSchemaOrConfig = $true
            noReverseProxyOrKubernetesDefault = $true
            noCrossSchoolSharedStore = $true
        }
        acceptance = [ordered]@{
            r005AdmissionReportPassed = $true
            adr007FailClosedAccepted = $true
            singleSchoolLanKeptAsOnlyPreferredPath = $true
            publicInternetBlocked = $true
            multiSchoolBlocked = $true
            multiTenantSaasBlocked = $true
            p001RemainsTodo = $true
            p006RemainsTodo = $true
            ns1005RemainsBlockedByOnsite = $true
            r005RemainsTodo = $true
            noNetworkExposure = $true
            noTenantSchemaChange = $true
            noDeploymentConfigMutation = $true
            noProductionWrite = $true
        }
        nextRequiredEvidence = @(
            'P001 isolated-machine evidence for install wizard, backup/restore, role audit, and four teacher-entry smokes',
            'P006 release decision record with rollback and privacy evidence',
            'security privacy ADR feature admission for public/multischool deployment',
            'procurement/DPA/SLA/operator responsibility evidence',
            'tenant/network/backup/audit isolation design with rollback and exit plan'
        )
        verification = [ordered]@{
            build = 'gate_na: admission boundary script only; no product code build required'
            test = 'tools/run-r005-public-multischool-deploy-eval-preflight-contract.ps1 + tools/run-ns1205-multischool-admission.ps1'
            contractInvariant = 'NS1205 keeps only single-school LAN as the future preferred route, leaves public/multischool/SaaS blocked, and verifies no tenant/network exposure config was enabled'
            hotspot = 'gate_na: public/multischool deployment admission requires P001/P006, data responsibility, procurement, network, ops, tenant isolation, and rollback evidence'
        }
        teacherEfficiencyBoundary = 'ordinary teacher workflows remain single-school/LAN first; NS1205 prevents deployment complexity from becoming teacher/admin burden before real responsibility boundaries exist'
        boundary = 'NS1205 verifies the public/multischool deployment admission boundary only. It does not expose the app to public networks, does not add tenant schema or config, does not configure reverse proxy/Kubernetes, and does not change release state.'
        rollback = "git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1 tools/README.md; git clean -f -- tools/run-ns1205-multischool-admission.ps1 $ReportPath"
        next = 'NS1206 can continue technical-debt cadence boundary; public/multischool deployment remains blocked until responsibility and onsite evidence exist.'
    }

    $jsonText = $report | ConvertTo-Json -Depth 12
    $reportFullPath = Resolve-InRepoPath $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $jsonText | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $jsonText
}
finally {
    Pop-Location
}

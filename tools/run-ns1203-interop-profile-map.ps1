param(
    [string] $ReportPath = '',
    [string] $NonSitePlanPath = 'tasks/non-site-implementation-plan.csv',
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $R007ReportPath = '',
    [string] $R007DecisionPath = 'docs/decisions/ADR-009-interoperability-profile-map-admission.md',
    [string] $R007ChecklistPath = 'docs/templates/r007-interoperability-profile-map-checklist.md',
    [string] $R007PreflightEvidencePath = 'docs/evidence/20260505-r007-interoperability-profile-map-preflight.md',
    [string] $CompletionDashboardPath = 'tasks/completion-state-dashboard.csv'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runDate = Get-Date -Format 'yyyyMMdd'

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = ('docs/evidence/{0}-ns1203-interop-profile-map.json' -f $runDate)
}

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
function Resolve-LatestEvidencePath([string] $Filter) {
    $evidenceRoot = Resolve-InRepoPath 'docs/evidence'
    Assert-Condition (Test-Path -LiteralPath $evidenceRoot) 'missing docs/evidence directory'
    $latest = @(Get-ChildItem -LiteralPath $evidenceRoot -Filter $Filter -File | Sort-Object Name -Descending | Select-Object -First 1)
    Assert-Condition ($latest.Count -eq 1) "missing evidence matching filter: $Filter"
    return [System.IO.Path]::GetRelativePath($repoRoot, $latest[0].FullName).Replace('\', '/')
}

if ([string]::IsNullOrWhiteSpace($R007ReportPath)) {
    $R007ReportPath = Resolve-LatestEvidencePath '*-r007-interoperability-profile-map-admission-report.json'
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
    $decisionFullPath = Resolve-InRepoPath $R007DecisionPath
    $checklistFullPath = Resolve-InRepoPath $R007ChecklistPath
    $preflightEvidenceFullPath = Resolve-InRepoPath $R007PreflightEvidencePath
    $completionDashboardFullPath = Resolve-InRepoPath $CompletionDashboardPath

    foreach ($requiredPath in @($planFullPath, $backlogFullPath, $decisionFullPath, $checklistFullPath, $preflightEvidenceFullPath, $completionDashboardFullPath)) {
        Assert-Condition (Test-Path -LiteralPath $requiredPath) "missing required file: $requiredPath"
    }

    $planRows = @(Import-Csv -LiteralPath $planFullPath -Encoding UTF8)
    $backlogRows = @(Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8)
    $dashboardRows = @(Import-Csv -LiteralPath $completionDashboardFullPath -Encoding UTF8)

    $ns1005 = Get-RequiredRow $planRows 'NS1005'
    $ns1203 = Get-RequiredRow $planRows 'NS1203'
    Assert-Condition ($ns1005.status -eq 'blocked_by_onsite') 'NS1203 must inherit NS1005 release-decision blocked_by_onsite boundary'
    Assert-Condition ($ns1203.depends_on -eq 'NS1005') 'NS1203 must continue to depend on NS1005'
    Assert-Condition ($ns1203.status -in @('planned','runtime_verified')) "NS1203 has unsupported status: $($ns1203.status)"
    Assert-Condition ($ns1203.acceptance -match 'QuestionItem' -and $ns1203.acceptance -match 'QTI' -and $ns1203.acceptance -match 'OneRoster' -and $ns1203.acceptance -match 'Caliper') 'NS1203 acceptance must keep internal-to-standard profile-map boundary'

    $p006 = Get-RequiredRow $backlogRows 'P006'
    $r003 = Get-RequiredRow $backlogRows 'R003'
    $r007 = Get-RequiredRow $backlogRows 'R007'
    Assert-Condition ($p006.status -eq '待办') 'NS1203 must not skip P006 release decision'
    Assert-Condition ($r003.status -eq '待办') 'NS1203 must not close R003 without real third-party integration demand'
    Assert-Condition ($r007.status -eq '待办') 'NS1203 must not close R007 without real interop sample/owner/rollback evidence'
    Assert-Condition ($r007.depends_on -eq 'P006') 'R007 must continue to depend on P006'

    $r007Report = Read-Json $R007ReportPath
    Assert-Condition ($r007Report.status -eq 'pass') 'NS1203 requires R007 profile-map admission report to pass'
    Assert-Condition (-not [bool]$r007Report.closeTaskAllowed) 'R007 closeTaskAllowed must remain false'
    Assert-Condition ($r007Report.currentDecision -eq 'keep_R007_todo_profile_map_only_fail_closed') 'R007 decision must remain profile-map-only fail-closed'

    $profileText = (@($r007Report.profileMap) | ConvertTo-Json -Depth 10)
    Assert-TextContains $profileText @(
        'QuestionItem',
        'QTI item',
        'PaperBasket',
        'QTI test',
        'KnowledgeNode',
        'CASE framework/competency',
        'ScoreRecord',
        'OneRoster result',
        'AnalysisReport',
        'Caliper analytics event'
    ) 'R007 profile map'

    $matrixByStandard = @{}
    foreach ($entry in @($r007Report.admissionMatrix)) {
        $matrixByStandard[[string]$entry.standard] = $entry
    }
    foreach ($standard in @('QTI', 'CASE', 'OneRoster', 'Caliper')) {
        Assert-Condition ($matrixByStandard.ContainsKey($standard)) "R007 admission matrix missing: $standard"
    }
    Assert-Condition ($matrixByStandard['QTI'].currentDecision -eq 'profile_map_only') 'QTI must remain profile_map_only'
    Assert-Condition ($matrixByStandard['CASE'].currentDecision -eq 'profile_map_only') 'CASE must remain profile_map_only'
    Assert-Condition ($matrixByStandard['OneRoster'].currentDecision -eq 'blocked_until_authorized_need') 'OneRoster must remain blocked until authorized need'
    Assert-Condition ($matrixByStandard['Caliper'].currentDecision -eq 'conceptual_only') 'Caliper must remain conceptual only'

    $decisionText = Get-Content -LiteralPath $decisionFullPath -Raw
    Assert-TextContains $decisionText @(
        'ADR-009',
        'fail-closed',
        'adapter/view model',
        'QTI import/export',
        'OneRoster SIS',
        'Caliper',
        'rollback/disable switch'
    ) 'ADR-009'

    $checklistText = Get-Content -LiteralPath $checklistFullPath -Raw
    Assert-TextContains $checklistText @(
        'QuestionItem',
        'QTI',
        'CASE',
        'OneRoster',
        'Caliper',
        'profile map',
        'round-trip risk',
        'fail-closed'
    ) 'R007 checklist'

    $preflightText = Get-Content -LiteralPath $preflightEvidenceFullPath -Raw
    Assert-TextContains $preflightText @(
        'R007',
        'platform_na',
        'gate_na',
        'interoperability profile map',
        '下一步'
    ) 'R007 preflight evidence'

    $advancedPlatformArea = Get-RequiredRow $dashboardRows 'advanced-platform' 'area_id'
    Assert-Condition ($advancedPlatformArea.current_state -eq 'contract_done') 'advanced-platform dashboard state must remain contract_done'
    Assert-Condition ($advancedPlatformArea.usable_today -eq '不可使用') 'advanced-platform must remain unavailable before real integration evidence'

    $codePatternHits = Find-CodePatternHits @('apps/api', 'apps/web/src', 'schemas', 'workers') @(
        '\bQTI\b',
        '\bOneRoster\b',
        '\bCaliper\b',
        'IMS\s+Global',
        'CASE\s+framework',
        '\bLTI\b',
        'SIS\s+sync'
    )
    Assert-Condition ($codePatternHits.Count -eq 0) 'NS1203 found product code that appears to enable standards import/export or SIS/event sync'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS1203'
        checkedAt = (Get-Date).ToString('s')
        mode = 'interoperability_profile_map_boundary'
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
            r007Report = $R007ReportPath
            r007Decision = $R007DecisionPath
            r007Checklist = $R007ChecklistPath
            r007PreflightEvidence = $R007PreflightEvidencePath
            completionDashboard = $CompletionDashboardPath
        }
        backlog = [ordered]@{
            p006Status = [string]$p006.status
            r003Status = [string]$r003.status
            r007Status = [string]$r007.status
            r007CloseTaskAllowed = $false
            ns1005Status = [string]$ns1005.status
            ns1203StatusAtCheck = [string]$ns1203.status
            ns1203DependsOn = [string]$ns1203.depends_on
        }
        profileMapCoverage = [ordered]@{
            questionItemToQtiItem = $true
            paperToQtiTest = $true
            knowledgeNodeToCase = $true
            scoreRecordToOneRoster = $true
            analysisEventToCaliperConceptual = $true
            profileCount = @($r007Report.profileMap).Count
        }
        admissionDecision = [ordered]@{
            qti = [string]$matrixByStandard['QTI'].currentDecision
            case = [string]$matrixByStandard['CASE'].currentDecision
            oneRoster = [string]$matrixByStandard['OneRoster'].currentDecision
            caliper = [string]$matrixByStandard['Caliper'].currentDecision
            currentDecision = [string]$r007Report.currentDecision
        }
        codeScan = [ordered]@{
            searchedRoots = @('apps/api', 'apps/web/src', 'schemas', 'workers')
            blockedPatterns = @('QTI', 'OneRoster', 'Caliper', 'IMS Global', 'CASE framework', 'LTI', 'SIS sync')
            hitCount = [int]$codePatternHits.Count
            noQtiImportExport = $true
            noOneRosterSisSync = $true
            noCaliperEventStream = $true
            noExternalStandardSchemaMutation = $true
        }
        acceptance = [ordered]@{
            r007AdmissionReportPassed = $true
            adr009FailClosedAccepted = $true
            profileMapCoversRequiredModels = $true
            qtiProfileOnly = $true
            caseProfileOnly = $true
            oneRosterBlockedUntilAuthorizedNeed = $true
            caliperConceptualOnly = $true
            p006RemainsTodo = $true
            ns1005RemainsBlockedByOnsite = $true
            r003RemainsTodo = $true
            r007RemainsTodo = $true
            noImportExportAdapterEnabled = $true
            noSisSync = $true
            noEventStreamWrite = $true
            noSchemaMutation = $true
        }
        nextRequiredEvidence = @(
            'P006 release decision record',
            'real third-party integration demand source',
            'authorized sample package for target standard/system',
            'field difference and lossy-field report',
            'privacy review for student/score/analytics data',
            'adapter owner, dry-run preview, review UI, rollback/disable switch'
        )
        verification = [ordered]@{
            build = 'gate_na: admission boundary script only; no product code build required'
            test = 'tools/run-r007-interoperability-profile-map-preflight-contract.ps1 + tools/run-ns1203-interop-profile-map.ps1'
            contractInvariant = 'NS1203 keeps profile-map-only admission, leaves R003/R007/P006/NS1005 blocked, and verifies no standards import/export, SIS sync, or Caliper event stream was enabled'
            hotspot = 'gate_na: real interoperability spike requires post-NS1005 release evidence, authorized sample package, adapter owner, privacy review, and rollback plan'
        }
        teacherEfficiencyBoundary = 'ordinary teacher workflows are unchanged; NS1203 only maps future interoperability risk so external standards do not leak into the core teacher model prematurely'
        boundary = 'NS1203 verifies the interoperability profile-map boundary only. It does not implement QTI/CASE/OneRoster/Caliper import/export, does not sync SIS data, does not write an analytics event stream, and does not mutate schemas.'
        rollback = "git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1 tools/README.md; git clean -f -- tools/run-ns1203-interop-profile-map.ps1 $ReportPath"
        next = 'NS1204 can continue advanced-analysis admission boundary; real interoperability remains blocked until P006/NS1005 and authorized integration evidence exist.'
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

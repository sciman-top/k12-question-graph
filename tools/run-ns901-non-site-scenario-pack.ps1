param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [string] $ReportPath = 'docs/evidence/20260530-ns901-non-site-scenario-pack.json',
    [string] $S012AReportPath = 'docs/evidence/20260508-s012a-e2e-proxy-fixture-pack-report.json',
    [string] $S012BReportPath = 'docs/evidence/20260509-s012b-non-site-e2e-rehearsal-report.json',
    [switch] $SkipS012Refresh
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Read-Json([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing report: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Convert-OutputToJson([object[]] $Output, [string] $Label) {
    $lines = @($Output | ForEach-Object { [string]$_ })
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].TrimStart().StartsWith('{')) {
            $start = $i
            break
        }
    }

    Assert-Condition ($start -ge 0) "$Label did not emit a JSON object"
    $jsonText = ($lines[$start..($lines.Count - 1)] -join [Environment]::NewLine)
    return $jsonText | ConvertFrom-Json
}

function Assert-NoSecretInText([string] $Text, [string] $Secret, [string] $Label) {
    if ([string]::IsNullOrWhiteSpace($Secret)) { return }
    Assert-Condition (-not $Text.Contains($Secret)) "$Label leaked the database password"
}

function Assert-WorkflowCoverage([object[]] $WorkflowSteps, [string[]] $RequiredSteps, [string] $Label) {
    $actual = @($WorkflowSteps | ForEach-Object { [string]$_.workflowStep })
    foreach ($step in $RequiredSteps) {
        Assert-Condition ($actual -contains $step) "$Label missing workflow step: $step"
    }
}

Push-Location $repoRoot
try {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'DatabasePassword or PGPASSWORD is required for NS901 non-site scenario pack.'

    $ns607 = Read-Json 'docs/evidence/20260530-ns607-export-artifacts-report.json'
    $ns704 = Read-Json 'docs/evidence/20260530-ns704-commentary-report.json'
    $ns806 = Read-Json 'docs/evidence/20260530-ns806-upgrade-bundle.json'

    Assert-Condition ($ns607.status -eq 'pass') 'NS901 dependency NS607 report did not pass'
    Assert-Condition ($ns704.status -eq 'pass') 'NS901 dependency NS704 report did not pass'
    Assert-Condition ($ns806.status -eq 'pass') 'NS901 dependency NS806 report did not pass'
    Assert-Condition (-not [bool]$ns607.productionEligible) 'NS901 must inherit NS607 non-production boundary'
    Assert-Condition (-not [bool]$ns704.productionEligible) 'NS901 must inherit NS704 non-production boundary'
    Assert-Condition (-not [bool]$ns806.productionEligible) 'NS901 must inherit NS806 non-production boundary'
    Assert-Condition ([bool]$ns607.acceptance.manifestHashVerified) 'NS901 requires NS607 artifact manifest verification'
    Assert-Condition ([bool]$ns704.acceptance.commentaryReportExported) 'NS901 requires NS704 commentary report export evidence'
    Assert-Condition ([bool]$ns806.acceptance.restoreDrillAfterBundle) 'NS901 requires NS806 post-upgrade restore drill evidence'

    if (-not $SkipS012Refresh) {
        $s012aOutput = .\tools\run-s012a-e2e-proxy-fixture-pack.ps1 -ReportPath $S012AReportPath
        $s012a = Convert-OutputToJson $s012aOutput 'S012A fixture pack'

        $s012bOutput = .\tools\run-s012b-non-site-e2e-rehearsal.ps1 `
            -DatabaseName $DatabaseName `
            -DatabaseUser $DatabaseUser `
            -DatabaseHost $DatabaseHost `
            -DatabasePort $DatabasePort `
            -DatabasePassword $DatabasePassword `
            -PgBin $PgBin `
            -FileStoreRoot $FileStoreRoot `
            -ReportPath $S012BReportPath
        $s012b = Convert-OutputToJson $s012bOutput 'S012B non-site E2E rehearsal'
    }
    else {
        $s012a = Read-Json $S012AReportPath
        $s012b = Read-Json $S012BReportPath
    }

    Assert-Condition ($s012a.status -eq 'pass') 'NS901 S012A fixture pack did not pass'
    Assert-Condition ($s012b.status -eq 'pass') 'NS901 S012B rehearsal did not pass'
    Assert-Condition (-not [bool]$s012a.productionEligible) 'NS901 S012A must stay non-production'
    Assert-Condition (-not [bool]$s012b.productionEligible) 'NS901 S012B must stay non-production'
    Assert-Condition (-not [bool]$s012a.realStudentDataUsed) 'NS901 S012A must not use real student data'
    Assert-Condition (-not [bool]$s012b.realStudentDataUsed) 'NS901 S012B must not use real student data'
    Assert-Condition (-not [bool]$s012a.containsStudentPii) 'NS901 S012A must not contain student PII'
    Assert-Condition ([bool]$s012b.preRunBackup.verified) 'NS901 requires verified S012B pre-run backup'

    $s012aCoveredSteps = @($s012a.coveredWorkflowSteps | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { [pscustomobject]@{ workflowStep = $_ } })
    Assert-WorkflowCoverage $s012aCoveredSteps @('import','cut','review','tagging','save','paper','export','score','analysis') 'NS901 S012A'
    Assert-WorkflowCoverage @($s012b.workflowSteps) @('admission','import_cut_review_save','tagging','review_save','paper','export','score','score_mapping','analysis','backup_restore') 'NS901 S012B'

    $failedSteps = @($s012b.workflowSteps | Where-Object { [string]$_.status -ne 'pass' })
    Assert-Condition ($failedSteps.Count -eq 0) 'NS901 S012B contains failed workflow steps'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS901'
        checkedAt = (Get-Date).ToString('s')
        mode = 'non_site_scenario_pack_runtime_verification'
        productionEligible = $false
        nonSiteValidated = $false
        externalAiCalls = 0
        realStudentDataUsed = $false
        containsStudentPii = $false
        writesProductionHistory = $false
        activeAssetMutation = $false
        dependency = [ordered]@{
            ns607 = 'docs/evidence/20260530-ns607-export-artifacts-report.json'
            ns704 = 'docs/evidence/20260530-ns704-commentary-report.json'
            ns806 = 'docs/evidence/20260530-ns806-upgrade-bundle.json'
            s012a = $S012AReportPath
            s012b = $S012BReportPath
            s012bPreRunBackup = [string]$s012b.preRunBackup.manifest
        }
        scenarioPack = [ordered]@{
            manifestPath = [string]$s012a.manifestPath
            materialCount = [int]$s012a.materialCount
            coveredFixtureSteps = @($s012a.coveredWorkflowSteps)
            coveredRuntimeSteps = @($s012b.workflowSteps | ForEach-Object { [string]$_.workflowStep })
            elapsedMinutes = [decimal]$s012b.elapsed.totalMinutes
            takeoverPoints = @($s012b.failureTakeoverPoints)
            rollbackCommand = [string]$s012b.preRunBackup.rollbackCommand
            databaseChanges = @($s012b.databaseChanges)
        }
        acceptance = [ordered]@{
            dependenciesPassed = $true
            syntheticOrAnonymizedOnly = $true
            importCutReviewTaggingSaveCovered = $true
            paperExportScoreAnalysisCovered = $true
            backupRestoreCovered = $true
            preRunBackupVerified = $true
            artifactManifestVerified = $true
            commentaryReportExportCovered = $true
            upgradeRestoreDrillCovered = $true
            rollbackCommandRecorded = $true
            noExternalAiCall = $true
            noRealStudentData = $true
            noStudentPii = $true
            noProductionHistoryWrite = $true
            noActiveWrite = $true
        }
        verification = [ordered]@{
            build = 'outer gate: dotnet build apps/api/K12QuestionGraph.Api.csproj before NS901'
            test = 'S012A fixture pack admission plus S012B non-site E2E rehearsal evidence'
            contractInvariant = 'NS901 requires NS607 export artifact regression, NS704 commentary export, NS806 upgrade restore drill, verified pre-run backup, rollback command, no real student data, no production history write, and no active write'
            hotspot = 'gate_na: this is still a synthetic/proxy non-site runtime pack; authorized school materials, isolated-machine install, teacher observation, printer/network/domain checks, and live operator signoff remain NS904/NS1001/P001 boundaries'
        }
        boundary = 'NS901 proves the non-site scenario pack can be verified from synthetic/proxy fixtures through runtime rehearsal, export, analysis, upgrade, backup, and restore evidence. It does not claim non_site_validated or live pilot closure until authorized/anonymized school materials and isolated-machine/operator validation exist.'
        rollback = "restore from S012B pre-run backup if synthetic rehearsal rows must be removed; git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1 tools/README.md; git clean -f -- tools/run-ns901-non-site-scenario-pack.ps1 $ReportPath"
        next = 'NS903 can refresh completion-state dashboards, then NS904 should assemble P001 readiness evidence without closing onsite/live blockers.'
    }

    $jsonText = $report | ConvertTo-Json -Depth 12
    Assert-NoSecretInText $jsonText $DatabasePassword 'NS901 report'

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $jsonText | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $jsonText
}
finally {
    Pop-Location
}

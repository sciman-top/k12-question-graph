param(
    [string] $WorkRoot = 'tmp/live-pilot-closeout-import-contract'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Resolve-InRepoPath([string] $RelativePath) {
    return Join-Path $repoRoot ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
}

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Resolve-LatestEvidencePath([string] $Filter, [string] $PreferredPath) {
    $evidenceRoot = Resolve-InRepoPath 'docs/evidence'
    $matches = @(Get-ChildItem -LiteralPath $evidenceRoot -Filter $Filter -File | Sort-Object Name)
    if ($matches.Count -gt 0) {
        return ('docs/evidence/' + $matches[-1].Name)
    }

    Assert-Condition (-not [string]::IsNullOrWhiteSpace($PreferredPath)) "missing evidence for filter: $Filter"
    $preferredFullPath = Resolve-InRepoPath $PreferredPath
    Assert-Condition (Test-Path -LiteralPath $preferredFullPath -PathType Leaf) "missing preferred evidence path: $PreferredPath"
    return ($PreferredPath -replace '\\', '/')
}

function Write-JsonFile([string] $Path, [object] $Value) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Ensure-NS1001ImportSmokeFixture([string] $FixtureRelativePath) {
    $fixtureFullPath = Resolve-InRepoPath $FixtureRelativePath
    if (Test-Path -LiteralPath $fixtureFullPath -PathType Container) {
        return $fixtureFullPath
    }

    & (Join-Path $repoRoot 'tools/run-ns1001-isolated-machine-pack-contract.ps1') | Out-Null

    $latestPackReport = Get-ChildItem -LiteralPath (Resolve-InRepoPath 'docs/evidence') -File -Filter '*-ns1001-isolated-machine-execution-pack.json' |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    Assert-Condition ($null -ne $latestPackReport) 'missing NS1001 execution-pack report for import smoke fixture'

    $packReport = Get-Content -LiteralPath $latestPackReport.FullName -Raw | ConvertFrom-Json
    $packRootPath = [string]$packReport.packRoot
    $packRootFullPath = if ([System.IO.Path]::IsPathRooted($packRootPath)) {
        $packRootPath
    }
    else {
        Resolve-InRepoPath $packRootPath
    }
    Assert-Condition (Test-Path -LiteralPath $packRootFullPath -PathType Container) "missing NS1001 execution pack root: $packRootPath"

    New-Item -ItemType Directory -Path $fixtureFullPath -Force | Out-Null
    foreach ($entry in Get-ChildItem -LiteralPath $packRootFullPath -Force) {
        $targetPath = Join-Path $fixtureFullPath $entry.Name
        Copy-Item -LiteralPath $entry.FullName -Destination $targetPath -Recurse -Force
    }

    $returnEvidenceJsonFullPath = Join-Path $fixtureFullPath 'return/p001-isolated-machine-evidence.json'
    $returnEvidenceMarkdownFullPath = Join-Path $fixtureFullPath 'return/p001-isolated-machine-evidence.md'
    $returnAttachmentsRootFullPath = Join-Path $fixtureFullPath 'return/attachments'
    New-Item -ItemType Directory -Path $returnAttachmentsRootFullPath -Force | Out-Null

    $returnEvidence = Get-Content -LiteralPath $returnEvidenceJsonFullPath -Raw | ConvertFrom-Json
    $attachmentRelativePath = 'return/attachments/smoke/health-ready.txt'
    $attachmentFullPath = Join-Path $fixtureFullPath ($attachmentRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    New-Item -ItemType Directory -Path (Split-Path -Parent $attachmentFullPath) -Force | Out-Null
    Set-Content -LiteralPath $attachmentFullPath -Value 'ns1001 import smoke attachment' -Encoding UTF8

    $returnEvidence.execution.date = Get-Date -Format 'yyyy-MM-dd'
    $returnEvidence.execution.machineId = 'smoke-isolated-machine'
    $returnEvidence.execution.location = 'repo-smoke-lab'
    $returnEvidence.execution.operator = 'codex-smoke'
    $returnEvidence.execution.supportOwner = 'support-owner'
    $returnEvidence.execution.rollbackOwner = 'release-owner'
    $returnEvidence.anchors.checklistVerified = $true

    $returnEvidence.installInit.status = 'blocked'
    $returnEvidence.installInit.installDir = 'D:\KQG_App'
    $returnEvidence.installInit.dataDir = 'D:\KQG_Data'
    $returnEvidence.installInit.backupDir = 'D:\KQG_Backups'
    $returnEvidence.installInit.pgpassNonInteractiveOk = $true
    $returnEvidence.installInit.hostCapabilitySummary = 'smoke fixture reused latest execution pack host diagnostics'
    $returnEvidence.installInit.workerProfileSummary = 'direct_venv_lite'
    $returnEvidence.installInit.technologyRefreshSummary = 'report_only'
    $returnEvidence.installInit.initLogPaths = @($attachmentRelativePath)
    $returnEvidence.installInit.commands = @(
        [ordered]@{
            command = 'installer smoke fixture'
            exitCode = '0'
            keyOutput = 'latest execution pack reused for import contract smoke'
        }
    )

    $returnEvidence.backupRestore.status = 'blocked'
    $returnEvidence.backupRestore.backupManifestPath = 'tmp/ns801-backups/smoke/manifest.json'
    $returnEvidence.backupRestore.verifySummary = 'smoke fixture placeholder'
    $returnEvidence.backupRestore.restoreSummary = 'smoke fixture placeholder'
    $returnEvidence.backupRestore.healthReadinessSummary = 'ready'
    $returnEvidence.backupRestore.rollbackCommand = 'pwsh -File tools/verify-backup.ps1'
    $returnEvidence.backupRestore.attachmentPaths = @($attachmentRelativePath)
    $returnEvidence.backupRestore.commands = @(
        [ordered]@{
            command = 'backup restore smoke fixture'
            exitCode = '0'
            keyOutput = 'placeholder backup/restore evidence for contract import'
        }
    )

    $returnEvidence.roleAudit.status = 'blocked'
    $returnEvidence.roleAudit.teacherGroupLeadAdminSeparation = 'smoke fixture placeholder'
    $returnEvidence.roleAudit.adminFailClosed = 'smoke fixture placeholder'
    $returnEvidence.roleAudit.internalAiFailClosed = 'smoke fixture placeholder'
    $returnEvidence.roleAudit.auditLogPaths = @($attachmentRelativePath)
    $returnEvidence.roleAudit.domainPermissionSummary = 'domain permission still blocked in smoke fixture'
    $returnEvidence.roleAudit.commands = @(
        [ordered]@{
            command = 'role audit smoke fixture'
            exitCode = '0'
            keyOutput = 'placeholder audit evidence for contract import'
        }
    )

    foreach ($entryName in @('import', 'paperAssembly', 'scoreImport', 'analysis')) {
        $returnEvidence.teacherEntrySmokes.$entryName.status = 'blocked'
        $returnEvidence.teacherEntrySmokes.$entryName.durationMinutes = '5'
        $returnEvidence.teacherEntrySmokes.$entryName.blockers = @('smoke_fixture_site_run_not_executed')
        $returnEvidence.teacherEntrySmokes.$entryName.takeoverPoints = @('keep_blocked_until_real_isolated_machine_run')
        $returnEvidence.teacherEntrySmokes.$entryName.rollbackAction = 'keep_blocked'
        $returnEvidence.teacherEntrySmokes.$entryName.attachmentPaths = @($attachmentRelativePath)
    }

    $returnEvidence.siteSpecific.printerSummary = 'printer not executed in smoke fixture'
    $returnEvidence.siteSpecific.networkSummary = 'network not executed in smoke fixture'
    $returnEvidence.siteSpecific.domainPermissionSummary = 'domain permission not executed in smoke fixture'
    $returnEvidence.siteSpecific.openBlockers = @('smoke_fixture_site_checks_not_executed')
    $returnEvidence.siteSpecific.attachmentPaths = @($attachmentRelativePath)

    $returnEvidence.na.platformNa.used = $false
    $returnEvidence.na.gateNa.used = $false

    $returnEvidence.signoff.decision = 'keep_blocked'
    $returnEvidence.signoff.remainingRisks = @('smoke fixture preserves site blockers')
    $returnEvidence.signoff.rollbackConfirmed = $true
    $returnEvidence.signoff.operatorSignoff = 'codex-smoke'
    $returnEvidence.signoff.supportOwnerSignoff = 'support-owner'
    $returnEvidence.signoff.releaseOwnerReview = 'release-owner'

    $returnEvidence | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $returnEvidenceJsonFullPath -Encoding UTF8
    Set-Content -LiteralPath $returnEvidenceMarkdownFullPath -Value "# P001 isolated-machine import smoke`r`n`r`n- decision: keep_blocked`r`n- note: smoke fixture regenerated from latest execution pack." -Encoding UTF8

    return $fixtureFullPath
}

Push-Location $repoRoot
try {
    $workRootFullPath = Resolve-InRepoPath $WorkRoot
    New-Item -ItemType Directory -Path $workRootFullPath -Force | Out-Null
    $currentDate = Get-Date -Format 'yyyy-MM-dd'
    $latestP002ReportPath = Resolve-LatestEvidencePath '*-p002-teacher-proxy-pilot-admission-report.json' 'docs/evidence/20260614-p002-teacher-proxy-pilot-admission-report.json'
    $latestP003ReportPath = Resolve-LatestEvidencePath '*-p003-onsite-pilot-admission-report.json' 'docs/evidence/20260614-p003-onsite-pilot-admission-report.json'
    $latestP004ReportPath = Resolve-LatestEvidencePath '*-p004-onsite-pilot-round1-report.json' 'docs/evidence/20260614-p004-onsite-pilot-round1-report.json'
    $latestNs904ReportPath = Resolve-LatestEvidencePath '*-ns904-p001-readiness.json' 'docs/evidence/20260617-ns904-p001-readiness.json'
    $latestCloseoutGuardPath = Resolve-LatestEvidencePath '*-live-pilot-closeout-plan-guard.md' 'docs/evidence/20260617-live-pilot-closeout-plan-guard.md'

    $p001ReturnedPackRoot = Ensure-NS1001ImportSmokeFixture -FixtureRelativePath 'tmp/ns1001-import-smoke'

    $p001EvidenceOutputPath = Join-Path $WorkRoot 'p001/p001-isolated-machine.md'
    $p001AttachmentOutputRoot = Join-Path $WorkRoot 'p001/attachments'
    $p001ReportPath = Join-Path $WorkRoot 'p001/ns1001-validation.json'

    & (Join-Path $repoRoot 'tools/run-ns1001-isolated-machine-evidence-import.ps1') `
        -ReturnedPackRoot $p001ReturnedPackRoot `
        -EvidenceOutputPath $p001EvidenceOutputPath `
        -AttachmentOutputRoot $p001AttachmentOutputRoot `
        -ReportPath $p001ReportPath | Out-Null

    $p001Report = Get-Content -LiteralPath (Resolve-InRepoPath $p001ReportPath) -Raw | ConvertFrom-Json
    Assert-Condition ([string]$p001Report.status -eq 'pass') 'P001 import contract expected status=pass'
    Assert-Condition ([string]$p001Report.taskId -eq 'NS1001') 'P001 import contract expected taskId=NS1001'
    Assert-Condition (-not [bool]$p001Report.decision.closeP001Allowed) 'P001 smoke fixture should keep closeP001Allowed=false'

    $p003TemplatePath = 'docs/templates/p003-onsite-pilot-admission-card-template.json'
    $p003Template = Get-Content -LiteralPath (Resolve-InRepoPath $p003TemplatePath) -Raw | ConvertFrom-Json
    Assert-Condition ([string]$p003Template.schemaVersion -eq 'p003-onsite-pilot-admission-card.v1') 'P003 template schema mismatch'
    Assert-Condition ($p003Template.PSObject.Properties.Name -contains 'admissionContext') 'P003 template missing admissionContext'

    $p003RecordJsonPath = Join-Path $workRootFullPath 'p003/p003-pilot-admission-card.json'
    $p003RecordMarkdownPath = Join-Path $workRootFullPath 'p003/p003-pilot-admission-card.md'
    $p003ReportPath = Join-Path $WorkRoot 'p003/p003-validation.json'
    $p003Record = [ordered]@{
        schemaVersion = 'p003-onsite-pilot-admission-card.v1'
        admissionContext = [ordered]@{
            date = $currentDate
            site = 'school-lab'
            operator = 'pilot-coordinator'
            teacherOrProxy = 'proxy-teacher'
            admissionDecision = 'keep_blocked'
            sourceEvidence = $latestP002ReportPath
        }
        teacherBoundary = [ordered]@{
            participants = @('teacher-a')
            allowedActions = @('import', 'paper', 'analysis')
            forbiddenActions = @('admin_active_switch', 'real_external_ai')
            observationGoal = 'validate teacher understanding before onsite round1'
        }
        dataAuthorization = [ordered]@{
            materialScope = 'anonymized_only'
            expiresAt = '2026-06-30'
            owner = 'data-owner'
            prohibitedActions = @('send_real_student_data_to_external_ai')
        }
        supportContacts = [ordered]@{
            onsiteSupport = 'support-owner'
            techSupport = 'tech-owner'
            escalationContact = 'release-owner'
        }
        rollbackPlan = [ordered]@{
            trigger = 'teacher confusion or environment blocker'
            action = 'return to offline-first and operator takeover'
            owner = 'release-owner'
            recoveryEntry = 'docs/109_ReleaseGoNoGoCard.md'
        }
        feedbackTemplate = [ordered]@{
            path = 'docs/templates/p005-pilot-feedback-triage-template.json'
            collectionCadence = 'per_session'
            escalationPath = 'product-owner -> release-owner'
        }
        signoff = [ordered]@{
            productOwner = 'product-owner-signed'
            dataOwnerRepresentative = 'data-owner-signed'
            supportOwner = 'support-owner-signed'
            releaseOwner = 'release-owner-signed'
        }
        decisionNotes = @(
            'P002 proxy evidence exists, but onsite admission stays blocked until real site confirmation.',
            'No AI or proxy replaces final responsibility signoff.'
        )
    }
    Write-JsonFile -Path $p003RecordJsonPath -Value $p003Record
    Set-Content -LiteralPath $p003RecordMarkdownPath -Value "# P003 pilot admission smoke`r`n" -Encoding UTF8

    & (Join-Path $repoRoot 'tools/run-p003-onsite-pilot-admission-card-import.ps1') `
        -RecordJsonPath ([System.IO.Path]::GetRelativePath($repoRoot, $p003RecordJsonPath).Replace('\', '/')) `
        -RecordMarkdownPath ([System.IO.Path]::GetRelativePath($repoRoot, $p003RecordMarkdownPath).Replace('\', '/')) `
        -ReportPath $p003ReportPath | Out-Null

    $p003Report = Get-Content -LiteralPath (Resolve-InRepoPath $p003ReportPath) -Raw | ConvertFrom-Json
    Assert-Condition ([string]$p003Report.status -eq 'pass') 'P003 import contract expected status=pass'
    Assert-Condition ([string]$p003Report.taskId -eq 'P003') 'P003 import contract expected taskId=P003'
    Assert-Condition ([string]$p003Report.decision.requested -eq 'keep_blocked') 'P003 import contract expected keep_blocked decision'

    $p004TemplatePath = 'docs/templates/p004-onsite-pilot-round1-evidence-template.json'
    $p004Template = Get-Content -LiteralPath (Resolve-InRepoPath $p004TemplatePath) -Raw | ConvertFrom-Json
    Assert-Condition ([string]$p004Template.schemaVersion -eq 'p004-onsite-pilot-round1-evidence.v1') 'P004 template schema mismatch'
    Assert-Condition ($p004Template.PSObject.Properties.Name -contains 'pilotContext') 'P004 template missing pilotContext'

    $p004RecordJsonPath = Join-Path $workRootFullPath 'p004/p004-teacher-pilot-evidence.json'
    $p004RecordMarkdownPath = Join-Path $workRootFullPath 'p004/p004-teacher-pilot-evidence.md'
    $p004ReportPath = Join-Path $WorkRoot 'p004/p004-validation.json'
    $p004Record = [ordered]@{
        schemaVersion = 'p004-onsite-pilot-round1-evidence.v1'
        pilotContext = [ordered]@{
            date = $currentDate
            site = 'school-lab'
            operator = 'pilot-coordinator'
            teacher = 'teacher-a'
            sourceEvidence = $latestP003ReportPath
            decision = 'keep_blocked'
        }
        prefilledChecks = [ordered]@{
            routeSmoke = 'prefilled'
            artifactProbe = 'prefilled'
            visualSurrogate = 'prefilled'
            traceLog = 'prefilled'
        }
        workflowTiming = @(
            [ordered]@{ step = 'import'; durationMinutes = '8'; outcome = 'blocked by site-only evidence gap' },
            [ordered]@{ step = 'paper'; durationMinutes = '6'; outcome = 'teacher can describe next action' },
            [ordered]@{ step = 'analysis'; durationMinutes = '5'; outcome = 'needs real onsite teacher observation' }
        )
        frictionItems = @(
            [ordered]@{ category = 'copy_confusion'; detail = 'export wording still needs teacher validation'; severity = 'medium' }
        )
        rollbackEvents = @(
            [ordered]@{ trigger = 'onsite evidence absent'; action = 'keep workflow blocked'; recoveryMinutes = '1' }
        )
        summary = [ordered]@{
            teacherUnderstanding = 'proxy_only'
            environmentBlockers = @('printer', 'network', 'domain_permission')
            recommendation = 'do_not_advance_p005'
        }
        signoff = [ordered]@{
            pilotOwner = 'pilot-owner-signed'
            supportOwner = 'support-owner-signed'
            releaseOwner = 'release-owner-signed'
        }
    }
    Write-JsonFile -Path $p004RecordJsonPath -Value $p004Record
    Set-Content -LiteralPath $p004RecordMarkdownPath -Value "# P004 teacher pilot evidence smoke`r`n" -Encoding UTF8

    & (Join-Path $repoRoot 'tools/run-p004-onsite-pilot-round1-evidence-import.ps1') `
        -RecordJsonPath ([System.IO.Path]::GetRelativePath($repoRoot, $p004RecordJsonPath).Replace('\', '/')) `
        -RecordMarkdownPath ([System.IO.Path]::GetRelativePath($repoRoot, $p004RecordMarkdownPath).Replace('\', '/')) `
        -ReportPath $p004ReportPath | Out-Null

    $p004Report = Get-Content -LiteralPath (Resolve-InRepoPath $p004ReportPath) -Raw | ConvertFrom-Json
    Assert-Condition ([string]$p004Report.status -eq 'pass') 'P004 import contract expected status=pass'
    Assert-Condition ([string]$p004Report.taskId -eq 'P004') 'P004 import contract expected taskId=P004'
    Assert-Condition ([string]$p004Report.decision.requested -eq 'keep_blocked') 'P004 import contract expected keep_blocked decision'

    $p005Date = $currentDate
    $p005RecordJsonPath = Join-Path $workRootFullPath 'p005/p005-triage-record.json'
    $p005RecordMarkdownPath = Join-Path $workRootFullPath 'p005/p005-triage-record.md'
    $p005ReportPath = Join-Path $WorkRoot 'p005/p005-validation.json'
    $p005Record = [ordered]@{
        schemaVersion = 'p005-pilot-feedback-triage.v1'
        pilotContext = [ordered]@{
            date = $p005Date
            sourceEvidence = $latestP004ReportPath
            operator = 'triage-operator'
            teacherOrProxy = 'proxy-teacher'
            site = 'school-lab'
        }
        summary = [ordered]@{
            totalFeedbackItems = 2
            keepCount = 1
            modifyCount = 1
            deferCount = 0
            doNotDoCount = 0
            overallTeacherEfficiencyImpact = 'medium'
            topBlockingThemes = @('paper export wording')
        }
        items = @(
            [ordered]@{
                id = 'feedback-001'
                title = '导出文案需要更直白'
                sourceStep = 'paper'
                description = '教师代理在组卷导出步骤停顿，需要更直接的按钮文案。'
                teacherEfficiencyImpact = 'medium'
                frequency = 'high'
                risk = 'low'
                cost = 'low'
                decision = 'modify'
                reason = '影响高频路径，但改动局部可控。'
                owner = 'product-owner'
                targetArtifact = 'docs/28_FunctionScopeReview.md'
                rollbackOrFallback = '保留现有导出路径并允许人工说明'
            },
            [ordered]@{
                id = 'feedback-002'
                title = '安装说明保留为支持文档'
                sourceStep = 'install'
                description = '现场说明页对普通教师不可见，不影响教学主链路。'
                teacherEfficiencyImpact = 'low'
                frequency = 'single'
                risk = 'low'
                cost = 'low'
                decision = 'keep'
                reason = '属于支持层材料，继续保留即可。'
                owner = 'support-owner'
                targetArtifact = 'docs/templates/p001-live-pilot-release-checklist.md'
                rollbackOrFallback = '继续沿用现有支持文档'
            }
        )
        decisionNotes = [ordered]@{
            keep = '继续保留安装支持材料。'
            modify = '收口导出主路径文案。'
            defer = '当前无后置项。'
            doNotDo = '当前无明确不做项。'
        }
        signoff = [ordered]@{
            triageOwner = 'triage-owner-signed'
            productOwnerReview = 'product-owner-signed'
            releaseOwnerReview = 'release-owner-signed'
        }
    }
    Write-JsonFile -Path $p005RecordJsonPath -Value $p005Record
    Set-Content -LiteralPath $p005RecordMarkdownPath -Value "# P005 triage smoke`r`n" -Encoding UTF8

    & (Join-Path $repoRoot 'tools/run-p005-pilot-feedback-triage-import.ps1') `
        -RecordJsonPath ([System.IO.Path]::GetRelativePath($repoRoot, $p005RecordJsonPath).Replace('\', '/')) `
        -RecordMarkdownPath ([System.IO.Path]::GetRelativePath($repoRoot, $p005RecordMarkdownPath).Replace('\', '/')) `
        -ReportPath $p005ReportPath | Out-Null

    $p005Report = Get-Content -LiteralPath (Resolve-InRepoPath $p005ReportPath) -Raw | ConvertFrom-Json
    Assert-Condition ([string]$p005Report.status -eq 'pass') 'P005 import contract expected status=pass'
    Assert-Condition ([string]$p005Report.taskId -eq 'P005') 'P005 import contract expected taskId=P005'
    Assert-Condition ([int]$p005Report.summary.totalFeedbackItems -eq 2) 'P005 import contract expected two feedback items'
    Assert-Condition ([int]$p005Report.summary.keepCount -eq 1) 'P005 import contract expected keepCount=1'
    Assert-Condition ([int]$p005Report.summary.modifyCount -eq 1) 'P005 import contract expected modifyCount=1'

    $p006Date = $currentDate
    $p006RecordJsonPath = Join-Path $workRootFullPath 'p006/p006-release-decision-record.json'
    $p006RecordMarkdownPath = Join-Path $workRootFullPath 'p006/p006-release-decision-record.md'
    $p006ReportPath = Join-Path $WorkRoot 'p006/p006-validation.json'
    $p006Record = [ordered]@{
        schemaVersion = 'p006-release-decision-record.v1'
        decisionContext = [ordered]@{
            date = $p006Date
            decision = 'no_go'
            targetMilestone = 'P001 readiness -> P003/P005/P006 closeout -> v0.1 live pilot release decision'
            releaseCandidate = 'not_created'
            deploymentMode = 'offline_first'
            siteScope = 'school-lab'
        }
        evidenceAnchors = [ordered]@{
            p001ReadinessPack = $latestNs904ReportPath
            p005Triage = $p005ReportPath.Replace('\', '/')
            goNoGoCard = 'docs/109_ReleaseGoNoGoCard.md'
            fullGateEvidence = 'docs/evidence/20260504-h0-full-gate-evidence.md'
            roadmapGuardEvidence = $latestCloseoutGuardPath
            backupEvidence = 'docs/evidence/20260505-o003-recovery-drill-upgrade.md'
            restoreEvidence = 'docs/evidence/20260505-o003-recovery-drill-upgrade.md'
            privacyEvidence = 'docs/evidence/20260505-n001-real-privacy-boundary-admission.md'
            roleAuditEvidence = 'docs/evidence/20260505-o004b-role-audit-closure.md'
        }
        gateReview = [ordered]@{
            buildTestContractHotspot = 'pass'
            backupRestore = 'pass'
            teacherEfficiency = 'blocked'
            privacyAuthorization = 'blocked'
            roleAudit = 'pass'
            onsiteBlockersRemaining = @('P001 not closed', 'P003 not closed')
        }
        exceptions = @(
            [ordered]@{
                id = 'exception-001'
                title = 'not-applicable placeholder'
                owner = 'release-owner'
                expiresAt = '2026-06-30'
                recoveryPlan = 'keep no_go'
                evidenceLink = 'docs/109_ReleaseGoNoGoCard.md'
                acceptedRisk = 'none'
            }
        )
        tagCandidatePlan = [ordered]@{
            createTagCandidate = $false
            tagName = 'not-created'
            rollbackWindow = 'not-entered'
            disableSwitchPlan = 'keep offline-first and operator takeover path'
        }
        signoff = [ordered]@{
            releaseOwner = 'release-owner-signed'
            adminOwner = 'admin-owner-signed'
            dataOwnerRepresentative = 'data-owner-signed'
            pilotSupportOwner = 'pilot-support-owner-signed'
        }
        finalRationale = 'Non-site evidence is ready for review, but P001/P003/P005 remain open, so release stays no_go.'
    }
    Write-JsonFile -Path $p006RecordJsonPath -Value $p006Record
    Set-Content -LiteralPath $p006RecordMarkdownPath -Value "# P006 release decision smoke`r`n" -Encoding UTF8

    & (Join-Path $repoRoot 'tools/run-p006-release-decision-record-import.ps1') `
        -RecordJsonPath ([System.IO.Path]::GetRelativePath($repoRoot, $p006RecordJsonPath).Replace('\', '/')) `
        -RecordMarkdownPath ([System.IO.Path]::GetRelativePath($repoRoot, $p006RecordMarkdownPath).Replace('\', '/')) `
        -ReportPath $p006ReportPath | Out-Null

    $p006Report = Get-Content -LiteralPath (Resolve-InRepoPath $p006ReportPath) -Raw | ConvertFrom-Json
    Assert-Condition ([string]$p006Report.status -eq 'pass') 'P006 import contract expected status=pass'
    Assert-Condition ([string]$p006Report.taskId -eq 'P006') 'P006 import contract expected taskId=P006'
    Assert-Condition ([string]$p006Report.decision -eq 'no_go') 'P006 import contract expected decision=no_go'

    [ordered]@{
        status = 'pass'
        taskId = 'LIVE_PILOT_CLOSEOUT_IMPORT_CONTRACT'
        checkedAt = (Get-Date).ToString('s')
        p001 = [ordered]@{
            reportPath = $p001ReportPath.Replace('\', '/')
            closeP001Allowed = [bool]$p001Report.decision.closeP001Allowed
        }
        p003 = [ordered]@{
            reportPath = $p003ReportPath.Replace('\', '/')
            templatePath = $p003TemplatePath
            decision = [string]$p003Report.decision.requested
        }
        p004 = [ordered]@{
            reportPath = $p004ReportPath.Replace('\', '/')
            templatePath = $p004TemplatePath
            decision = [string]$p004Report.decision.requested
        }
        p005 = [ordered]@{
            reportPath = $p005ReportPath.Replace('\', '/')
            totalFeedbackItems = [int]$p005Report.summary.totalFeedbackItems
        }
        p006 = [ordered]@{
            reportPath = $p006ReportPath.Replace('\', '/')
            decision = [string]$p006Report.decision
        }
        boundary = 'validates the repo-side import/archival scripts for returned P001 evidence, P003 admission cards, P004 teacher pilot evidence, P005 triage, and P006 decision records without changing backlog status or release readiness'
    } | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}

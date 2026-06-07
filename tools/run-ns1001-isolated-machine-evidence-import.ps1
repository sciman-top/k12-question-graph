param(
    [string] $ReturnedPackRoot,
    [string] $EvidenceOutputPath = '',
    [string] $AttachmentOutputRoot = '',
    [string] $ReportPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Resolve-InRepoPath([string] $RelativePath) {
    return Join-Path $repoRoot ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
}

function Resolve-FlexiblePath([string] $PathValue) {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($PathValue)) 'path value must not be empty'
    $fullPath = if ([System.IO.Path]::IsPathRooted($PathValue)) {
        $PathValue
    }
    else {
        Resolve-InRepoPath $PathValue
    }
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing path: $PathValue"
    return (Resolve-Path -LiteralPath $fullPath).Path
}

function Read-Json([string] $Path) {
    $fullPath = Resolve-FlexiblePath $Path
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Require-Text([object] $Value, [string] $Label) {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$Value)) "$Label must not be empty"
}

function Validate-NaBlock([object] $NaBlock, [string] $Label) {
    if ([bool]$NaBlock.used) {
        foreach ($field in @('reason', 'alternativeVerification', 'evidenceLink', 'expiresAt')) {
            Require-Text $NaBlock.$field "$Label.$field"
        }
    }
}

function Validate-CommandEntries([object[]] $Commands, [string] $Label) {
    Assert-Condition ($Commands.Count -ge 1) "$Label must contain at least one command entry"
    foreach ($commandEntry in $Commands) {
        Require-Text $commandEntry.command "$Label.command"
        Require-Text $commandEntry.exitCode "$Label.exitCode"
        Require-Text $commandEntry.keyOutput "$Label.keyOutput"
    }
}

function Get-SectionBlockers([string] $SectionName, [string] $Status) {
    if ($Status -eq 'pass') {
        return @()
    }
    return @("$SectionName status is $Status")
}

Push-Location $repoRoot
try {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($ReturnedPackRoot)) 'ReturnedPackRoot is required'
    $returnedPackRootFullPath = Resolve-FlexiblePath $ReturnedPackRoot
    Assert-Condition (Test-Path -LiteralPath $returnedPackRootFullPath -PathType Container) 'ReturnedPackRoot must be a directory'

    $returnEvidenceJsonFullPath = Join-Path $returnedPackRootFullPath 'return/p001-isolated-machine-evidence.json'
    $returnEvidenceMarkdownFullPath = Join-Path $returnedPackRootFullPath 'return/p001-isolated-machine-evidence.md'
    $returnAttachmentsRootFullPath = Join-Path $returnedPackRootFullPath 'return/attachments'

    foreach ($requiredFile in @($returnEvidenceJsonFullPath, $returnEvidenceMarkdownFullPath)) {
        Assert-Condition (Test-Path -LiteralPath $requiredFile -PathType Leaf) "missing returned evidence file: $requiredFile"
    }
    Assert-Condition (Test-Path -LiteralPath $returnAttachmentsRootFullPath -PathType Container) "missing returned attachments root: $returnAttachmentsRootFullPath"

    $returnedEvidence = Get-Content -LiteralPath $returnEvidenceJsonFullPath -Raw | ConvertFrom-Json
    Assert-Condition ($returnedEvidence.schemaVersion -eq 'p001-isolated-machine-evidence.v1') 'unexpected returned evidence schemaVersion'

    foreach ($field in @(
        'date',
        'machineId',
        'location',
        'operator',
        'supportOwner',
        'packageVersion',
        'rollbackOwner'
    )) {
        Require-Text $returnedEvidence.execution.$field "execution.$field"
    }

    $executionDateText = [string]$returnedEvidence.execution.date
    $datePattern = '^\d{4}-\d{2}-\d{2}$'
    Assert-Condition ($executionDateText -match $datePattern) 'execution.date must use YYYY-MM-DD'
    $evidenceDate = [datetime]::ParseExact($executionDateText, 'yyyy-MM-dd', $null)
    $dateStamp = $evidenceDate.ToString('yyyyMMdd')

    $p001Report = Read-Json ([string]$returnedEvidence.anchors.p001PreflightReport)
    $ns904Report = Read-Json ([string]$returnedEvidence.anchors.ns904ReadinessPack)
    $ns1308Report = Read-Json ([string]$returnedEvidence.anchors.ns1308ReleasePack)
    $real012Report = Read-Json ([string]$returnedEvidence.anchors.real012QualityReport)

    Assert-Condition ($p001Report.status -eq 'pass') 'anchored P001 report must pass'
    Assert-Condition ([bool]$p001Report.readyForIsolatedMachineRun) 'anchored P001 report must still be readyForIsolatedMachineRun=true'
    Assert-Condition (-not [bool]$p001Report.p001CanClose) 'anchored P001 report must remain open before import decision'
    Assert-Condition ($ns904Report.status -eq 'pass') 'anchored NS904 report must pass'
    Assert-Condition (-not [bool]$ns904Report.releaseReady) 'anchored NS904 report must keep releaseReady=false'
    Assert-Condition (-not [bool]$ns904Report.nonSiteValidated) 'anchored NS904 report must keep nonSiteValidated=false'
    Assert-Condition ($ns1308Report.status -eq 'pass') 'anchored NS1308 report must pass'
    Assert-Condition (-not [bool]$ns1308Report.productionEligible) 'anchored NS1308 report must keep productionEligible=false'
    Assert-Condition ($real012Report.status -eq 'pass') 'anchored REAL012 report must pass'
    Assert-Condition ($real012Report.real005ClosureStatus -eq 'not_closed') 'anchored REAL012 report must keep REAL005 not_closed'

    $allowedStatuses = @('pass', 'blocked', 'fail', 'na')
    foreach ($pair in @(
        @{ name = 'installInit'; value = [string]$returnedEvidence.installInit.status },
        @{ name = 'backupRestore'; value = [string]$returnedEvidence.backupRestore.status },
        @{ name = 'roleAudit'; value = [string]$returnedEvidence.roleAudit.status },
        @{ name = 'teacherEntry.import'; value = [string]$returnedEvidence.teacherEntrySmokes.import.status },
        @{ name = 'teacherEntry.paperAssembly'; value = [string]$returnedEvidence.teacherEntrySmokes.paperAssembly.status },
        @{ name = 'teacherEntry.scoreImport'; value = [string]$returnedEvidence.teacherEntrySmokes.scoreImport.status },
        @{ name = 'teacherEntry.analysis'; value = [string]$returnedEvidence.teacherEntrySmokes.analysis.status }
    )) {
        Assert-Condition ($allowedStatuses -contains $pair.value) "$($pair.name) status must be one of: $($allowedStatuses -join ', ')"
    }

    Validate-NaBlock -NaBlock $returnedEvidence.na.platformNa -Label 'platformNa'
    Validate-NaBlock -NaBlock $returnedEvidence.na.gateNa -Label 'gateNa'

    Require-Text $returnedEvidence.installInit.installDir 'installInit.installDir'
    Require-Text $returnedEvidence.installInit.dataDir 'installInit.dataDir'
    Require-Text $returnedEvidence.installInit.backupDir 'installInit.backupDir'
    Require-Text $returnedEvidence.backupRestore.backupManifestPath 'backupRestore.backupManifestPath'
    Require-Text $returnedEvidence.backupRestore.verifySummary 'backupRestore.verifySummary'
    Require-Text $returnedEvidence.backupRestore.restoreSummary 'backupRestore.restoreSummary'
    Require-Text $returnedEvidence.backupRestore.healthReadinessSummary 'backupRestore.healthReadinessSummary'
    Require-Text $returnedEvidence.backupRestore.rollbackCommand 'backupRestore.rollbackCommand'
    Require-Text $returnedEvidence.roleAudit.teacherGroupLeadAdminSeparation 'roleAudit.teacherGroupLeadAdminSeparation'
    Require-Text $returnedEvidence.roleAudit.adminFailClosed 'roleAudit.adminFailClosed'
    Require-Text $returnedEvidence.roleAudit.internalAiFailClosed 'roleAudit.internalAiFailClosed'
    Require-Text $returnedEvidence.roleAudit.domainPermissionSummary 'roleAudit.domainPermissionSummary'
    Require-Text $returnedEvidence.siteSpecific.printerSummary 'siteSpecific.printerSummary'
    Require-Text $returnedEvidence.siteSpecific.networkSummary 'siteSpecific.networkSummary'
    Require-Text $returnedEvidence.siteSpecific.domainPermissionSummary 'siteSpecific.domainPermissionSummary'

    Validate-CommandEntries -Commands @($returnedEvidence.installInit.commands) -Label 'installInit.commands'
    Validate-CommandEntries -Commands @($returnedEvidence.backupRestore.commands) -Label 'backupRestore.commands'
    Validate-CommandEntries -Commands @($returnedEvidence.roleAudit.commands) -Label 'roleAudit.commands'

    foreach ($entryArea in @(
        @{ name = 'import'; section = $returnedEvidence.teacherEntrySmokes.import },
        @{ name = 'paperAssembly'; section = $returnedEvidence.teacherEntrySmokes.paperAssembly },
        @{ name = 'scoreImport'; section = $returnedEvidence.teacherEntrySmokes.scoreImport },
        @{ name = 'analysis'; section = $returnedEvidence.teacherEntrySmokes.analysis }
    )) {
        Require-Text $entryArea.section.durationMinutes "teacherEntrySmokes.$($entryArea.name).durationMinutes"
        Require-Text $entryArea.section.rollbackAction "teacherEntrySmokes.$($entryArea.name).rollbackAction"
    }

    $attachmentFiles = @(
        Get-ChildItem -LiteralPath $returnAttachmentsRootFullPath -Recurse -File |
            Where-Object { $_.Name -ne 'README.md' }
    )
    Assert-Condition ($attachmentFiles.Count -ge 1) 'returned attachments must include at least one real file'

    if ([string]::IsNullOrWhiteSpace($EvidenceOutputPath)) {
        $EvidenceOutputPath = "docs/evidence/{0}-p001-isolated-machine.md" -f $dateStamp
    }
    if ([string]::IsNullOrWhiteSpace($AttachmentOutputRoot)) {
        $AttachmentOutputRoot = "docs/evidence/attachments/{0}-p001-isolated-machine" -f $dateStamp
    }
    if ([string]::IsNullOrWhiteSpace($ReportPath)) {
        $ReportPath = "docs/evidence/{0}-ns1001-isolated-machine-validation.json" -f $dateStamp
    }

    $evidenceOutputFullPath = Resolve-InRepoPath $EvidenceOutputPath
    $attachmentOutputRootFullPath = Resolve-InRepoPath $AttachmentOutputRoot
    $reportOutputFullPath = Resolve-InRepoPath $ReportPath

    New-Item -ItemType Directory -Path (Split-Path -Parent $evidenceOutputFullPath) -Force | Out-Null
    New-Item -ItemType Directory -Path $attachmentOutputRootFullPath -Force | Out-Null
    Set-Content -LiteralPath $evidenceOutputFullPath -Value (Get-Content -LiteralPath $returnEvidenceMarkdownFullPath -Raw) -Encoding UTF8

    $copiedAttachmentRelativePaths = New-Object System.Collections.Generic.List[string]
    foreach ($file in $attachmentFiles) {
        $relativePath = [System.IO.Path]::GetRelativePath($returnAttachmentsRootFullPath, $file.FullName)
        $targetFullPath = Join-Path $attachmentOutputRootFullPath $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $targetFullPath) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $targetFullPath -Force
        $copiedAttachmentRelativePaths.Add(([System.IO.Path]::GetRelativePath($repoRoot, $targetFullPath)).Replace('\', '/'))
    }

    $rawJsonTargetFullPath = Join-Path $attachmentOutputRootFullPath 'p001-isolated-machine-evidence.json'
    Copy-Item -LiteralPath $returnEvidenceJsonFullPath -Destination $rawJsonTargetFullPath -Force
    $rawJsonRelativePath = ([System.IO.Path]::GetRelativePath($repoRoot, $rawJsonTargetFullPath)).Replace('\', '/')

    $blockers = New-Object System.Collections.Generic.List[string]
    foreach ($blocker in (Get-SectionBlockers -SectionName 'installInit' -Status ([string]$returnedEvidence.installInit.status))) { $blockers.Add($blocker) }
    foreach ($blocker in (Get-SectionBlockers -SectionName 'backupRestore' -Status ([string]$returnedEvidence.backupRestore.status))) { $blockers.Add($blocker) }
    foreach ($blocker in (Get-SectionBlockers -SectionName 'roleAudit' -Status ([string]$returnedEvidence.roleAudit.status))) { $blockers.Add($blocker) }
    foreach ($entryName in @('import', 'paperAssembly', 'scoreImport', 'analysis')) {
        $entryStatus = [string]$returnedEvidence.teacherEntrySmokes.$entryName.status
        foreach ($blocker in (Get-SectionBlockers -SectionName "teacherEntry.$entryName" -Status $entryStatus)) { $blockers.Add($blocker) }
    }
    foreach ($openBlocker in @($returnedEvidence.siteSpecific.openBlockers | ForEach-Object { [string]$_ })) {
        if (-not [string]::IsNullOrWhiteSpace($openBlocker)) {
            $blockers.Add("siteSpecific blocker: $openBlocker")
        }
    }
    if ([bool]$returnedEvidence.na.platformNa.used) {
        $blockers.Add('platform_na recorded')
    }
    if ([bool]$returnedEvidence.na.gateNa.used) {
        $blockers.Add('gate_na recorded')
    }
    if (-not [bool]$returnedEvidence.signoff.rollbackConfirmed) {
        $blockers.Add('rollback not confirmed by operator')
    }
    foreach ($field in @('operatorSignoff', 'supportOwnerSignoff', 'releaseOwnerReview')) {
        if ([string]::IsNullOrWhiteSpace([string]$returnedEvidence.signoff.$field)) {
            $blockers.Add("missing signoff field: $field")
        }
    }

    $decision = [string]$returnedEvidence.signoff.decision
    Assert-Condition (@('continue_p002', 'keep_blocked') -contains $decision) 'signoff.decision must be continue_p002 or keep_blocked'
    if ($decision -eq 'keep_blocked') {
        $blockers.Add('operator decision keeps P001 blocked')
    }

    $closeP001Allowed = ($blockers.Count -eq 0)

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS1001'
        checkedAt = (Get-Date).ToString('s')
        mode = 'isolated_machine_evidence_import'
        productionEligible = $false
        returnedPackRoot = $ReturnedPackRoot.Replace('\', '/')
        importedEvidence = [ordered]@{
            markdown = $EvidenceOutputPath.Replace('\', '/')
            rawJson = $rawJsonRelativePath
            attachments = @($copiedAttachmentRelativePaths)
        }
        anchors = [ordered]@{
            p001 = [string]$returnedEvidence.anchors.p001PreflightReport
            ns904 = [string]$returnedEvidence.anchors.ns904ReadinessPack
            ns1308 = [string]$returnedEvidence.anchors.ns1308ReleasePack
            real012 = [string]$returnedEvidence.anchors.real012QualityReport
        }
        importedExecution = [ordered]@{
            date = [string]$returnedEvidence.execution.date
            machineId = [string]$returnedEvidence.execution.machineId
            location = [string]$returnedEvidence.execution.location
            operator = [string]$returnedEvidence.execution.operator
            packageVersion = [string]$returnedEvidence.execution.packageVersion
        }
        sectionStatus = [ordered]@{
            installInit = [string]$returnedEvidence.installInit.status
            backupRestore = [string]$returnedEvidence.backupRestore.status
            roleAudit = [string]$returnedEvidence.roleAudit.status
            import = [string]$returnedEvidence.teacherEntrySmokes.import.status
            paperAssembly = [string]$returnedEvidence.teacherEntrySmokes.paperAssembly.status
            scoreImport = [string]$returnedEvidence.teacherEntrySmokes.scoreImport.status
            analysis = [string]$returnedEvidence.teacherEntrySmokes.analysis.status
        }
        decision = [ordered]@{
            requested = $decision
            closeP001Allowed = $closeP001Allowed
            p002CanAdvance = $closeP001Allowed
            blockers = @($blockers)
        }
        acceptance = [ordered]@{
            anchorsValidated = $true
            requiredFieldsPresent = $true
            markdownImported = $true
            rawJsonImported = $true
            attachmentCount = $copiedAttachmentRelativePaths.Count
            operatorRollbackConfirmed = [bool]$returnedEvidence.signoff.rollbackConfirmed
            platformNaUsed = [bool]$returnedEvidence.na.platformNa.used
            gateNaUsed = [bool]$returnedEvidence.na.gateNa.used
        }
        verification = [ordered]@{
            build = 'gate_na: NS1001 import validates returned evidence only'
            test = 'returned markdown/json/attachment validation plus P001/NS904/NS1308/REAL012 anchor cross-check'
            contractInvariant = 'real isolated-machine evidence may advance past P001 only when install, backup/restore, role audit, four entries, site-specific checks, and signoff all pass without unresolved NA'
            hotspot = 'gate_na: import does not re-execute the isolated-machine workflow; it validates returned artifacts and keeps backlog status untouched'
        }
        boundary = 'NS1001 import validates and archives returned isolated-machine evidence. It does not automatically update tasks/backlog.csv, does not close P001 by itself, and does not alter REAL005 semantics.'
        next = if ($closeP001Allowed) { 'Evidence is structurally complete; the next manual repo step may review whether P001 can move to 已完成 and P002 can begin.' } else { 'Keep P001 blocked, review blockers, and rerun the isolated-machine rehearsal or补齐现场签收后再导入。' }
        rollback = "Remove-Item -LiteralPath '$evidenceOutputFullPath' -Force; Remove-Item -LiteralPath '$attachmentOutputRootFullPath' -Recurse -Force; Remove-Item -LiteralPath '$reportOutputFullPath' -Force"
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $reportOutputFullPath) -Force | Out-Null
    Set-Content -LiteralPath $reportOutputFullPath -Value ($report | ConvertTo-Json -Depth 12) -Encoding UTF8
    $report | ConvertTo-Json -Depth 12
}
finally {
    Pop-Location
}

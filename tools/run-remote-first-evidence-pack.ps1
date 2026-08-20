param(
    [ValidateSet('DryRun', 'Collect')]
    [string] $Mode = 'DryRun',
    [string] $OutputPath = 'tmp/verification/remote-first/current/remote-first-evidence-pack.json',
    [string] $EvidenceIndexPath = 'docs/evidence/index.json',
    [string] $VerificationSummaryPath = 'tmp/verification/current/verification-summary.json',
    [string] $RoadmapGuardReportPath = 'tmp/verification/roadmap.json',
    [string] $ReleaseCardPath = 'docs/109_ReleaseGoNoGoCard.md',
    [string] $HostCapabilityReportPath = 'docs/evidence/host-capability-diagnostic-report.json',
    [string] $WorkerProfileReportPath = 'docs/evidence/worker-profile-diagnostic-report.json',
    [string] $TechnologyRefreshReportPath = 'docs/evidence/technology-refresh-report.json',
    [string] $VisualSurrogateReportPath = 'docs/evidence/20260528-ns906-visual-surrogate-review-report.json',
    [string] $ArtifactReportPath = 'docs/evidence/20260731-real005c1-word-pdf-artifact-report.json',
    [string] $RemoteTargetEvidencePath = '',
    [string] $TeacherEvidencePath = '',
    [string] $AdmissionCardPath = '',
    [string] $FeedbackTriagePath = '',
    [string] $ReleaseDecisionPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$automatedEvidence = New-Object System.Collections.Generic.List[object]
$remoteEnvironmentEvidence = New-Object System.Collections.Generic.List[object]
$humanSuppliedEvidence = New-Object System.Collections.Generic.List[object]
$automationBlockedReasons = New-Object System.Collections.Generic.List[string]
$commandReceipts = New-Object System.Collections.Generic.List[object]

function Resolve-InputPath([string] $Path) {
    if ([System.IO.Path]::IsPathFullyQualified($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
}

function Get-DisplayPath([string] $FullPath) {
    $relative = [System.IO.Path]::GetRelativePath($repoRoot, $FullPath).Replace('\', '/')
    if (-not $relative.StartsWith('../', [System.StringComparison]::Ordinal)) {
        return $relative
    }
    return $FullPath
}

function Get-PropertyValue([object] $Object, [string] $Name) {
    if ($null -eq $Object -or $Object.PSObject.Properties.Name -notcontains $Name) {
        return $null
    }
    return $Object.$Name
}

function Add-AutomationBlock([string] $Reason) {
    if (-not $automationBlockedReasons.Contains($Reason)) {
        $automationBlockedReasons.Add($Reason)
    }
}

function Read-JsonEvidence([string] $Id, [string] $Path, [string] $ClaimBoundary, [string] $Category = 'automated') {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        Add-AutomationBlock "required_evidence_path_blank:$Id"
        return $null
    }

    $fullPath = Resolve-InputPath $Path
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        Add-AutomationBlock "required_evidence_missing:${Id}:$Path"
        return $null
    }

    try {
        $data = Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Add-AutomationBlock "required_evidence_invalid_json:${Id}:$Path"
        return $null
    }

    $status = Get-PropertyValue $data 'status'
    $checkedAt = Get-PropertyValue $data 'checkedAt'
    $entry = [pscustomobject][ordered]@{
        id = $Id
        path = Get-DisplayPath $fullPath
        status = if ($null -eq $status) { 'available' } else { [string] $status }
        checkedAt = if ($null -eq $checkedAt) { $null } else { [string] $checkedAt }
        sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
        claimBoundary = $ClaimBoundary
    }

    switch ($Category) {
        'remote' { $remoteEnvironmentEvidence.Add($entry) }
        'human' { $humanSuppliedEvidence.Add($entry) }
        default { $automatedEvidence.Add($entry) }
    }
    return [pscustomobject]@{ data = $data; entry = $entry; fullPath = $fullPath }
}

function Require-True([bool] $Condition, [string] $Reason) {
    if (-not $Condition) { Add-AutomationBlock $Reason }
}

function Invoke-GitReceipt([string] $CommandText, [string[]] $Arguments) {
    $startedAt = (Get-Date).ToString('o')
    $output = @(& git -C $repoRoot @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $keyOutput = ($output | Out-String).Trim()
    $commandReceipts.Add([pscustomobject][ordered]@{
        command = $CommandText
        exitCode = $exitCode
        keyOutput = $keyOutput
        timestamp = $startedAt
    })
    if ($exitCode -ne 0) {
        Add-AutomationBlock "git_probe_failed:$CommandText"
    }
    return $keyOutput
}

$headCommit = Invoke-GitReceipt 'git rev-parse HEAD' @('rev-parse', 'HEAD')
$headCommittedAtText = Invoke-GitReceipt 'git show -s --format=%cI HEAD' @('show', '-s', '--format=%cI', 'HEAD')
$worktreeStatus = Invoke-GitReceipt 'git status --porcelain=v1 --untracked-files=all' @('status', '--porcelain=v1', '--untracked-files=all')
Require-True ([string]::IsNullOrWhiteSpace($worktreeStatus)) 'working_tree_not_clean'

$indexEvidence = Read-JsonEvidence 'evidence-index' $EvidenceIndexPath 'Curated current-evidence routing only; indexed receipts retain their own claim boundaries.'
$indexById = @{}
if ($null -ne $indexEvidence) {
    Require-True ([int](Get-PropertyValue $indexEvidence.data 'schemaVersion') -eq 2) 'evidence_index_schema_mismatch'
    foreach ($entry in @($indexEvidence.data.entries)) {
        $indexById[[string] $entry.id] = $entry
    }
}

$currentEvidence = @{}
foreach ($requiredId in @('reference-basis', 'real005-closure-standard', 'p001-readiness', 'p006-release-decision', 'live-pilot-closeout-plan')) {
    if (-not $indexById.ContainsKey($requiredId)) {
        Add-AutomationBlock "current_evidence_index_entry_missing:$requiredId"
        continue
    }
    $indexEntry = $indexById[$requiredId]
    Require-True ([string] $indexEntry.state -eq 'current') "current_evidence_entry_not_current:$requiredId"
    $currentEvidence[$requiredId] = Read-JsonEvidence $requiredId ([string] $indexEntry.currentPath) ([string] $indexEntry.claimBoundary)
}

$verification = Read-JsonEvidence 'release-verification' $VerificationSummaryPath 'Repo-side Release verification only; it does not prove target-site or live acceptance.'
$roadmap = Read-JsonEvidence 'roadmap-guard' $RoadmapGuardReportPath 'Backlog structure and closeout truth only; historical completed-task evidence is not re-audited.'
$releaseCardFullPath = Resolve-InputPath $ReleaseCardPath
$releaseCardText = $null
if (Test-Path -LiteralPath $releaseCardFullPath -PathType Leaf) {
    $releaseCardText = Get-Content -LiteralPath $releaseCardFullPath -Raw -Encoding UTF8
    $automatedEvidence.Add([pscustomobject][ordered]@{
        id = 'release-go-no-go-card'
        path = Get-DisplayPath $releaseCardFullPath
        status = if ($releaseCardText -match '(?m)^\*\*No-Go\*\*') { 'No-Go' } else { 'review_required' }
        checkedAt = $null
        sha256 = (Get-FileHash -LiteralPath $releaseCardFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
        claimBoundary = 'Release card text only; a signed decision is still required for Go.'
    })
}
else {
    Add-AutomationBlock "required_evidence_missing:release-go-no-go-card:$ReleaseCardPath"
}
$hostCapability = Read-JsonEvidence 'host-capability' $HostCapabilityReportPath 'Read-only diagnostic for the machine named in the receipt; not proof of the school target host.'
$worker = Read-JsonEvidence 'worker-profile' $WorkerProfileReportPath 'Read-only worker routing diagnostic; no dependency installation or production route change.'
$technology = Read-JsonEvidence 'technology-refresh' $TechnologyRefreshReportPath 'Report-only candidate scan; no install, download, or default-route change.'
$visual = Read-JsonEvidence 'visual-surrogate' $VisualSurrogateReportPath 'Automated screenshot, layout, artifact, and workflow checks; not teacher understanding or target-site acceptance.'
$artifact = Read-JsonEvidence 'word-pdf-artifact' $ArtifactReportPath 'Word/PDF structure and hash evidence for a review candidate; production eligibility and real printing remain separate.'

if ($null -ne $verification) {
    Require-True ([string] $verification.data.status -eq 'pass') 'release_verification_not_pass'
    Require-True ([string] $verification.data.profile -eq 'Release') 'verification_profile_not_release'
    Require-True (-not [bool] $verification.data.dryRun) 'release_verification_is_dry_run'
    Require-True ([bool] $verification.data.releaseCoreIncluded) 'release_core_not_included'
    Require-True ([bool] $verification.data.worktreeUnchanged) 'release_receipt_worktree_changed'
    Require-True ([bool] $verification.data.processesUnchanged) 'release_receipt_processes_changed'
    try {
        $headCommittedAt = [DateTimeOffset]::Parse($headCommittedAtText)
        $verificationWrittenAt = [DateTimeOffset](Get-Item -LiteralPath $verification.fullPath).LastWriteTimeUtc
        Require-True ($verificationWrittenAt -ge $headCommittedAt.ToUniversalTime()) 'release_receipt_predates_current_commit'
    }
    catch {
        Add-AutomationBlock 'release_receipt_commit_time_comparison_failed'
    }
}

if ($currentEvidence.ContainsKey('real005-closure-standard') -and $null -ne $currentEvidence['real005-closure-standard']) {
    $real005 = $currentEvidence['real005-closure-standard'].data
    Require-True ([string] $real005.status -eq 'pass') 'real005_receipt_not_pass'
    Require-True ([string] $real005.closureStatus -eq 'not_closed') 'real005_closure_boundary_drift'
    Require-True (-not [bool] $real005.fullClosureAllowed) 'real005_full_closure_must_remain_disallowed'
}
if ($currentEvidence.ContainsKey('p001-readiness') -and $null -ne $currentEvidence['p001-readiness']) {
    $p001 = $currentEvidence['p001-readiness'].data
    Require-True ([string] $p001.status -eq 'pass') 'p001_readiness_not_pass'
    Require-True ([bool] $p001.readyForIsolatedMachineRun) 'p001_not_ready_for_target_machine_run'
    Require-True (-not [bool] $p001.p001CanClose) 'p001_preflight_must_not_auto_close_task'
}
if ($currentEvidence.ContainsKey('p006-release-decision') -and $null -ne $currentEvidence['p006-release-decision']) {
    $p006 = $currentEvidence['p006-release-decision'].data
    Require-True (-not [bool] $p006.closeTaskAllowed) 'p006_preflight_must_not_allow_auto_close'
}
if ($currentEvidence.ContainsKey('live-pilot-closeout-plan') -and $null -ne $currentEvidence['live-pilot-closeout-plan']) {
    $live = $currentEvidence['live-pilot-closeout-plan'].data
    Require-True ([string] $live.status -eq 'pass') 'live_closeout_guard_not_pass'
    Require-True ([string] $live.real005ClosureStatus -eq 'not_closed') 'live_closeout_real005_boundary_drift'
    Require-True (-not [bool] $live.fullClosureAllowed) 'live_closeout_full_closure_must_remain_disallowed'
    Require-True ($releaseCardText -match '(?m)^\*\*No-Go\*\*') 'release_card_must_remain_no_go'
}
if ($null -ne $roadmap) {
    Require-True ([string] $roadmap.data.status -eq 'pass') 'roadmap_guard_not_pass'
    Require-True ([string] $roadmap.data.closeout.real005ClosureStatus -eq 'not_closed') 'roadmap_real005_boundary_drift'
    Require-True ([string] $roadmap.data.closeout.releaseDecision -eq 'No-Go') 'roadmap_release_decision_must_remain_no_go'
    Require-True ((@($roadmap.data.closeout.open) -join ',') -eq 'P001,P002,P003,P004,P005,P006') 'p001_p006_open_sequence_drift'
}
if ($null -ne $hostCapability) {
    Require-True ([string] $hostCapability.data.schemaVersion -eq 'host-capability-diagnostic.v1') 'host_capability_schema_mismatch'
    Require-True ([string] $hostCapability.data.mode -eq 'read_only') 'host_capability_not_read_only'
    Require-True ([bool] $hostCapability.data.guardrail.noInstallPerformed) 'host_capability_install_side_effect_detected'
}
if ($null -ne $worker) {
    Require-True ([string] $worker.data.mode -eq 'read_only') 'worker_profile_not_read_only'
    Require-True ([bool] $worker.data.guardrail.noInstallPerformed) 'worker_profile_install_side_effect_detected'
}
if ($null -ne $technology) {
    Require-True ([string] $technology.data.status -eq 'pass') 'technology_refresh_not_pass'
    Require-True ([string] $technology.data.mode -eq 'report_only') 'technology_refresh_not_report_only'
    Require-True ([bool] $technology.data.boundaries.noProductionWrite) 'technology_refresh_production_write_detected'
}
if ($null -ne $visual) {
    Require-True ([string] $visual.data.status -eq 'pass') 'visual_surrogate_not_pass'
    Require-True (-not [bool] $visual.data.productionEligible) 'visual_surrogate_must_not_claim_production_eligibility'
}
if ($null -ne $artifact) {
    Require-True ([string] $artifact.data.status -eq 'pass') 'artifact_report_not_pass'
    Require-True (-not [bool] $artifact.data.productionEligible) 'artifact_report_must_not_claim_production_eligibility'
}

$optionalEvidence = @(
    [pscustomobject]@{ id = 'remote-target-environment'; path = $RemoteTargetEvidencePath; category = 'remote'; boundary = 'Target-host facts supplied for review; presence alone does not close P001.' },
    [pscustomobject]@{ id = 'teacher-human-evidence'; path = $TeacherEvidencePath; category = 'human'; boundary = 'Teacher-authored understanding, timing, friction, and preference evidence; automation does not reinterpret it as accepted.' },
    [pscustomobject]@{ id = 'p003-admission-card'; path = $AdmissionCardPath; category = 'human'; boundary = 'Authorization and accountable-party confirmation supplied for review; AI cannot sign.' },
    [pscustomobject]@{ id = 'p005-feedback-triage'; path = $FeedbackTriagePath; category = 'human'; boundary = 'Candidate triage supplied for product-owner review; it does not update backlog automatically.' },
    [pscustomobject]@{ id = 'p006-release-decision'; path = $ReleaseDecisionPath; category = 'human'; boundary = 'Signed decision supplied for formal validation; this collector never changes No-Go or creates a tag.' }
)
foreach ($candidate in $optionalEvidence) {
    if (-not [string]::IsNullOrWhiteSpace([string] $candidate.path)) {
        Read-JsonEvidence ([string] $candidate.id) ([string] $candidate.path) ([string] $candidate.boundary) ([string] $candidate.category) | Out-Null
    }
}

$humanRequiredEvidence = @(
    [pscustomobject]@{ stage = 'P001'; evidence = '目标机安装、health/readiness、隔离备份恢复、角色/域权限和文件目录访问事实'; remoteAllowed = $true; onsiteOnlyWhen = '远程目标机执行不可达或环境异常无法复现' },
    [pscustomobject]@{ stage = 'P001'; evidence = '学校网络探针；若发布承诺真实纸张交付则补真实打印，否则可用等价打印预检'; remoteAllowed = $true; onsiteOnlyWhen = '网络、打印驱动或物理设备异常' },
    [pscustomobject]@{ stage = 'P002/P004'; evidence = '真实教师或明确标记的 teacher_proxy 对术语、理解、困惑、偏好、实际耗时和接管点的原始记录'; remoteAllowed = $true; onsiteOnlyWhen = '无法远程观察或目标环境问题影响结果' },
    [pscustomobject]@{ stage = 'P003'; evidence = '数据授权范围、有效期、数据责任方身份，以及支持/回滚责任人的电子确认'; remoteAllowed = $true; onsiteOnlyWhen = '责任边界或授权对象不清' },
    [pscustomobject]@{ stage = 'P005'; evidence = '对影响范围、成本、风险和优先级的产品负责人裁决'; remoteAllowed = $true; onsiteOnlyWhen = '不要求现场，可异步电子复核' },
    [pscustomobject]@{ stage = 'P006'; evidence = 'Go 或 named exception 的发布、管理员、数据、试点支持责任人电子签收'; remoteAllowed = $true; onsiteOnlyWhen = '不要求同场或纸质签字，但必须可验证身份、时间、commit 和证据哈希' }
)

$externalBlockedReasons = @(
    'P001_target_environment_evidence_not_formally_accepted',
    'P002_P004_teacher_authored_understanding_and_timing_not_formally_accepted',
    'P003_data_authorization_and_accountable_signoff_not_formally_accepted',
    'P005_product_scope_risk_cost_decision_not_formally_accepted',
    'P006_signed_release_decision_not_recorded'
)
$status = if ($automationBlockedReasons.Count -eq 0) { 'pass' } else { 'blocked' }
$report = [ordered]@{
    schemaVersion = 'remote-first-evidence-pack.v1'
    status = $status
    mode = $Mode
    collectedAt = (Get-Date).ToString('o')
    repository = [ordered]@{
        root = $repoRoot
        commit = $headCommit
        worktreeClean = [string]::IsNullOrWhiteSpace($worktreeStatus)
    }
    automatedEvidenceComplete = $automationBlockedReasons.Count -eq 0
    automatedEvidence = $automatedEvidence.ToArray()
    remoteEnvironmentEvidence = $remoteEnvironmentEvidence.ToArray()
    humanSuppliedEvidence = $humanSuppliedEvidence.ToArray()
    humanRequiredEvidence = $humanRequiredEvidence
    automationBlockedReasons = $automationBlockedReasons.ToArray()
    externalBlockedReasons = $externalBlockedReasons
    blockedReasons = @($automationBlockedReasons.ToArray()) + $externalBlockedReasons
    signoffRequired = @('P003:data_owner+support_owner+release_owner', 'P005:product_owner', 'P006:release_owner+admin_owner+data_owner_representative+pilot_support_owner')
    canAdvanceToNextSlice = $false
    advanceRule = 'This pack prepares and hashes evidence only. The stage-specific contract plus accountable human confirmations must close before backlog, release card, active state, or tag changes.'
    commandReceipts = $commandReceipts.ToArray()
    sideEffectBoundary = 'DryRun writes nothing. Collect writes only OutputPath. No DB, FileStore, process, backlog, active-state, release-card, signoff, tag, or external-service write is performed.'
    truthBoundary = [ordered]@{
        real005ClosureStatus = 'not_closed'
        fullClosureAllowed = $false
        p001ThroughP006 = '待办'
        releaseDecision = 'No-Go'
        liveAccepted = $false
    }
}
$json = $report | ConvertTo-Json -Depth 10
if ($Mode -eq 'Collect') {
    $outputFullPath = Resolve-InputPath $OutputPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $outputFullPath) -Force | Out-Null
    $json | Set-Content -LiteralPath $outputFullPath -Encoding UTF8
}
$json

if ($status -ne 'pass') {
    throw "remote-first evidence pack blocked: $($automationBlockedReasons -join ', ')"
}

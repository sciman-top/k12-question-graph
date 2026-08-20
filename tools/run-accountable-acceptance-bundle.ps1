param(
    [ValidateSet('DryRun', 'Collect')]
    [string] $Mode = 'DryRun',
    [Parameter(Mandatory = $true)]
    [string] $BundlePath,
    [string] $OutputPath = 'tmp/verification/accountable-acceptance/current/accountable-acceptance-report.json',
    [string] $ExpectedCommit = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$blockingReasons = New-Object System.Collections.Generic.List[string]

$stageContracts = [ordered]@{
    P001 = [ordered]@{
        roles = @('pilot_support_owner', 'admin_owner')
        acceptedDecisions = @('accept_target_evidence')
    }
    P002_P004 = [ordered]@{
        roles = @('teacher_or_proxy', 'pilot_support_owner')
        acceptedDecisions = @('accept_teacher_evidence')
    }
    P003 = [ordered]@{
        roles = @('data_owner_representative', 'pilot_support_owner', 'release_owner')
        acceptedDecisions = @('authorize')
    }
    P005 = [ordered]@{
        roles = @('product_owner')
        acceptedDecisions = @('approve_triage')
    }
    P006 = [ordered]@{
        roles = @('release_owner', 'admin_owner', 'data_owner_representative', 'pilot_support_owner')
        acceptedDecisions = @('go', 'no_go', 'go_with_named_exceptions')
    }
}
$allowedVerificationMethods = @('school_sso', 'verified_email', 'digital_signature', 'identity_provider', 'other_accountable_system')

function Resolve-InputPath([string] $Path) {
    if ([System.IO.Path]::IsPathFullyQualified($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
}

function Get-DisplayPath([string] $FullPath) {
    $relative = [System.IO.Path]::GetRelativePath($repoRoot, $FullPath).Replace('\', '/')
    if (-not $relative.StartsWith('../', [System.StringComparison]::Ordinal)) { return $relative }
    return $FullPath
}

function Add-Block([string] $Reason) {
    if (-not $blockingReasons.Contains($Reason)) { $blockingReasons.Add($Reason) }
}

function Get-PropertyValue([object] $Object, [string] $Name) {
    if ($null -eq $Object -or $Object.PSObject.Properties.Name -notcontains $Name) { return $null }
    return $Object.$Name
}

function Test-ConcreteText([object] $Value) {
    if ($null -eq $Value) { return $false }
    $text = ([string] $Value).Trim()
    return -not [string]::IsNullOrWhiteSpace($text) -and
        $text -notmatch '^<.*>$' -and
        $text -notin @('string', 'todo', 'tbd', 'unknown')
}

function Test-Sha256([object] $Value) {
    return $null -ne $Value -and ([string] $Value) -match '^[0-9a-fA-F]{64}$'
}

if ([string]::IsNullOrWhiteSpace($ExpectedCommit)) {
    $ExpectedCommit = (& git -C $repoRoot rev-parse HEAD 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or -not (Test-ConcreteText $ExpectedCommit)) {
        throw 'cannot resolve current git commit'
    }
}

$bundleFullPath = Resolve-InputPath $BundlePath
if (-not (Test-Path -LiteralPath $bundleFullPath -PathType Leaf)) {
    throw "acceptance bundle missing: $BundlePath"
}
try {
    $bundle = Get-Content -LiteralPath $bundleFullPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
catch {
    throw "acceptance bundle is not valid JSON: $BundlePath"
}

if ([string] (Get-PropertyValue $bundle 'schemaVersion') -ne 'accountable-acceptance-bundle.v1') {
    Add-Block 'schema_version_mismatch'
}
$bundleContext = Get-PropertyValue $bundle 'bundleContext'
if ([string] (Get-PropertyValue $bundleContext 'commit') -ne $ExpectedCommit) {
    Add-Block 'bundle_commit_mismatch'
}
foreach ($field in @('siteId', 'preparedAt')) {
    if (-not (Test-ConcreteText (Get-PropertyValue $bundleContext $field))) {
        Add-Block "bundle_context_missing:$field"
    }
}
try {
    [void][DateTimeOffset]::Parse([string] (Get-PropertyValue $bundleContext 'preparedAt'))
}
catch {
    Add-Block 'bundle_prepared_at_invalid'
}

$includedStages = @((Get-PropertyValue $bundleContext 'includedStages') | ForEach-Object { [string] $_ } | Where-Object { $_ })
if ($includedStages.Count -eq 0) { Add-Block 'included_stages_empty' }
if (@($includedStages | Select-Object -Unique).Count -ne $includedStages.Count) { Add-Block 'included_stages_duplicate' }
foreach ($stage in $includedStages) {
    if (-not $stageContracts.Contains($stage)) { Add-Block "unknown_stage:$stage" }
}

$evidenceReceipts = New-Object System.Collections.Generic.List[object]
$evidenceByStage = @{}
foreach ($stage in $includedStages) { $evidenceByStage[$stage] = New-Object System.Collections.Generic.List[object] }
foreach ($evidence in @((Get-PropertyValue $bundle 'evidence'))) {
    $stage = [string] (Get-PropertyValue $evidence 'stage')
    $path = [string] (Get-PropertyValue $evidence 'path')
    $claimedHash = ([string] (Get-PropertyValue $evidence 'sha256')).ToLowerInvariant()
    if (-not ($includedStages -contains $stage)) {
        Add-Block "evidence_stage_not_included:$stage"
        continue
    }
    if (-not (Test-ConcreteText $path)) {
        Add-Block "evidence_path_missing:$stage"
        continue
    }
    if (-not (Test-Sha256 $claimedHash)) {
        Add-Block "evidence_sha256_invalid:${stage}:$path"
        continue
    }
    $fullPath = Resolve-InputPath $path
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        Add-Block "evidence_file_missing:${stage}:$path"
        continue
    }
    $actualHash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $claimedHash) { Add-Block "evidence_hash_mismatch:${stage}:$path" }
    $receipt = [pscustomobject][ordered]@{
        stage = $stage
        path = Get-DisplayPath $fullPath
        claimedSha256 = $claimedHash
        actualSha256 = $actualHash
        hashMatches = $actualHash -eq $claimedHash
    }
    $evidenceReceipts.Add($receipt)
    $evidenceByStage[$stage].Add($receipt)
}

$attestations = @((Get-PropertyValue $bundle 'attestations'))
foreach ($attestation in $attestations) {
    $attestationStage = [string] (Get-PropertyValue $attestation 'stage')
    $attestationRole = [string] (Get-PropertyValue $attestation 'role')
    if (-not ($includedStages -contains $attestationStage)) {
        Add-Block "attestation_stage_not_included:$attestationStage"
        continue
    }
    if ($stageContracts.Contains($attestationStage) -and $attestationRole -notin @($stageContracts[$attestationStage].roles)) {
        Add-Block "attestation_role_not_required:${attestationStage}:$attestationRole"
    }
}
$stageResults = New-Object System.Collections.Generic.List[object]
foreach ($stage in $includedStages) {
    if (-not $stageContracts.Contains($stage)) { continue }
    $contract = $stageContracts[$stage]
    $stageEvidence = @($evidenceByStage[$stage])
    if ($stageEvidence.Count -eq 0) { Add-Block "stage_evidence_missing:$stage" }
    $stageHashes = @($stageEvidence | ForEach-Object { $_.actualSha256 } | Select-Object -Unique)
    $stageAttestations = @($attestations | Where-Object { [string] (Get-PropertyValue $_ 'stage') -eq $stage })
    $roleResults = New-Object System.Collections.Generic.List[object]

    foreach ($requiredRole in @($contract.roles)) {
        $matching = @($stageAttestations | Where-Object { [string] (Get-PropertyValue $_ 'role') -eq $requiredRole })
        if ($matching.Count -ne 1) {
            Add-Block "attestation_role_count:${stage}:${requiredRole}:$($matching.Count)"
            $roleResults.Add([pscustomobject]@{ role = $requiredRole; status = 'missing_or_duplicate'; decision = $null })
            continue
        }
        $attestation = $matching[0]
        foreach ($field in @('signerId', 'signedAt', 'decision', 'verificationMethod', 'verificationReference')) {
            if (-not (Test-ConcreteText (Get-PropertyValue $attestation $field))) {
                Add-Block "attestation_field_missing:${stage}:${requiredRole}:$field"
            }
        }
        if ([string] (Get-PropertyValue $attestation 'commit') -ne $ExpectedCommit) {
            Add-Block "attestation_commit_mismatch:${stage}:$requiredRole"
        }
        $verificationMethod = [string] (Get-PropertyValue $attestation 'verificationMethod')
        if ($verificationMethod -notin $allowedVerificationMethods) {
            Add-Block "attestation_verification_method_invalid:${stage}:$requiredRole"
        }
        try {
            $signedAt = [DateTimeOffset]::Parse([string] (Get-PropertyValue $attestation 'signedAt'))
            if ($signedAt -gt (Get-Date).AddMinutes(5)) { Add-Block "attestation_signed_at_future:${stage}:$requiredRole" }
        }
        catch {
            Add-Block "attestation_signed_at_invalid:${stage}:$requiredRole"
        }
        $attestedHashes = @((Get-PropertyValue $attestation 'evidenceSha256') | ForEach-Object { ([string] $_).ToLowerInvariant() } | Where-Object { $_ })
        foreach ($hash in $stageHashes) {
            if ($attestedHashes -notcontains $hash) { Add-Block "attestation_evidence_hash_missing:${stage}:${requiredRole}:$hash" }
        }
        $decision = [string] (Get-PropertyValue $attestation 'decision')
        $decisionAccepted = $decision -in @($contract.acceptedDecisions)
        if (-not $decisionAccepted -and $decision -ne 'keep_blocked') {
            Add-Block "attestation_decision_invalid:${stage}:${requiredRole}:$decision"
        }
        $roleResults.Add([pscustomobject]@{
            role = $requiredRole
            status = if ($decisionAccepted) { 'accepted' } else { 'keep_blocked' }
            decision = $decision
        })
    }

    $allRolesPresent = @($roleResults | Where-Object status -eq 'missing_or_duplicate').Count -eq 0
    $allRolesAccepted = $allRolesPresent -and @($roleResults | Where-Object status -ne 'accepted').Count -eq 0
    $acceptedDecisions = @($roleResults | Where-Object status -eq 'accepted' | ForEach-Object decision | Select-Object -Unique)
    if ($allRolesAccepted -and $acceptedDecisions.Count -ne 1) {
        Add-Block "attestation_decision_mismatch:$stage"
        $allRolesAccepted = $false
    }
    $stageResults.Add([pscustomobject][ordered]@{
        stage = $stage
        evidenceCount = $stageEvidence.Count
        requiredRoles = @($contract.roles)
        roleResults = $roleResults.ToArray()
        readyForAccountableReview = $allRolesAccepted
        formalDecisionCandidate = if ($stage -eq 'P006' -and $allRolesAccepted) { [string] $acceptedDecisions[0] } else { $null }
    })
}

$status = if ($blockingReasons.Count -eq 0) { 'pass' } else { 'blocked' }
$readyStages = @($stageResults | Where-Object readyForAccountableReview | ForEach-Object stage)
$p006Result = @($stageResults | Where-Object stage -eq 'P006' | Select-Object -First 1)
$report = [ordered]@{
    schemaVersion = 'accountable-acceptance-report.v1'
    status = $status
    mode = $Mode
    checkedAt = (Get-Date).ToString('o')
    bundlePath = Get-DisplayPath $bundleFullPath
    bundleSha256 = (Get-FileHash -LiteralPath $bundleFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    expectedCommit = $ExpectedCommit
    includedStages = $includedStages
    evidenceReceipts = $evidenceReceipts.ToArray()
    stageResults = $stageResults.ToArray()
    readyStages = $readyStages
    readyForAccountableReview = $status -eq 'pass' -and $readyStages.Count -eq $includedStages.Count
    releaseDecisionCandidate = if ($p006Result.Count -eq 1) { [string] $p006Result[0].formalDecisionCandidate } else { $null }
    releaseAdvanceAllowed = $false
    blockingReasons = $blockingReasons.ToArray()
    identityVerificationRequired = $true
    identityBoundary = 'verificationMethod and verificationReference are present and hash-bound, but their external identity-system truth must be checked by an accountable human or trusted identity provider.'
    formalAcceptanceStillRequired = $true
    sideEffectBoundary = 'Validates and optionally writes this report only. It never signs, updates backlog/evidence index/release card/active state, creates tags, or contacts an identity provider.'
    truthBoundary = 'pass means structurally complete, commit-bound, hash-bound material ready for accountable review; it is not automatic onsite or live acceptance.'
}
$json = $report | ConvertTo-Json -Depth 12
if ($Mode -eq 'Collect') {
    $outputFullPath = Resolve-InputPath $OutputPath
    $outputDirectory = Split-Path -Parent $outputFullPath
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    $candidatePath = Join-Path $outputDirectory ('.{0}.{1}.tmp' -f [System.IO.Path]::GetFileName($outputFullPath), [Guid]::NewGuid().ToString('N'))
    try {
        $json | Set-Content -LiteralPath $candidatePath -Encoding UTF8
        Get-Content -LiteralPath $candidatePath -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
        [System.IO.File]::Move($candidatePath, $outputFullPath, $true)
    }
    finally {
        if (Test-Path -LiteralPath $candidatePath -PathType Leaf) { Remove-Item -LiteralPath $candidatePath -Force }
    }
}
$json
if ($status -ne 'pass') { throw "accountable acceptance bundle blocked: $($blockingReasons -join ', ')" }

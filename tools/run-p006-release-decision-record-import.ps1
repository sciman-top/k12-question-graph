param(
    [string] $RecordJsonPath,
    [string] $RecordMarkdownPath = '',
    [string] $ReportPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Resolve-FlexiblePath([string] $PathValue) {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($PathValue)) 'path value must not be empty'
    $fullPath = if ([System.IO.Path]::IsPathRooted($PathValue)) { $PathValue } else { Join-Path $repoRoot ($PathValue -replace '/', [System.IO.Path]::DirectorySeparatorChar) }
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing path: $PathValue"
    return (Resolve-Path -LiteralPath $fullPath).Path
}

function Require-Text([object] $Value, [string] $Label) {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$Value)) "$Label must not be empty"
}

Push-Location $repoRoot
try {
    $recordJsonFullPath = Resolve-FlexiblePath $RecordJsonPath
    $record = Get-Content -LiteralPath $recordJsonFullPath -Raw | ConvertFrom-Json
    Assert-Condition ($record.schemaVersion -eq 'p006-release-decision-record.v1') 'P006 decision record schema mismatch'

    foreach ($field in @('date', 'decision', 'targetMilestone', 'releaseCandidate', 'deploymentMode', 'siteScope')) {
        Require-Text $record.decisionContext.$field "decisionContext.$field"
    }
    Assert-Condition (@('go', 'no_go', 'go_with_named_exceptions') -contains [string]$record.decisionContext.decision) 'unsupported P006 decision value'

    foreach ($field in @('p001ReadinessPack', 'p005Triage', 'goNoGoCard', 'fullGateEvidence', 'roadmapGuardEvidence', 'backupEvidence', 'restoreEvidence', 'privacyEvidence', 'roleAuditEvidence')) {
        Require-Text $record.evidenceAnchors.$field "evidenceAnchors.$field"
    }
    foreach ($field in @('buildTestContractHotspot', 'backupRestore', 'teacherEfficiency', 'privacyAuthorization', 'roleAudit')) {
        Require-Text $record.gateReview.$field "gateReview.$field"
    }

    if ([string]$record.decisionContext.decision -eq 'go_with_named_exceptions') {
        Assert-Condition (@($record.exceptions).Count -ge 1) 'go_with_named_exceptions requires at least one exception'
        foreach ($exception in @($record.exceptions)) {
            foreach ($field in @('id', 'title', 'owner', 'expiresAt', 'recoveryPlan', 'evidenceLink', 'acceptedRisk')) {
                Require-Text $exception.$field "exceptions.$field"
            }
        }
    }

    foreach ($field in @('createTagCandidate', 'tagName', 'rollbackWindow', 'disableSwitchPlan')) {
        if ($field -eq 'createTagCandidate') { continue }
        Require-Text $record.tagCandidatePlan.$field "tagCandidatePlan.$field"
    }
    foreach ($field in @('releaseOwner', 'adminOwner', 'dataOwnerRepresentative', 'pilotSupportOwner')) {
        Require-Text $record.signoff.$field "signoff.$field"
    }
    Require-Text $record.finalRationale 'finalRationale'

    if (-not [string]::IsNullOrWhiteSpace($RecordMarkdownPath)) {
        $null = Resolve-FlexiblePath $RecordMarkdownPath
    }

    if ([string]::IsNullOrWhiteSpace($ReportPath)) {
        $dateText = [string]$record.decisionContext.date
        $dateStamp = ($dateText -replace '-', '')
        $ReportPath = "docs/evidence/{0}-p006-release-decision-validation.json" -f $dateStamp
    }

    $reportFullPath = if ([System.IO.Path]::IsPathRooted($ReportPath)) { $ReportPath } else { Join-Path $repoRoot ($ReportPath -replace '/', [System.IO.Path]::DirectorySeparatorChar) }
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null

    $report = [ordered]@{
        status = 'pass'
        taskId = 'P006'
        checkedAt = (Get-Date).ToString('s')
        mode = 'release_decision_record_import'
        recordJsonPath = $RecordJsonPath
        recordMarkdownPath = $RecordMarkdownPath
        decision = [string]$record.decisionContext.decision
        acceptance = [ordered]@{
            evidenceAnchorsPresent = $true
            gateReviewPresent = $true
            signoffRecorded = $true
            rationalePresent = $true
        }
        boundary = 'P006 import validates the structure of a release decision record only. It does not itself mark release-ready or create a tag candidate.'
    }

    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 10
}
finally {
    Pop-Location
}

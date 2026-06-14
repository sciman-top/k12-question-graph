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
    Assert-Condition ($record.schemaVersion -eq 'p003-onsite-pilot-admission-card.v1') 'P003 admission card schema mismatch'

    foreach ($field in @('date', 'site', 'operator', 'teacherOrProxy', 'admissionDecision', 'sourceEvidence')) {
        Require-Text $record.admissionContext.$field "admissionContext.$field"
    }
    Assert-Condition (@('continue_p004', 'keep_blocked') -contains [string]$record.admissionContext.admissionDecision) 'unsupported P003 admission decision'

    foreach ($field in @('participants', 'allowedActions', 'forbiddenActions', 'observationGoal')) {
        Assert-Condition ($null -ne $record.teacherBoundary.$field) "teacherBoundary.$field must not be null"
    }
    Assert-Condition (@($record.teacherBoundary.participants).Count -ge 1) 'teacherBoundary.participants must contain at least one participant'
    Assert-Condition (@($record.teacherBoundary.allowedActions).Count -ge 1) 'teacherBoundary.allowedActions must contain at least one action'
    Assert-Condition (@($record.teacherBoundary.forbiddenActions).Count -ge 1) 'teacherBoundary.forbiddenActions must contain at least one action'
    Require-Text $record.teacherBoundary.observationGoal 'teacherBoundary.observationGoal'

    foreach ($field in @('materialScope', 'expiresAt', 'owner', 'prohibitedActions')) {
        Assert-Condition ($null -ne $record.dataAuthorization.$field) "dataAuthorization.$field must not be null"
    }
    Require-Text $record.dataAuthorization.materialScope 'dataAuthorization.materialScope'
    Require-Text $record.dataAuthorization.expiresAt 'dataAuthorization.expiresAt'
    Require-Text $record.dataAuthorization.owner 'dataAuthorization.owner'
    Assert-Condition (@($record.dataAuthorization.prohibitedActions).Count -ge 1) 'dataAuthorization.prohibitedActions must contain at least one action'

    foreach ($field in @('onsiteSupport', 'techSupport', 'escalationContact')) {
        Require-Text $record.supportContacts.$field "supportContacts.$field"
    }
    foreach ($field in @('trigger', 'action', 'owner', 'recoveryEntry')) {
        Require-Text $record.rollbackPlan.$field "rollbackPlan.$field"
    }
    foreach ($field in @('path', 'collectionCadence', 'escalationPath')) {
        Require-Text $record.feedbackTemplate.$field "feedbackTemplate.$field"
    }
    foreach ($field in @('productOwner', 'dataOwnerRepresentative', 'supportOwner', 'releaseOwner')) {
        Require-Text $record.signoff.$field "signoff.$field"
    }
    Assert-Condition (@($record.decisionNotes).Count -ge 1) 'decisionNotes must contain at least one note'

    if (-not [string]::IsNullOrWhiteSpace($RecordMarkdownPath)) {
        $null = Resolve-FlexiblePath $RecordMarkdownPath
    }

    if ([string]::IsNullOrWhiteSpace($ReportPath)) {
        $dateText = [string]$record.admissionContext.date
        $dateStamp = ($dateText -replace '-', '')
        $ReportPath = "docs/evidence/{0}-p003-admission-card-validation.json" -f $dateStamp
    }

    $reportFullPath = if ([System.IO.Path]::IsPathRooted($ReportPath)) { $ReportPath } else { Join-Path $repoRoot ($ReportPath -replace '/', [System.IO.Path]::DirectorySeparatorChar) }
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null

    $report = [ordered]@{
        status = 'pass'
        taskId = 'P003'
        checkedAt = (Get-Date).ToString('s')
        mode = 'onsite_pilot_admission_card_import'
        recordJsonPath = $RecordJsonPath
        recordMarkdownPath = $RecordMarkdownPath
        decision = [ordered]@{
            requested = [string]$record.admissionContext.admissionDecision
            p004CanAdvance = ([string]$record.admissionContext.admissionDecision -eq 'continue_p004')
        }
        acceptance = [ordered]@{
            teacherBoundaryPresent = $true
            dataAuthorizationPresent = $true
            supportContactsPresent = $true
            rollbackPlanPresent = $true
            feedbackTemplatePresent = $true
            signoffRecorded = $true
        }
        boundary = 'P003 import validates the structure of a pilot admission card only. It does not itself change backlog rows or close P003.'
    }

    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 10
}
finally {
    Pop-Location
}

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
    Assert-Condition ($record.schemaVersion -eq 'p005-pilot-feedback-triage.v1') 'P005 triage record schema mismatch'

    foreach ($field in @('date', 'sourceEvidence', 'operator', 'teacherOrProxy', 'site')) {
        Require-Text $record.pilotContext.$field "pilotContext.$field"
    }

    $items = @($record.items)
    Assert-Condition ($items.Count -ge 1) 'P005 triage record must contain at least one feedback item'

    $decisionCounts = @{
        keep = 0
        modify = 0
        defer = 0
        do_not_do = 0
    }

    foreach ($item in $items) {
        foreach ($field in @('id', 'title', 'sourceStep', 'description', 'teacherEfficiencyImpact', 'frequency', 'risk', 'cost', 'decision', 'reason', 'owner', 'targetArtifact', 'rollbackOrFallback')) {
            Require-Text $item.$field "items.$field"
        }
        Assert-Condition ($decisionCounts.ContainsKey([string]$item.decision)) "unsupported triage decision: $($item.decision)"
        $decisionCounts[[string]$item.decision] += 1
    }

    Assert-Condition ([int]$record.summary.totalFeedbackItems -eq $items.Count) 'summary.totalFeedbackItems must equal item count'
    Assert-Condition ([int]$record.summary.keepCount -eq $decisionCounts.keep) 'summary.keepCount mismatch'
    Assert-Condition ([int]$record.summary.modifyCount -eq $decisionCounts.modify) 'summary.modifyCount mismatch'
    Assert-Condition ([int]$record.summary.deferCount -eq $decisionCounts.defer) 'summary.deferCount mismatch'
    Assert-Condition ([int]$record.summary.doNotDoCount -eq $decisionCounts.do_not_do) 'summary.doNotDoCount mismatch'

    foreach ($field in @('overallTeacherEfficiencyImpact')) {
        Require-Text $record.summary.$field "summary.$field"
    }
    foreach ($field in @('keep', 'modify', 'defer', 'doNotDo')) {
        Require-Text $record.decisionNotes.$field "decisionNotes.$field"
    }
    foreach ($field in @('triageOwner', 'productOwnerReview', 'releaseOwnerReview')) {
        Require-Text $record.signoff.$field "signoff.$field"
    }

    if (-not [string]::IsNullOrWhiteSpace($RecordMarkdownPath)) {
        $null = Resolve-FlexiblePath $RecordMarkdownPath
    }

    if ([string]::IsNullOrWhiteSpace($ReportPath)) {
        $dateText = [string]$record.pilotContext.date
        $dateStamp = ($dateText -replace '-', '')
        $ReportPath = "docs/evidence/{0}-p005-feedback-triage-validation.json" -f $dateStamp
    }

    $reportFullPath = if ([System.IO.Path]::IsPathRooted($ReportPath)) { $ReportPath } else { Join-Path $repoRoot ($ReportPath -replace '/', [System.IO.Path]::DirectorySeparatorChar) }
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null

    $report = [ordered]@{
        status = 'pass'
        taskId = 'P005'
        checkedAt = (Get-Date).ToString('s')
        mode = 'pilot_feedback_triage_import'
        recordJsonPath = $RecordJsonPath
        recordMarkdownPath = $RecordMarkdownPath
        summary = [ordered]@{
            totalFeedbackItems = $items.Count
            keepCount = $decisionCounts.keep
            modifyCount = $decisionCounts.modify
            deferCount = $decisionCounts.defer
            doNotDoCount = $decisionCounts.do_not_do
        }
        acceptance = [ordered]@{
            sourceEvidenceLinked = $true
            allItemsClassified = $true
            summaryCountsMatch = $true
            signoffRecorded = $true
        }
        boundary = 'P005 import validates structured feedback triage only. It does not itself change backlog rows or close P005.'
    }

    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 10
}
finally {
    Pop-Location
}

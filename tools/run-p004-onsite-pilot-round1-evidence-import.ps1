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
    Assert-Condition ($record.schemaVersion -eq 'p004-onsite-pilot-round1-evidence.v1') 'P004 teacher pilot evidence schema mismatch'

    foreach ($field in @('date', 'site', 'operator', 'teacher', 'sourceEvidence', 'decision')) {
        Require-Text $record.pilotContext.$field "pilotContext.$field"
    }
    Assert-Condition (@('continue_p005', 'keep_blocked') -contains [string]$record.pilotContext.decision) 'unsupported P004 decision'

    foreach ($field in @('routeSmoke', 'artifactProbe', 'visualSurrogate', 'traceLog')) {
        Require-Text $record.prefilledChecks.$field "prefilledChecks.$field"
    }

    $timingRows = @($record.workflowTiming)
    Assert-Condition ($timingRows.Count -ge 1) 'workflowTiming must contain at least one row'
    foreach ($row in $timingRows) {
        foreach ($field in @('step', 'durationMinutes', 'outcome')) {
            Require-Text $row.$field "workflowTiming.$field"
        }
    }

    $frictionItems = @($record.frictionItems)
    Assert-Condition ($frictionItems.Count -ge 1) 'frictionItems must contain at least one item'
    foreach ($item in $frictionItems) {
        foreach ($field in @('category', 'detail', 'severity')) {
            Require-Text $item.$field "frictionItems.$field"
        }
    }

    $rollbackEvents = @($record.rollbackEvents)
    Assert-Condition ($rollbackEvents.Count -ge 1) 'rollbackEvents must contain at least one event'
    foreach ($event in $rollbackEvents) {
        foreach ($field in @('trigger', 'action', 'recoveryMinutes')) {
            Require-Text $event.$field "rollbackEvents.$field"
        }
    }

    foreach ($field in @('teacherUnderstanding', 'environmentBlockers', 'recommendation')) {
        Assert-Condition ($null -ne $record.summary.$field) "summary.$field must not be null"
    }
    Require-Text $record.summary.teacherUnderstanding 'summary.teacherUnderstanding'
    Assert-Condition (@($record.summary.environmentBlockers).Count -ge 1) 'summary.environmentBlockers must contain at least one blocker'
    Require-Text $record.summary.recommendation 'summary.recommendation'

    foreach ($field in @('pilotOwner', 'supportOwner', 'releaseOwner')) {
        Require-Text $record.signoff.$field "signoff.$field"
    }

    if (-not [string]::IsNullOrWhiteSpace($RecordMarkdownPath)) {
        $null = Resolve-FlexiblePath $RecordMarkdownPath
    }

    if ([string]::IsNullOrWhiteSpace($ReportPath)) {
        $dateText = [string]$record.pilotContext.date
        $dateStamp = ($dateText -replace '-', '')
        $ReportPath = "docs/evidence/{0}-p004-teacher-pilot-validation.json" -f $dateStamp
    }

    $reportFullPath = if ([System.IO.Path]::IsPathRooted($ReportPath)) { $ReportPath } else { Join-Path $repoRoot ($ReportPath -replace '/', [System.IO.Path]::DirectorySeparatorChar) }
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null

    $report = [ordered]@{
        status = 'pass'
        taskId = 'P004'
        checkedAt = (Get-Date).ToString('s')
        mode = 'onsite_pilot_round1_evidence_import'
        recordJsonPath = $RecordJsonPath
        recordMarkdownPath = $RecordMarkdownPath
        decision = [ordered]@{
            requested = [string]$record.pilotContext.decision
            p005CanAdvance = ([string]$record.pilotContext.decision -eq 'continue_p005')
        }
        acceptance = [ordered]@{
            prefilledChecksPresent = $true
            workflowTimingPresent = $true
            frictionItemsPresent = $true
            rollbackEventsPresent = $true
            summaryPresent = $true
            signoffRecorded = $true
        }
        boundary = 'P004 import validates the structure of teacher pilot evidence only. It does not itself change backlog rows or close P004.'
    }

    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 10
}
finally {
    Pop-Location
}

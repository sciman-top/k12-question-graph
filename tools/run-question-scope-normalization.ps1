param(
    [string] $CsvRoot = 'guangzhou-physics-full-research-package-2016-2025\csv',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabaseUser = 'postgres',
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $ManifestPath = 'tmp\cek010\question-scope-manifest.json',
    [string] $ReportPath = 'docs\evidence\cek010-question-scope-normalization.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Write-Json([object] $Value, [string] $Path) {
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 30) + "`n"), [Text.UTF8Encoding]::new($false))
}

function Get-ReferenceRevision([string] $Path) {
    $revision = (& git -C $Path rev-parse HEAD).Trim()
    Assert-True ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($revision)) "reference revision unavailable: $Path"
    return $revision
}

. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword $DatabasePassword
Assert-True (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'database password required'

$csv = (Resolve-Path $CsvRoot).Path
$manifest = [IO.Path]::GetFullPath((Join-Path $repoRoot $ManifestPath))
$report = [IO.Path]::GetFullPath((Join-Path $repoRoot $ReportPath))
$connection = "host=$DatabaseHost port=$DatabasePort dbname=$DatabaseName user=$DatabaseUser"
$previousPassword = $env:PGPASSWORD
$env:PGPASSWORD = $DatabasePassword

Push-Location $repoRoot
try {
    python -m unittest tests.workers.test_question_scope_normalization
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-10 unit tests failed'

    python tools/question_scope_normalization.py `
        --csv-root $csv `
        --connection-string $connection `
        --manifest $manifest `
        --evidence $report
    Assert-True ($LASTEXITCODE -eq 0) 'scope manifest generation failed'

    $payload = Get-Content -Raw $report | ConvertFrom-Json
    Assert-True ($payload.status -eq 'pass') 'scope report status mismatch'
    Assert-True ($payload.manifest.questions -eq 234) 'materialized question count mismatch'
    Assert-True ($payload.scopeCounts.whole_question -eq 234) 'whole question scope count mismatch'
    Assert-True ($payload.scopeCounts.subquestion -eq 210) 'subquestion scope count mismatch'
    Assert-True ($payload.scopeCounts.scoring_point -eq 0) 'unexpected real scoring point scopes'
    Assert-True ($payload.blockCandidateCounts.subquestion -eq 210) 'subquestion block count mismatch'
    Assert-True ($payload.blockCandidateCounts.scoring_point -eq 0) 'unexpected real scoring point blocks'
    Assert-True ($payload.sourceRows.wholeMarkers -eq 139) 'whole marker count mismatch'
    Assert-True ($payload.sourceRows.wholeQuestionScoringSummaries -eq 210) 'whole scoring summary count mismatch'
    Assert-True ($payload.invariants.nonWholeScopesReferenceQuestionBlock) 'non-whole block reference invariant failed'
    Assert-True ($payload.invariants.wholeScopesHaveNoQuestionBlockReference) 'whole block reference invariant failed'
    Assert-True ($payload.invariants.allNewScopesPendingReview) 'scope review status invariant failed'
    Assert-True ($payload.invariants.allNewBlocksPendingReview) 'block review status invariant failed'

    $payload | Add-Member -NotePropertyName referencesReviewed -NotePropertyValue @(
        [ordered]@{
            path = 'official-docs/AspNetCore.Docs/aspnetcore/mvc/models/model-binding.md'
            revision = Get-ReferenceRevision 'D:\CODE\external\k12-question-graph-references\official-docs\AspNetCore.Docs'
            purpose = 'explicit API input validation boundary'
        },
        [ordered]@{
            path = 'education-assessment/moodle'
            revision = Get-ReferenceRevision 'D:\CODE\external\k12-question-graph-references\education-assessment\moodle'
            purpose = 'question-bank governance comparison only'
        },
        [ordered]@{
            path = 'education-assessment/OpenOLAT'
            revision = Get-ReferenceRevision 'D:\CODE\external\k12-question-graph-references\education-assessment\OpenOLAT'
            purpose = 'assessment-item lifecycle comparison only'
        }
    )
    $payload | Add-Member -NotePropertyName adoptionDecision -NotePropertyValue ([ordered]@{
        mode = 'reference_only_no_copy'
        decision = 'retain the existing QuestionBlock and pending-review model; add optional scope metadata without copying LMS/QTI models'
        dependenciesAdded = 0
        licensesCopied = $false
    })
    Write-Json $payload $report
    $payload | ConvertTo-Json -Depth 30
}
finally {
    $env:PGPASSWORD = $previousPassword
    Pop-Location
}

param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ReportPath = 'docs/evidence/20260505-pqr-preflight-freshness-report.json',
    [string] $ExpectedDatePrefix = '20260505'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$rows = Import-Csv -LiteralPath (Join-Path $repoRoot $BacklogPath) -Encoding UTF8
$targets = $rows | Where-Object { $_.id -match '^(P00[1-6]|Q00[1-5]|R00[1-7])$' }
Assert-True ($targets.Count -eq 18) 'PQR freshness guard expects 18 targets'

$issues = New-Object System.Collections.Generic.List[object]
foreach ($row in $targets) {
    $idLower = $row.id.ToLower()
    $expectedEvidence = switch ($idLower) {
        'p001' { 'docs/evidence/20260505-p001-live-pilot-readiness-preflight.md' }
        'p002' { 'docs/evidence/20260505-p002-teacher-proxy-pilot-preflight.md' }
        'p003' { 'docs/evidence/20260505-p003-onsite-pilot-admission-preflight.md' }
        'p004' { 'docs/evidence/20260505-p004-onsite-pilot-round1-preflight.md' }
        'p005' { 'docs/evidence/20260505-p005-pilot-feedback-backlog-preflight.md' }
        'p006' { 'docs/evidence/20260505-p006-release-decision-preflight.md' }
        'q001' { 'docs/evidence/20260505-q001-second-subject-candidate-admission-preflight.md' }
        'q002' { 'docs/evidence/20260505-q002-second-subject-teacher-review-template-preflight.md' }
        'q003' { 'docs/evidence/20260505-q003-second-subject-active-drill-preflight.md' }
        'q004' { 'docs/evidence/20260505-q004-cross-subject-diff-report-preflight.md' }
        'q005' { 'docs/evidence/20260505-q005-multi-subject-ui-simplification-preflight.md' }
        'r001' { 'docs/evidence/20260505-r001-search-semantic-retrieval-eval-preflight.md' }
        'r002' { 'docs/evidence/20260505-r002-queue-worker-scale-eval-preflight.md' }
        'r003' { 'docs/evidence/20260505-r003-interop-eval-preflight.md' }
        'r004' { 'docs/evidence/20260505-r004-advanced-analysis-eval-preflight.md' }
        'r005' { 'docs/evidence/20260505-r005-public-multischool-deploy-eval-preflight.md' }
        'r006' { 'docs/evidence/20260505-r006-techdebt-cadence-preflight.md' }
        'r007' { 'docs/evidence/20260505-r007-interoperability-profile-map-preflight.md' }
        default { $null }
    }
    if ([string]::IsNullOrWhiteSpace($expectedEvidence)) {
        $issues.Add([ordered]@{ id = $row.id; issue = 'no expected evidence mapping' })
        continue
    }

    if (-not $expectedEvidence.Contains($ExpectedDatePrefix)) {
        $issues.Add([ordered]@{ id = $row.id; issue = "evidence path missing expected date prefix $ExpectedDatePrefix" })
    }

    $evidenceFullPath = Join-Path $repoRoot $expectedEvidence
    if (-not (Test-Path -LiteralPath $evidenceFullPath)) {
        $issues.Add([ordered]@{ id = $row.id; issue = "missing evidence file: $expectedEvidence" })
        continue
    }

    $content = Get-Content -LiteralPath $evidenceFullPath -Raw
    foreach ($k in @('preflight', 'platform_na', 'gate_na', '下一步')) {
        if (-not $content.Contains($k)) {
            $issues.Add([ordered]@{ id = $row.id; issue = "evidence missing keyword: $k" })
        }
    }
}

Assert-True ($issues.Count -eq 0) ("PQR freshness guard failed: " + ($issues | ConvertTo-Json -Depth 5 -Compress))

$report = [ordered]@{
    status = 'pass'
    task = 'PQR preflight freshness guard'
    checkedAt = (Get-Date).ToString('s')
    expectedDatePrefix = $ExpectedDatePrefix
    targetCount = $targets.Count
    report = $ReportPath
}
$report | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $repoRoot $ReportPath) -Encoding UTF8
$report | ConvertTo-Json -Depth 4

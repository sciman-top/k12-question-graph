param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $ReportPath = 'docs/evidence/20260505-pqr-preflight-pack-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Write-ContentIfChanged([string]$Path, [string]$Content) {
    if (Test-Path -LiteralPath $Path) {
        $existing = Get-Content -LiteralPath $Path -Raw
        if ($existing -eq $Content) { return }
    }
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

$backlogFullPath = Join-Path $repoRoot $BacklogPath
$reportFullPath = Join-Path $repoRoot $ReportPath
Assert-True (Test-Path -LiteralPath $backlogFullPath) "PQR backlog file missing: $BacklogPath"

$rows = Import-Csv -LiteralPath $backlogFullPath -Encoding UTF8
$targets = $rows | Where-Object { $_.id -match '^(P00[1-6]|Q00[1-5]|R00[1-7])$' }
Assert-True ($targets.Count -eq 18) 'PQR target count must be 18 (P001-P006,Q001-Q005,R001-R007)'

$missing = New-Object System.Collections.Generic.List[object]
foreach ($row in $targets) {
    if ($row.status -ne '待办') {
        $missing.Add([ordered]@{ id = $row.id; issue = "status must remain 待办 in preflight pack, found $($row.status)" })
    }
    $parts = @($row.verification -split '\+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($parts.Count -lt 2) {
        $missing.Add([ordered]@{ id = $row.id; issue = 'verification must include at least contract + checklist' })
        continue
    }
    $contractPath = Join-Path $repoRoot ($parts[0] -replace '\\', '/')
    $checklistPath = Join-Path $repoRoot ($parts[1] -replace '\\', '/')
    if (-not (Test-Path -LiteralPath $contractPath)) { $missing.Add([ordered]@{ id = $row.id; issue = "missing contract path: $($parts[0])" }) }
    if (-not (Test-Path -LiteralPath $checklistPath)) { $missing.Add([ordered]@{ id = $row.id; issue = "missing checklist path: $($parts[1])" }) }

    $normalizedId = $row.id.ToLower()
    $evidenceMap = @{
        'p001' = 'docs/evidence/20260505-p001-live-pilot-readiness-preflight.md'
        'p002' = 'docs/evidence/20260505-p002-teacher-proxy-pilot-preflight.md'
        'p003' = 'docs/evidence/20260505-p003-onsite-pilot-admission-preflight.md'
        'p004' = 'docs/evidence/20260505-p004-onsite-pilot-round1-preflight.md'
        'p005' = 'docs/evidence/20260505-p005-pilot-feedback-backlog-preflight.md'
        'p006' = 'docs/evidence/20260505-p006-release-decision-preflight.md'
        'q001' = 'docs/evidence/20260505-q001-second-subject-candidate-admission-preflight.md'
        'q002' = 'docs/evidence/20260505-q002-second-subject-teacher-review-template-preflight.md'
        'q003' = 'docs/evidence/20260505-q003-second-subject-active-drill-preflight.md'
        'q004' = 'docs/evidence/20260505-q004-cross-subject-diff-report-preflight.md'
        'q005' = 'docs/evidence/20260505-q005-multi-subject-ui-simplification-preflight.md'
        'r001' = 'docs/evidence/20260505-r001-search-semantic-retrieval-eval-preflight.md'
        'r002' = 'docs/evidence/20260505-r002-queue-worker-scale-eval-preflight.md'
        'r003' = 'docs/evidence/20260505-r003-interop-eval-preflight.md'
        'r004' = 'docs/evidence/20260505-r004-advanced-analysis-eval-preflight.md'
        'r005' = 'docs/evidence/20260505-r005-public-multischool-deploy-eval-preflight.md'
        'r006' = 'docs/evidence/20260505-r006-techdebt-cadence-preflight.md'
        'r007' = 'docs/evidence/20260505-r007-interoperability-profile-map-preflight.md'
    }
    if (-not $evidenceMap.ContainsKey($normalizedId)) {
        $missing.Add([ordered]@{ id = $row.id; issue = 'no expected evidence mapping found' })
        continue
    }
    $evidencePath = Join-Path $repoRoot $evidenceMap[$normalizedId]
    if (-not (Test-Path -LiteralPath $evidencePath)) {
        $missing.Add([ordered]@{ id = $row.id; issue = "missing evidence file: $($evidenceMap[$normalizedId])" })
    }
}

Assert-True ($missing.Count -eq 0) ("PQR preflight pack validation failed: " + ($missing | ConvertTo-Json -Depth 5 -Compress))

$summary = [ordered]@{
    status = 'pass'
    task = 'PQR preflight pack'
    checkedDate = (Get-Date).ToString('yyyy-MM-dd')
    targetCount = $targets.Count
    todoCount = ($targets | Where-Object { $_.status -eq '待办' }).Count
    groups = [ordered]@{
        P = ($targets | Where-Object { $_.id -like 'P*' } | Select-Object -ExpandProperty id)
        Q = ($targets | Where-Object { $_.id -like 'Q*' } | Select-Object -ExpandProperty id)
        R = ($targets | Where-Object { $_.id -like 'R*' } | Select-Object -ExpandProperty id)
    }
    boundary = 'preflight only; no live execution state transition is performed'
    report = $ReportPath
}

$summaryJson = $summary | ConvertTo-Json -Depth 6
Write-ContentIfChanged -Path $reportFullPath -Content $summaryJson
$summary | ConvertTo-Json -Depth 6

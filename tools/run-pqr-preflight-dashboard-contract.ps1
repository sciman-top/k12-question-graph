param(
    [string] $BacklogPath = 'tasks/backlog.csv',
    [string] $DashboardJsonPath = 'docs/evidence/20260505-pqr-preflight-dashboard.json',
    [string] $DashboardMarkdownPath = 'docs/evidence/20260505-pqr-preflight-dashboard.md'
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

$rows = Import-Csv -LiteralPath (Join-Path $repoRoot $BacklogPath) -Encoding UTF8
$targets = $rows | Where-Object { $_.id -match '^(P00[1-6]|Q00[1-5]|R00[1-7])$' } | Sort-Object id
Assert-True ($targets.Count -eq 18) 'PQR dashboard expects 18 target tasks'

$groups = [ordered]@{
    P = @($targets | Where-Object { $_.id -like 'P*' })
    Q = @($targets | Where-Object { $_.id -like 'Q*' })
    R = @($targets | Where-Object { $_.id -like 'R*' })
}

$summary = [ordered]@{
    status = 'pass'
    task = 'PQR preflight dashboard'
    checkedDate = (Get-Date).ToString('yyyy-MM-dd')
    totals = [ordered]@{
        all = $targets.Count
        todo = @($targets | Where-Object { $_.status -eq '待办' }).Count
        completed = @($targets | Where-Object { $_.status -eq '已完成' }).Count
    }
    blockers = [ordered]@{
        root = 'S012 productization and P006 release decision remain todo; downstream Q/R stay preflight-only by design'
        p = 'P001-P006 require S012 productized E2E plus live/on-site evidence to transition from 待办'
        q = 'Q001-Q005 depend on P006 and second-subject real execution evidence'
        r = 'R001-R003/R005-R007 depend on P006; R004 depends on N004 and advanced-analysis admission'
    }
    nextActions = @(
        'Close S001->S012 first to productize the teacher workflow before live/on-site execution.',
        'When live/on-site execution becomes available, close P001->P006 in order with real evidence.',
        'After P006, execute Q001->Q005 second-subject pipeline with admission/review/activation proof.',
        'Then execute R-series evaluations with ADR/admission artifacts.'
    )
    groups = [ordered]@{
        P = @($groups.P | ForEach-Object { [ordered]@{ id=$_.id; status=$_.status; depends_on=$_.depends_on } })
        Q = @($groups.Q | ForEach-Object { [ordered]@{ id=$_.id; status=$_.status; depends_on=$_.depends_on } })
        R = @($groups.R | ForEach-Object { [ordered]@{ id=$_.id; status=$_.status; depends_on=$_.depends_on } })
    }
}

$jsonFullPath = Join-Path $repoRoot $DashboardJsonPath
$mdFullPath = Join-Path $repoRoot $DashboardMarkdownPath
$summaryJson = $summary | ConvertTo-Json -Depth 8
Write-ContentIfChanged -Path $jsonFullPath -Content $summaryJson

$md = @()
$md += '# 20260505 PQR preflight dashboard'
$md += ''
$md += "- checkedDate: $($summary.checkedDate)"
$md += "- totals: all=$($summary.totals.all), todo=$($summary.totals.todo), completed=$($summary.totals.completed)"
$md += ''
$md += '## Blockers'
$md += "- root: $($summary.blockers.root)"
$md += "- P: $($summary.blockers.p)"
$md += "- Q: $($summary.blockers.q)"
$md += "- R: $($summary.blockers.r)"
$md += ''
$md += '## Next Actions'
foreach ($line in $summary.nextActions) { $md += "- $line" }
$md += ''
$md += '## Task Snapshot'
$md += '| Group | Task | Status | Depends On |'
$md += '|---|---|---|---|'
foreach ($g in @('P','Q','R')) {
    foreach ($row in $summary.groups[$g]) {
        $md += "| $g | $($row.id) | $($row.status) | $($row.depends_on) |"
    }
}
$mdContent = $md -join "`r`n"
Write-ContentIfChanged -Path $mdFullPath -Content $mdContent

$summary | ConvertTo-Json -Depth 8

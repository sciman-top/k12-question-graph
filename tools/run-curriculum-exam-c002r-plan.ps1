param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabaseUser = 'postgres',
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PlanPath = 'configs\domain-assets\curriculum-exam-c002r-revision.sample.json',
    [string] $ReportPath = 'docs\evidence\cek024-curriculum-exam-c002r-plan.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Write-Json([object] $Value, [string] $Path) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 60) + "`n"), [Text.UTF8Encoding]::new($false))
}

. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword $DatabasePassword
Assert-True (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'database password required'
$env:PGPASSWORD = $DatabasePassword
$connection = "host=$DatabaseHost port=$DatabasePort dbname=$DatabaseName user=$DatabaseUser"
$plan = [IO.Path]::GetFullPath((Join-Path $repoRoot $PlanPath))
$report = [IO.Path]::GetFullPath((Join-Path $repoRoot $ReportPath))
$tmpRoot = Join-Path $repoRoot 'tmp\cek024'
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

Push-Location $repoRoot
try {
    python -m unittest tests.workers.test_curriculum_exam_c002r_plan
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-24 unit tests failed'
    python -m py_compile tools\curriculum_exam_c002r_plan.py
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-24 Python compile failed'
    python tools\curriculum_exam_c002r_plan.py --connection-string $connection `
        --plan $plan --report $report | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'CEK-24 plan generation failed'

    $legacyReportPath = 'tmp\cek024\existing-c002r-contract.json'
    $legacy = pwsh -NoProfile -ExecutionPolicy Bypass -File tools\run-c002r-versioned-revision-contract.ps1 `
        -ReportPath $legacyReportPath | ConvertFrom-Json
    Assert-True ($legacy.status -eq 'pass') 'existing C002R contract regressed'

    $evidence = Get-Content -Raw -LiteralPath $report | ConvertFrom-Json
    $revision = Get-Content -Raw -LiteralPath $plan | ConvertFrom-Json
    Assert-True ($evidence.status -eq 'pass' -and $evidence.planningSnapshotUnchanged -and -not $evidence.databaseWrite) 'CEK-24 read-only planning snapshot evidence failed'
    Assert-True ($evidence.activeBaseline.activeAssetCount -eq 452) 'CEK-24 active baseline count mismatch'
    Assert-True ($evidence.candidateCounts -eq 297) 'CEK-24 candidate count mismatch'
    Assert-True ($evidence.mappingCount -eq 94) 'CEK-24 mapping count mismatch'
    Assert-True ($evidence.profileCount -eq 24) 'CEK-24 profile count mismatch'
    Assert-True (@($evidence.impacts).Count -eq 6) 'CEK-24 impact coverage mismatch'
    Assert-True ($revision.candidateVersion.noInPlaceActiveEdit) 'CEK-24 in-place edit guard failed'
    Assert-True (-not $revision.historicalReferencePolicy.silentRewriteAllowed) 'CEK-24 historical rewrite guard failed'
    Assert-True ($revision.errorPatternPlan.status -eq 'blocked_no_persisted_candidates') 'CEK-24 hid CEK-20 persistence gap'

    $evidence | Add-Member -NotePropertyName existingC002RContract -NotePropertyValue ([ordered]@{
        status = $legacy.status
        planId = $legacy.planId
        report = 'tmp/cek024/existing-c002r-contract.json'
    }) -Force
    $evidence | Add-Member -NotePropertyName fullGate -NotePropertyValue ([ordered]@{
        status = 'gate_na'
        reason = 'stateful Release requires current explicit authorization because it uses PostgreSQL and isolated backup/restore rehearsal'
        alternative_verification = 'CEK-24 unit tests, read-only live planning-input snapshot parity, existing C002R contract, roadmap/reference guards, and static hotspot audit'
        evidence_link = 'docs/evidence/cek024-curriculum-exam-c002r-plan.json'
        expires_at = 'CEK-34'
        recovery_condition = 'obtain current-task authorization and run tools/run-verification.ps1 -Profile Release -AuthorizeStateful at CEK-34'
    }) -Force
    $evidence | Add-Member -NotePropertyName rollback -NotePropertyValue 'Delete only the generated plan/report; CEK-24 performs no database, migration, candidate, question, or active write.' -Force
    Write-Json $evidence $report
    $evidence | ConvertTo-Json -Depth 60
}
finally {
    Pop-Location
}

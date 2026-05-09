param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [string] $FixtureManifestPath = 'tests/e2e/s012a-proxy-fixture-pack.json',
    [string] $ReportPath = 'docs/evidence/20260509-s012b-non-site-e2e-rehearsal-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword
if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for S012B non-site E2E rehearsal'
}

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Convert-ToRelative([string] $Path) {
    return [System.IO.Path]::GetRelativePath($repoRoot, (Resolve-Path -LiteralPath $Path).Path).Replace('\', '/')
}

function Invoke-ScalarSql([string] $Sql) {
    $psql = Join-Path $PgBin 'psql.exe'
    $value = & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -v ON_ERROR_STOP=1 -c $Sql
    if ($LASTEXITCODE -ne 0) { throw "S012B SQL failed: $Sql" }
    return (($value | Select-Object -First 1) ?? '').Trim()
}

function Get-DatabaseCounts {
    $json = Invoke-ScalarSql @"
select jsonb_build_object(
  'source_documents', (select count(*) from source_documents),
  'question_items', (select count(*) from question_items),
  'knowledge_mappings', (select count(*) from knowledge_mappings),
  'paper_baskets', (select count(*) from paper_baskets),
  'paper_basket_items', (select count(*) from paper_basket_items),
  'assessments', (select count(*) from assessments),
  'score_records', (select count(*) from score_records),
  'item_scores', (select count(*) from item_scores)
)::text;
"@
    return ($json | ConvertFrom-Json)
}

function Compare-DatabaseCounts($Before, $After) {
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($name in $Before.PSObject.Properties.Name) {
        $beforeValue = [int]$Before.$name
        $afterValue = [int]$After.$name
        $rows.Add([ordered]@{
            table = $name
            before = $beforeValue
            after = $afterValue
            delta = $afterValue - $beforeValue
        })
    }
    return $rows
}

function Format-CommandForEvidence([string] $Command, [string[]] $Arguments) {
    $text = "$Command $($Arguments -join ' ')"
    if (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) {
        $text = $text.Replace($DatabasePassword, '<redacted>')
    }
    return $text
}

function Invoke-RehearsalStep {
    param(
        [string] $Name,
        [string] $WorkflowStep,
        [string] $Command,
        [string[]] $Arguments,
        [string[]] $TakeoverPoints,
        [string] $RollbackAction,
        [string] $EvidencePath
    )

    $started = Get-Date
    $output = & $Command @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $durationMs = [int]((Get-Date) - $started).TotalMilliseconds
    if ($exitCode -ne 0) {
        throw "S012B step failed: $Name exit=$exitCode output=$($output -join "`n")"
    }

    $evidenceExists = $true
    if (-not [string]::IsNullOrWhiteSpace($EvidencePath)) {
        $evidenceFullPath = Join-Path $repoRoot $EvidencePath
        $evidenceExists = Test-Path -LiteralPath $evidenceFullPath
        Assert-True $evidenceExists "S012B step evidence missing for ${Name}: $EvidencePath"
    }

    return [ordered]@{
        name = $Name
        workflowStep = $WorkflowStep
        status = 'pass'
        durationMs = $durationMs
        command = Format-CommandForEvidence -Command $Command -Arguments $Arguments
        evidencePath = $EvidencePath
        evidenceExists = $evidenceExists
        takeoverPoints = $TakeoverPoints
        rollbackAction = $RollbackAction
    }
}

$reportFullPath = Join-Path $repoRoot $ReportPath
$fixtureFullPath = Join-Path $repoRoot $FixtureManifestPath
Assert-True (Test-Path -LiteralPath $fixtureFullPath) "S012B fixture manifest missing: $FixtureManifestPath"

Push-Location $repoRoot
try {
    $overallStarted = Get-Date
    $manifest = Get-Content -Raw -LiteralPath $fixtureFullPath | ConvertFrom-Json -Depth 20
    Assert-True ([string]$manifest.schemaVersion -eq 's012a-e2e-proxy-fixture-pack.v1') 'S012B requires the S012A fixture pack schema'
    Assert-True ([bool]$manifest.s012bAdmission.requiresRollbackEvidence) 'S012A manifest must require rollback evidence before S012B'
    Assert-True ([bool]$manifest.s012bAdmission.requiresBackupRestoreEvidence) 'S012A manifest must require backup restore evidence before S012B'

    $preBackupJson = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'backup.ps1') -BackupRoot 'tmp/s012b/pre-run-backup' -FileStoreRoot $FileStoreRoot -PgBin $PgBin -DatabaseName $DatabaseName -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabaseUser $DatabaseUser
    if ($LASTEXITCODE -ne 0) { throw 'S012B pre-run backup failed' }
    $preBackup = $preBackupJson | ConvertFrom-Json
    & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'verify-backup.ps1') -ManifestPath $preBackup.manifest | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'S012B pre-run backup verify failed' }

    $beforeCounts = Get-DatabaseCounts
    $steps = New-Object System.Collections.Generic.List[object]

    $commonDbArgs = @(
        '-DatabaseName', $DatabaseName,
        '-DatabaseUser', $DatabaseUser,
        '-DatabaseHost', $DatabaseHost,
        '-DatabasePort', "$DatabasePort",
        '-DatabasePassword', $DatabasePassword
    )

    $steps.Add((Invoke-RehearsalStep -Name 'S012A fixture pack admission' -WorkflowStep 'admission' -Command 'pwsh' -Arguments @('-NoProfile','-ExecutionPolicy','Bypass','-File','tools/run-s012a-e2e-proxy-fixture-pack.ps1') -EvidencePath 'docs/evidence/20260508-s012a-e2e-proxy-fixture-pack-report.json' -TakeoverPoints @('replace synthetic localPath with authorized or anonymized school materials before site use') -RollbackAction 'remove S012A fixture pack and evidence report'))

    $steps.Add((Invoke-RehearsalStep -Name 'P1 import cut review save source proxy' -WorkflowStep 'import_cut_review_save' -Command 'pwsh' -Arguments (@('-NoProfile','-ExecutionPolicy','Bypass','-File','tools/run-p1-proxy-scenario.ps1') + $commonDbArgs + @('-FileStoreRoot', $FileStoreRoot)) -EvidencePath '' -TakeoverPoints @('merge cross-page segments','split over-cut segment','associate shared image','manual box source region','rerun adapter when source is fixed') -RollbackAction 'delete generated synthetic source/question rows or restore the S012B pre-run backup manifest'))

    $steps.Add((Invoke-RehearsalStep -Name 'S007C tagging writeback undo' -WorkflowStep 'tagging' -Command 'pwsh' -Arguments (@('-NoProfile','-ExecutionPolicy','Bypass','-File','tools/run-s007c-teacher-confirm-writeback-smoke.ps1') + $commonDbArgs + @('-ApiPort','5312')) -EvidencePath 'docs/evidence/20260506-s007c-teacher-confirm-writeback-smoke-report.json' -TakeoverPoints @('teacher modifies AI suggestion before confirm','undo-confirm restores question count') -RollbackAction 'undo-confirm removes generated question and mapping; otherwise restore the S012B pre-run backup manifest'))

    $steps.Add((Invoke-RehearsalStep -Name 'S006B manual takeover workbench' -WorkflowStep 'review_save' -Command 'pwsh' -Arguments (@('-NoProfile','-ExecutionPolicy','Bypass','-File','tools/run-s006b-manual-takeover-smoke.ps1') + $commonDbArgs + @('-ApiPort','5313')) -EvidencePath 'docs/evidence/20260506-s006b-manual-takeover-smoke-report.json' -TakeoverPoints @('merge','split','associate','save_question') -RollbackAction 'remove generated review candidates/questions or restore the S012B pre-run backup manifest'))

    $steps.Add((Invoke-RehearsalStep -Name 'S009B blueprint review' -WorkflowStep 'paper' -Command 'pwsh' -Arguments (@('-NoProfile','-ExecutionPolicy','Bypass','-File','tools/run-s009b-blueprint-review-workflow-smoke.ps1') + $commonDbArgs + @('-ApiPort','5314','-PgBin',$PgBin)) -EvidencePath 'docs/evidence/20260507-s009b-blueprint-review-workflow-smoke-report.json' -TakeoverPoints @('teacher reviews blueprint before taking questions','delete draft basket if constraints are wrong') -RollbackAction 'delete created paper_blueprint_reviews and draft basket rows or restore the S012B pre-run backup manifest'))

    $steps.Add((Invoke-RehearsalStep -Name 'S010B word pdf artifact chain' -WorkflowStep 'export' -Command 'pwsh' -Arguments (@('-NoProfile','-ExecutionPolicy','Bypass','-File','tools/run-s010b-word-pdf-artifact-chain-smoke.ps1') + $commonDbArgs + @('-ApiPort','5315','-PgBin',$PgBin)) -EvidencePath 'docs/evidence/20260508-s010b-word-pdf-artifact-chain-report.json' -TakeoverPoints @('export preflight blocks missing formula image source assets','manifest hash verifies generated artifacts') -RollbackAction 'delete tmp/s010b-paper-artifacts or restore the S012B pre-run backup manifest'))

    $steps.Add((Invoke-RehearsalStep -Name 'S011A score import' -WorkflowStep 'score' -Command 'pwsh' -Arguments (@('-NoProfile','-ExecutionPolicy','Bypass','-File','tools/run-s011a-score-import-api-smoke.ps1') + $commonDbArgs + @('-ApiPort','5316','-PgBin',$PgBin)) -EvidencePath 'docs/evidence/20260508-s011a-score-import-api-smoke-report.json' -TakeoverPoints @('invalid rows remain centralized for teacher correction','no student PII accepted by smoke fixture') -RollbackAction 'remove synthetic assessment/score rows or restore the S012B pre-run backup manifest'))

    $steps.Add((Invoke-RehearsalStep -Name 'S011B item score mapping preview' -WorkflowStep 'score_mapping' -Command 'pwsh' -Arguments (@('-NoProfile','-ExecutionPolicy','Bypass','-File','tools/run-s011b-item-score-mapping-ui-api-smoke.ps1') + $commonDbArgs + @('-ApiPort','5317','-PgBin',$PgBin)) -EvidencePath 'docs/evidence/20260508-s011b-item-score-mapping-ui-api-report.json' -TakeoverPoints @('unclear item-to-question mappings are centralized before report export') -RollbackAction 'remove synthetic mapping fixture rows or restore the S012B pre-run backup manifest'))

    $steps.Add((Invoke-RehearsalStep -Name 'S011C commentary export' -WorkflowStep 'analysis' -Command 'pwsh' -Arguments (@('-NoProfile','-ExecutionPolicy','Bypass','-File','tools/run-s011c-commentary-report-export-smoke.ps1') + $commonDbArgs + @('-ApiPort','5318','-PgBin',$PgBin)) -EvidencePath 'docs/evidence/20260508-s011c-commentary-report-export-report.json' -TakeoverPoints @('report generation blocks if item score mapping is unclear','AI draft text remains disabled in smoke') -RollbackAction 'remove synthetic score/report fixture rows or restore the S012B pre-run backup manifest'))

    $steps.Add((Invoke-RehearsalStep -Name 'O003 backup restore drill' -WorkflowStep 'backup_restore' -Command 'pwsh' -Arguments @('-NoProfile','-ExecutionPolicy','Bypass','-File','tools/run-o003-recovery-drill-contract.ps1','-BackupRoot','tmp/s012b/o003-backup-root','-FileStoreRoot',$FileStoreRoot,'-PgBin',$PgBin,'-DatabaseName',$DatabaseName,'-DatabaseHost',$DatabaseHost,'-DatabasePort',"$DatabasePort",'-DatabaseUser',$DatabaseUser,'-ReportPath','docs/evidence/20260509-s012b-o003-recovery-drill-report.json') -EvidencePath 'docs/evidence/20260509-s012b-o003-recovery-drill-report.json' -TakeoverPoints @('restore plan generated with pg_restore -l','schema-only restore extracted in isolated directory') -RollbackAction 'delete tmp/s012b/o003-backup-root and tmp/o003 restore-drill directories'))

    $afterCounts = Get-DatabaseCounts
    $databaseChanges = Compare-DatabaseCounts -Before $beforeCounts -After $afterCounts
    $overallDurationMs = [int]((Get-Date) - $overallStarted).TotalMilliseconds

    $report = [ordered]@{
        status = 'pass'
        taskId = 'S012B'
        checkedAt = (Get-Date).ToString('s')
        mode = 'non_site_e2e_rehearsal'
        productionEligible = $false
        realStudentDataUsed = $false
        fixtureManifest = $FixtureManifestPath
        preRunBackup = [ordered]@{
            manifest = $preBackup.manifest
            verified = $true
            rollbackCommand = "pwsh -NoProfile -ExecutionPolicy Bypass -File tools/restore-backup.ps1 -ManifestPath '$($preBackup.manifest)'"
        }
        elapsed = [ordered]@{
            totalMs = $overallDurationMs
            totalMinutes = [decimal]::Round($overallDurationMs / 60000, 2)
        }
        workflowSteps = $steps
        databaseChanges = $databaseChanges
        failureTakeoverPoints = @(
            'keep original upload and adapter diagnostics',
            'manual box source region',
            'merge or split affected question segments',
            'skip bad page and rerun adapter after source fix',
            'block commentary export until item score mappings are clear',
            'restore from pre-run backup manifest if rehearsal data must be removed'
        )
        rollback = [ordered]@{
            code = 'git revert the S012B commit to remove the orchestration script, gate entry, task status, and evidence files'
            data = 'restore from preRunBackup.manifest if synthetic rehearsal rows or file-store artifacts must be removed'
            tempArtifacts = @('tmp/s012b','tmp/o003','tmp/s010b-paper-artifacts')
        }
        conclusion = 'S012B ran a non-site proxy E2E rehearsal across import, cut, review, tagging, save, paper, export, score, analysis, and backup/restore evidence. This is still not a live teacher/site validation.'
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 12
}
finally {
    Pop-Location
}

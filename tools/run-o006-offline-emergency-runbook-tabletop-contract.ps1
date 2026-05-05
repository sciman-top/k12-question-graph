param(
    [string] $Report = 'docs/evidence/o006-offline-emergency-runbook-tabletop-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

Push-Location $repoRoot
try {
    $runbook = Join-Path $repoRoot 'runbooks/WinPE_EmergencyRecovery.md'
    Assert-Condition (Test-Path -LiteralPath $runbook) 'missing runbook: runbooks/WinPE_EmergencyRecovery.md'

    $runbookText = Get-Content -LiteralPath $runbook -Raw
    foreach ($pattern in @(
        'run-g003-winpe-emergency-copy-contract.ps1',
        'KQG_EmergencyCopy.cmd',
        'verify-backup.ps1',
        'restore.ps1',
        'copy-only',
        '不要'
    )) {
        Assert-Condition ($runbookText.Contains($pattern)) "runbook missing required instruction: $pattern"
    }

    $g003Json = & pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-g003-winpe-emergency-copy-contract.ps1
    Assert-Condition ($LASTEXITCODE -eq 0) 'G003 contract failed inside O006'
    $g003 = $g003Json | ConvertFrom-Json

    $backupJson = & pwsh -NoProfile -ExecutionPolicy Bypass -File tools/backup.ps1
    Assert-Condition ($LASTEXITCODE -eq 0) 'backup.ps1 failed inside O006'
    $backup = $backupJson | ConvertFrom-Json

    $verifyJson = & pwsh -NoProfile -ExecutionPolicy Bypass -File tools/verify-backup.ps1 -ManifestPath $backup.manifest
    Assert-Condition ($LASTEXITCODE -eq 0) 'verify-backup.ps1 failed inside O006'
    $verify = $verifyJson | ConvertFrom-Json
    Assert-Condition ($verify.status -eq 'ok') 'backup verification must be ok for O006 tabletop'

    $restoreDryRunJson = & pwsh -NoProfile -ExecutionPolicy Bypass -File tools/restore.ps1 -ManifestPath $backup.manifest -ApplyDatabase -ApplyFileStore -ApplyConfigs
    Assert-Condition ($LASTEXITCODE -eq 0) 'restore.ps1 dry-run failed inside O006'
    $restoreDryRun = $restoreDryRunJson | ConvertFrom-Json
    Assert-Condition ($restoreDryRun.mode -eq 'dry_run') 'restore.ps1 must default to dry_run'

    $tabletopScenarios = @(
        [ordered]@{
            scenario = 'windows_unbootable'
            trigger = 'Windows cannot boot'
            operator = 'admin'
            expectedAction = 'boot WinPE and run KQG_EmergencyCopy.cmd'
            expectedEvidence = 'recovery-media-manifest + copy log + backup manifest'
            fallback = 'manual copy data root and backup root, then verify-backup and restore dry-run'
            rollback = 'do not run mirror-delete; keep destination content intact'
        },
        [ordered]@{
            scenario = 'backup_manifest_hash_mismatch'
            trigger = 'verify-backup returns hash mismatch'
            operator = 'admin'
            expectedAction = 'stop restore apply and collect mismatch file list'
            expectedEvidence = 'verify-backup error output + previous valid manifest reference'
            fallback = 'switch to last known good manifest and rerun verify-backup'
            rollback = 'do not overwrite recovered target until manifest passes'
        },
        [ordered]@{
            scenario = 'restore_apply_failure'
            trigger = 'pg_restore exits non-zero during apply'
            operator = 'admin'
            expectedAction = 'keep system read-only and use previous backup manifest for rollback'
            expectedEvidence = 'pg_restore stderr + attempted dump path + database target'
            fallback = 'rerun restore in dry-run and isolate failing object list'
            rollback = 'restore from previous validated manifest before retry'
        }
    )

    $reportObject = [ordered]@{
        status = 'pass'
        task = 'O006'
        mode = 'draft_test'
        productionEligible = $false
        dependencies = [ordered]@{
            g003 = 'pass'
            o003 = 'already_completed'
        }
        runbook = [ordered]@{
            path = 'runbooks/WinPE_EmergencyRecovery.md'
            requiredInstructionsChecked = $true
        }
        tabletop = [ordered]@{
            scenarios = $tabletopScenarios
            scenarioCount = $tabletopScenarios.Count
        }
        evidenceChain = [ordered]@{
            g003Report = [string]$g003.generatedManifest
            backupManifest = [string]$backup.manifest
            verifyStatus = [string]$verify.status
            restoreDryRunMode = [string]$restoreDryRun.mode
        }
        rollback = [ordered]@{
            tempCleanup = @(
                "Remove-Item -LiteralPath '$($backup.backupDir)' -Recurse -Force"
            )
            policy = 'if tabletop reveals unresolved blocker, keep O006 as todo and block P001'
        }
        summaryChinese = [ordered]@{
            title = 'O006 离线应急手册与演练报告'
            result = '通过'
            boundary = '完成 runbook + tabletop + backup/verify + restore dry-run 证据链；未执行生产恢复 apply。'
        }
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $Report) -Force | Out-Null
    $json = $reportObject | ConvertTo-Json -Depth 10
    $json | Set-Content -LiteralPath $Report -Encoding UTF8
    $json
}
finally {
    Pop-Location
}

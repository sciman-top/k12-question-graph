param(
    [Parameter(Mandatory)]
    [string] $ImportKey,

    [Parameter(Mandatory)]
    [string] $MaterialBatchKey,

    [string] $EvidencePrefix = 'domain-asset-activation',
    [int] $ExpectedSourceDocumentCount = 0,
    [string] $DecisionFile = '',
    [switch] $GenerateDecisionFile,
    [switch] $ApplyReview,
    [switch] $ApplyActivation,
    [switch] $SkipBackupBeforeActivation,
    [string] $BackupManifest = '',
    [string] $BackupRoot = 'D:\KQG_Backups',
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $ConnectionString = $env:KQG_CONNECTION_STRING
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$evidenceRoot = Join-Path $repoRoot 'docs\evidence'
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null

function Get-EvidencePath([string] $Suffix) {
    return Join-Path $evidenceRoot "$EvidencePrefix-$Suffix"
}

function Read-JsonFile([string] $Path) {
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Invoke-Step([string] $Name, [scriptblock] $Script) {
    $started = Get-Date
    & $Script
    [ordered]@{
        name = $Name
        status = 'pass'
        durationMs = [int]((Get-Date) - $started).TotalMilliseconds
    }
}

Push-Location $repoRoot
try {
    $steps = New-Object System.Collections.Generic.List[object]
    $readinessBeforePath = Get-EvidencePath 'readiness-before.json'
    $reviewApplyPath = Get-EvidencePath 'review-apply.json'
    $readinessAfterReviewPath = Get-EvidencePath 'readiness-after-review.json'
    $activeDryRunBeforePath = Get-EvidencePath 'active-dry-run-before.json'
    $activeApplyPath = Get-EvidencePath 'active-apply.json'
    $activeDryRunAfterPath = Get-EvidencePath 'active-dry-run-after.json'
    $summaryPath = Get-EvidencePath 'summary.json'

    $commonDbArgs = @{
        DatabaseName = $DatabaseName
        DatabaseUser = $DatabaseUser
        DatabaseHost = $DatabaseHost
        DatabasePort = $DatabasePort
        DatabasePassword = $DatabasePassword
        ConnectionString = $ConnectionString
    }

    $steps.Add((Invoke-Step 'readiness before review/activation' {
        .\tools\run-c002l-candidate-review-readiness.ps1 @commonDbArgs -ImportKey $ImportKey -MaterialBatchKey $MaterialBatchKey -ReportPath $readinessBeforePath -ExpectedSourceDocumentCount $ExpectedSourceDocumentCount | Write-Host
    }))

    if ($GenerateDecisionFile -and [string]::IsNullOrWhiteSpace($DecisionFile)) {
        $DecisionFile = Get-EvidencePath 'review-decisions.generated.json'
        $steps.Add((Invoke-Step 'generate review decisions' {
            .\tools\generate-c002-review-decisions.ps1 @commonDbArgs -ImportKey $ImportKey -MaterialBatchKey $MaterialBatchKey -Output $DecisionFile -ExpectedSourceDocumentCount $ExpectedSourceDocumentCount | Write-Host
        }))
    }

    if ($ApplyReview) {
        if ([string]::IsNullOrWhiteSpace($DecisionFile)) {
            throw 'DecisionFile is required when ApplyReview is set. Use -GenerateDecisionFile or pass -DecisionFile.'
        }

        $steps.Add((Invoke-Step 'apply review decisions' {
            .\tools\run-c002m-candidate-review-apply-contract.ps1 @commonDbArgs -ImportKey $ImportKey -DecisionFile $DecisionFile -ReportPath $reviewApplyPath -Apply | Write-Host
        }))
    }

    $steps.Add((Invoke-Step 'readiness after review' {
        .\tools\run-c002l-candidate-review-readiness.ps1 @commonDbArgs -ImportKey $ImportKey -MaterialBatchKey $MaterialBatchKey -ReportPath $readinessAfterReviewPath -ExpectedSourceDocumentCount $ExpectedSourceDocumentCount | Write-Host
    }))

    $steps.Add((Invoke-Step 'active switch dry-run before apply' {
        .\tools\run-c002t-active-switch.ps1 @commonDbArgs -ImportKey $ImportKey -MaterialBatchKey $MaterialBatchKey -ReportPath $activeDryRunBeforePath -ExpectedSourceDocumentCount $ExpectedSourceDocumentCount | Write-Host
    }))

    if ($ApplyActivation) {
        if ([string]::IsNullOrWhiteSpace($BackupManifest) -and -not $SkipBackupBeforeActivation) {
            $steps.Add((Invoke-Step 'backup before activation' {
                $backup = .\tools\backup.ps1 -BackupRoot $BackupRoot -PgBin $PgBin -DatabaseName $DatabaseName -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabaseUser $DatabaseUser | ConvertFrom-Json
                .\tools\verify-backup.ps1 -ManifestPath $backup.manifest | Write-Host
                $script:BackupManifest = [string]$backup.manifest
            }))
        }

        if ([string]::IsNullOrWhiteSpace($BackupManifest)) {
            throw 'BackupManifest is required for ApplyActivation unless backup creation succeeded in this run.'
        }

        $steps.Add((Invoke-Step 'apply active switch' {
            .\tools\run-c002t-active-switch.ps1 @commonDbArgs -ImportKey $ImportKey -MaterialBatchKey $MaterialBatchKey -BackupManifest $BackupManifest -ReportPath $activeApplyPath -ExpectedSourceDocumentCount $ExpectedSourceDocumentCount -Apply | Write-Host
        }))
    }

    $steps.Add((Invoke-Step 'active switch dry-run after pipeline' {
        .\tools\run-c002t-active-switch.ps1 @commonDbArgs -ImportKey $ImportKey -MaterialBatchKey $MaterialBatchKey -ReportPath $activeDryRunAfterPath -ExpectedSourceDocumentCount $ExpectedSourceDocumentCount | Write-Host
    }))

    $finalReadiness = Read-JsonFile $readinessAfterReviewPath
    $finalActivation = Read-JsonFile $activeDryRunAfterPath
    $summary = [ordered]@{
        status = if ($finalActivation.status -eq 'pass') { 'pass' } else { 'blocked' }
        task = 'domain_asset_activation_pipeline'
        generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        importKey = $ImportKey
        materialBatchKey = $MaterialBatchKey
        evidencePrefix = $EvidencePrefix
        applyReview = [bool]$ApplyReview
        applyActivation = [bool]$ApplyActivation
        backupManifest = $BackupManifest
        finalLifecycle = $finalReadiness.activationState.lifecycle
        formalActivationComplete = [bool]$finalReadiness.activationState.formalActivationComplete
        activeAssets = [int]$finalActivation.after.activeAssets
        totalAssets = [int]$finalActivation.after.totalAssets
        blockers = @($finalActivation.blockers)
        evidence = [ordered]@{
            readinessBefore = [System.IO.Path]::GetRelativePath($repoRoot, $readinessBeforePath).Replace('\', '/')
            reviewDecisions = if ([string]::IsNullOrWhiteSpace($DecisionFile)) { '' } else { [System.IO.Path]::GetRelativePath($repoRoot, $DecisionFile).Replace('\', '/') }
            reviewApply = if ($ApplyReview) { [System.IO.Path]::GetRelativePath($repoRoot, $reviewApplyPath).Replace('\', '/') } else { '' }
            readinessAfterReview = [System.IO.Path]::GetRelativePath($repoRoot, $readinessAfterReviewPath).Replace('\', '/')
            activeDryRunBefore = [System.IO.Path]::GetRelativePath($repoRoot, $activeDryRunBeforePath).Replace('\', '/')
            activeApply = if ($ApplyActivation) { [System.IO.Path]::GetRelativePath($repoRoot, $activeApplyPath).Replace('\', '/') } else { '' }
            activeDryRunAfter = [System.IO.Path]::GetRelativePath($repoRoot, $activeDryRunAfterPath).Replace('\', '/')
        }
        steps = $steps
    }

    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    $summary | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}

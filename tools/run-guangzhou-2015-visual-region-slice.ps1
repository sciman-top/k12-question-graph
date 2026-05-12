param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [string] $Output = 'docs\evidence\20260512-guangzhou-2015-visual-region-slice-report.json',
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'
$env:PYTHONIOENCODING = 'utf-8'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for Guangzhou 2015 visual region slice'
}

function Assert-True {
    param(
        [bool] $Condition,
        [string] $Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

Push-Location $repoRoot
try {
    $args = @(
        'tools\guangzhou_2015_visual_region.py',
        '--host', $DatabaseHost,
        '--port', ([string] $DatabasePort),
        '--database', $DatabaseName,
        '--user', $DatabaseUser,
        '--password', $DatabasePassword,
        '--file-root', $FileStoreRoot,
        '--output', $Output
    )
    if ($Apply) {
        $args += '--apply'
    }

    & python @args
    if ($LASTEXITCODE -ne 0) {
        throw 'Guangzhou 2015 visual region slice failed'
    }

    $reportPath = Join-Path $repoRoot $Output
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    if ($Apply) {
        Assert-True ($report.status -eq 'pass') "expected pass status after apply, got $($report.status)"
    }
    else {
        Assert-True ($report.status -eq 'dry_run_pass') "expected dry_run_pass status, got $($report.status)"
    }

    $expectedNumbers = @(19, 20, 21, 22, 23, 24)
    $actualNumbers = @($report.after.questionNumbers | ForEach-Object { [int] $_ })
    Assert-True ($report.after.questionCount -eq 6) "expected 6 visual question items, got $($report.after.questionCount)"
    Assert-True ((Compare-Object -ReferenceObject $expectedNumbers -DifferenceObject $actualNumbers).Count -eq 0) "expected visual questions 19-24, got $($actualNumbers -join ',')"
    Assert-True ($report.after.sourceRegionCount -ge 17) "expected at least 17 visual source regions, got $($report.after.sourceRegionCount)"
    Assert-True ($report.after.questionAssetCount -ge 5) "expected at least 5 visual question assets, got $($report.after.questionAssetCount)"
    Assert-True ($report.after.cutCandidateCount -eq 6) "expected 6 visual cut candidates, got $($report.after.cutCandidateCount)"
    Assert-True ($report.after.openReviewQueueCount -eq 6) "expected 6 open review queue items, got $($report.after.openReviewQueueCount)"
    Assert-True ([bool] $report.verification.questionRangeComplete) 'visual question range is incomplete'
    Assert-True ([bool] $report.verification.allHaveAnswers) 'not all visual questions have answer evidence'
    Assert-True ([bool] $report.verification.allHaveKnowledgeTags) 'not all visual questions have knowledge tag evidence'
    Assert-True ([bool] $report.verification.allHaveVisualRegionStatus) 'not all visual questions have visual region status'
    Assert-True ([bool] $report.verification.hasQuestionAssetsForVisualQuestions) 'visual question assets are incomplete'
    Assert-True ([bool] $report.verification.noExternalAiCalls) 'REAL002 must not call external AI'
}
finally {
    Pop-Location
}

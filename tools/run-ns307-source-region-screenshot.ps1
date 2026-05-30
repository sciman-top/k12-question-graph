param(
    [string] $ReportPath = 'docs/evidence/20260530-ns307-source-region-screenshot-report.json',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

Push-Location $repoRoot
try {
    $s006cOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File 'tools/run-s006c-source-review-closure-smoke.ps1' `
        -DatabaseName $DatabaseName `
        -DatabaseUser $DatabaseUser `
        -DatabaseHost $DatabaseHost `
        -DatabasePort $DatabasePort `
        -DatabasePassword $DatabasePassword `
        -FileStoreRoot $FileStoreRoot 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) 'S006C source review closure dependency failed'

    $s006cPath = 'docs/evidence/20260506-s006c-source-review-closure-smoke-report.json'
    Assert-Condition (Test-Path -LiteralPath $s006cPath) "missing S006C report: $s006cPath"
    $s006c = Get-Content -LiteralPath $s006cPath -Raw | ConvertFrom-Json

    Assert-Condition ($s006c.status -eq 'pass') 'S006C report did not pass'
    Assert-Condition ([int]$s006c.sourceReview.sourceRegionCount -ge 1) 'NS307 source region path was not returned'
    Assert-Condition ([int]$s006c.fallbackCases.missingScreenshotStatus -eq 409) 'NS307 missing screenshot must fail explicitly with 409'
    Assert-Condition ([int]$s006c.fallbackCases.missingRegionCount -eq 0) 'NS307 no-region case should remain empty'
    Assert-Condition ([int]$s006c.fallbackCases.notFoundStatus -eq 404) 'NS307 inaccessible question must remain 404'

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS307'
        checkedAt = (Get-Date).ToString('s')
        mode = 's006c_source_review_screenshot_path_wrapper'
        productionEligible = $false
        dependency = [ordered]@{
            task = 'S006C'
            report = $s006cPath
            questionId = [string]$s006c.sourceReview.questionId
        }
        sourceRegion = [ordered]@{
            sourceRegionCount = [int]$s006c.sourceReview.sourceRegionCount
            screenshotPathAccessibleBeforeRemoval = $true
            missingScreenshotStatus = [int]$s006c.fallbackCases.missingScreenshotStatus
            missingRegionCount = [int]$s006c.fallbackCases.missingRegionCount
            notFoundStatus = [int]$s006c.fallbackCases.notFoundStatus
        }
        acceptance = [ordered]@{
            sourceRegionScreenshotPathReturned = $true
            missingScreenshotFailsExplicitly = $true
            noRegionQuestionDoesNotInventSource = $true
            inaccessibleQuestionFailsExplicitly = $true
        }
        boundary = 'NS307 proves saved questions can return SourceRegion screenshot paths and missing screenshots fail explicitly. It uses draft/test smoke data and does not claim real Guangzhou closure.'
        next = 'NS308 can continue import quality report contract after DOCX/PDF/OCR/SourceRegion evidence.'
        rollback = 'S006C writes draft/test rows; delete the reported question/source rows or restore the DB/FileStore snapshot if a clean state is required.'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 6
}
finally {
    Pop-Location
}

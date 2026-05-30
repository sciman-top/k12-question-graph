param(
    [string] $ReportPath = 'docs/evidence/20260530-ns404-question-asset-report.json',
    [string] $SourceReportPath = 'docs/evidence/20260530-ns404-real008-source-report.json',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [int] $ApiPort = 0,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Read-Json([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing report: $Path"
    return Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
}

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse('127.0.0.1'), 0)
    try {
        $listener.Start()
        return $listener.LocalEndpoint.Port
    }
    finally {
        $listener.Stop()
    }
}

Push-Location $repoRoot
try {
    $ns403 = Read-Json 'docs/evidence/20260530-ns403-review-workbench-ui-report.json'
    Assert-Condition ($ns403.status -eq 'pass') 'NS404 dependency NS403 report did not pass'
    Assert-Condition ([bool]$ns403.acceptance.teacherCanAssociateAsset) 'NS404 requires NS403 teacher asset association UI evidence'

    $buildOutput = dotnet build 'apps/api/K12QuestionGraph.Api.csproj' -c Release 2>&1
    Assert-Condition ($LASTEXITCODE -eq 0) 'dotnet build failed before NS404 question asset smoke'

    if ($ApiPort -le 0) {
        $ApiPort = Get-FreeTcpPort
    }

    $real008Output = & pwsh -NoProfile -ExecutionPolicy Bypass -File 'tools/run-real008-question-asset-smoke.ps1' `
        -DatabaseName $DatabaseName `
        -DatabaseUser $DatabaseUser `
        -DatabaseHost $DatabaseHost `
        -DatabasePort $DatabasePort `
        -DatabasePassword $DatabasePassword `
        -FileStoreRoot $FileStoreRoot `
        -ApiPort $ApiPort `
        -PgBin $PgBin `
        -ReportPath $SourceReportPath 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "REAL008 question asset dependency failed: $real008Output"

    $real008 = Read-Json $SourceReportPath
    Assert-Condition ($real008.status -eq 'pass') 'REAL008 source report did not pass'
    Assert-Condition ($real008.task -eq 'REAL008') 'NS404 source report must be REAL008'
    Assert-Condition ([bool]$real008.cardProbe.beforeAssociation.hasImage -eq $false) 'NS404 must prove card hasImage is false before association'
    Assert-Condition ([int]$real008.cardProbe.beforeAssociation.assetCount -eq 0) 'NS404 must prove card assetCount is 0 before association'
    Assert-Condition ([int]$real008.cardProbe.beforeAssociation.sourceScreenshotCount -ge 1) 'NS404 must prove source screenshots alone do not create card images'
    Assert-Condition ([bool]$real008.cardProbe.afterAssociation.hasImage -eq $true) 'NS404 must prove card hasImage comes from QuestionAsset'
    Assert-Condition ([int]$real008.cardProbe.afterAssociation.assetCount -eq 1) 'NS404 must prove card assetCount comes from QuestionAsset'
    Assert-Condition ([bool]$real008.cardProbe.afterUnlink.hasImage -eq $false) 'NS404 must prove unlink removes hasImage'
    Assert-Condition ([int]$real008.cardProbe.afterUnlink.assetCount -eq 0) 'NS404 must prove unlink removes assetCount'
    Assert-Condition ([int]$real008.detailProbe.assetCount -eq 1) 'NS404 must prove reassociation restores detail asset'
    Assert-Condition ([string]$real008.detailProbe.assetType -eq 'image') 'NS404 asset type must be image'
    Assert-Condition ([string]$real008.detailProbe.purpose -eq 'question_figure') 'NS404 asset purpose must be question_figure'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$real008.detailProbe.sourceRegionScreenshotUrl)) 'NS404 detail screenshot URL missing'
    Assert-Condition ([string]$real008.sourceProbe.assetRegionType -eq 'question_asset') 'NS404 source review must expose question_asset region'
    Assert-Condition ([int]$real008.sourceProbe.assetScreenshotStatusCode -eq 200) 'NS404 asset screenshot endpoint must return 200'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$real008.auditIds.associate)) 'NS404 associate audit id missing'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$real008.auditIds.unlink)) 'NS404 unlink audit id missing'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$real008.auditIds.reassociate)) 'NS404 reassociate audit id missing'

    $program = Get-Content -LiteralPath 'apps/api/Program.cs' -Raw
    foreach ($marker in @(
        'WithName("AssociateQuestionAsset")',
        'WithName("UnlinkQuestionAsset")',
        'question_asset_revision',
        'question_asset_associated',
        'question_asset_unlinked',
        'sourceRegionScreenshotUrl'
    )) {
        Assert-Condition ($program.Contains($marker)) "NS404 API marker missing: $marker"
    }

    $app = Get-Content -LiteralPath 'apps/web/src/App.tsx' -Raw
    foreach ($marker in @(
        "runWorkbenchAction('associate')",
        "data-action=`"associate`"",
        'data-contract="question-stem-asset-fusion"',
        '共用题图',
        '未关联题图'
    )) {
        Assert-Condition ($app.Contains($marker)) "NS404 UI marker missing: $marker"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS404'
        checkedAt = (Get-Date).ToString('s')
        mode = 'real008_question_asset_wrapper_plus_api_ui_contract_markers'
        productionEligible = $false
        dependency = [ordered]@{
            ns403 = 'docs/evidence/20260530-ns403-review-workbench-ui-report.json'
            real008 = $SourceReportPath
        }
        questionAsset = [ordered]@{
            questionId = [string]$real008.questionId
            sourceDocumentId = [string]$real008.sourceDocumentId
            assetSourceRegionId = [string]$real008.assetSourceRegionId
            beforeAssociation = $real008.cardProbe.beforeAssociation
            afterAssociation = $real008.cardProbe.afterAssociation
            afterUnlink = $real008.cardProbe.afterUnlink
            detailAssetCountAfterReassociate = [int]$real008.detailProbe.assetCount
            detailAssetType = [string]$real008.detailProbe.assetType
            detailPurpose = [string]$real008.detailProbe.purpose
            sourceRegionScreenshotUrl = [string]$real008.detailProbe.sourceRegionScreenshotUrl
            screenshotStatusCode = [int]$real008.sourceProbe.assetScreenshotStatusCode
        }
        auditIds = [ordered]@{
            associate = [string]$real008.auditIds.associate
            unlink = [string]$real008.auditIds.unlink
            reassociate = [string]$real008.auditIds.reassociate
        }
        acceptance = [ordered]@{
            cardDoesNotInferImageFromSourceScreenshot = $true
            associationAddsCardImageAndAssetCount = $true
            unlinkRemovesCardImageAndAssetCount = $true
            reassociationCoversRecutRegression = $true
            detailExposesQuestionAssetScreenshot = $true
            sourceReviewRendersQuestionAssetRegion = $true
            associateUnlinkReassociateAudited = $true
            teacherWorkbenchAssociateMarkerPresent = $true
        }
        boundary = 'NS404 proves QuestionAsset association, unlink, and reassociation through REAL008 API smoke plus frontend contract markers. It uses reassociation as the recut regression and does not claim live crop UI pixel editing or onsite teacher validation.'
        next = 'NS405 can continue table/formula QuestionBlock contract evidence; NS406 can combine NS404 and NS405 for edit audit.'
        rollback = "git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns404-question-asset.ps1 docs/evidence/20260530-ns404-question-asset-report.json docs/evidence/20260530-ns404-real008-source-report.json"
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}

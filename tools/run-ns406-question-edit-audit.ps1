param(
    [string] $ReportPath = 'docs/evidence/20260530-ns406-question-edit-audit-report.json',
    [string] $SourceReportPath = 'docs/evidence/20260530-ns406-real011-source-report.json',
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
    $ns404 = Read-Json 'docs/evidence/20260530-ns404-question-asset-report.json'
    $ns405 = Read-Json 'docs/evidence/20260530-ns405-table-formula-blocks-report.json'
    Assert-Condition ($ns404.status -eq 'pass') 'NS406 dependency NS404 report did not pass'
    Assert-Condition ($ns405.status -eq 'pass') 'NS406 dependency NS405 report did not pass'
    Assert-Condition ([bool]$ns404.acceptance.associateUnlinkReassociateAudited) 'NS406 requires NS404 QuestionAsset audit evidence'
    Assert-Condition ([bool]$ns405.acceptance.tableSavedAsStructuredJson) 'NS406 requires NS405 table block evidence'
    Assert-Condition ([bool]$ns405.acceptance.formulaKeepsOmmlAsFirstSource) 'NS406 requires NS405 formula block evidence'

    $buildOutput = dotnet build 'apps/api/K12QuestionGraph.Api.csproj' -c Release 2>&1
    Assert-Condition ($LASTEXITCODE -eq 0) 'dotnet build failed before NS406 question edit smoke'

    if ($ApiPort -le 0) {
        $ApiPort = Get-FreeTcpPort
    }

    $real011Output = & pwsh -NoProfile -ExecutionPolicy Bypass -File 'tools/run-real011-question-edit-smoke.ps1' `
        -DatabaseName $DatabaseName `
        -DatabaseUser $DatabaseUser `
        -DatabaseHost $DatabaseHost `
        -DatabasePort $DatabasePort `
        -DatabasePassword $DatabasePassword `
        -FileStoreRoot $FileStoreRoot `
        -ApiPort $ApiPort `
        -PgBin $PgBin `
        -ReportPath $SourceReportPath 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "REAL011 question edit dependency failed: $real011Output"

    $real011 = Read-Json $SourceReportPath
    Assert-Condition ($real011.status -eq 'pass' -and $real011.task -eq 'REAL011') 'REAL011 source report did not pass'
    Assert-Condition ([string]$real011.questionEdit.questionType -eq 'calculation') 'NS406 questionType edit missing'
    Assert-Condition ([double]$real011.questionEdit.defaultScore -eq 6) 'NS406 score edit missing'
    Assert-Condition ([double]$real011.questionEdit.difficultyEstimated -eq 0.74) 'NS406 difficulty edit missing'
    Assert-Condition ([string]$real011.questionEdit.status -eq 'pending_review') 'NS406 status edit missing'
    Assert-Condition ([string]$real011.questionEdit.editedStem -like 'REAL011 修订后题干*') 'NS406 stem edit missing'
    Assert-Condition ([string]$real011.questionEdit.answer -eq '修订答案') 'NS406 answer edit missing'
    Assert-Condition ([string]$real011.questionEdit.solution -eq '修订解析') 'NS406 solution edit missing'
    Assert-Condition ([int]$real011.questionEdit.blockCount -ge 2) 'NS406 block edit/add missing'
    Assert-Condition ([string]$real011.sourceRegionEdit.regionType -eq 'question_stem_revised') 'NS406 recrop region type missing'
    Assert-Condition ([double]$real011.sourceRegionEdit.x -eq 11 -and [double]$real011.sourceRegionEdit.y -eq 16) 'NS406 recrop bbox origin missing'
    Assert-Condition ([double]$real011.sourceRegionEdit.width -eq 58 -and [double]$real011.sourceRegionEdit.height -eq 18) 'NS406 recrop bbox size missing'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$real011.sourceRegionEdit.auditId)) 'NS406 source region audit missing'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$real011.auditProbe.questionRevisionAuditId)) 'NS406 question revision audit missing'
    Assert-Condition ([string]$real011.auditProbe.questionAuditDecision -eq 'question_updated') 'NS406 question audit decision mismatch'

    $program = Get-Content -LiteralPath 'apps/api/Program.cs' -Raw
    foreach ($marker in @(
        'WithName("UpdateQuestion")',
        'ReviewType = "question_revision"',
        'decision = "question_updated"',
        'PrimaryKnowledgeId',
        'KnowledgeMappingSources.Manual',
        'WithName("UpdateSourceRegion")',
        'source_region_revision'
    )) {
        Assert-Condition ($program.Contains($marker)) "NS406 API marker missing: $marker"
    }

    $app = Get-Content -LiteralPath 'apps/web/src/App.tsx' -Raw
    foreach ($marker in @(
        "runWorkbenchAction('merge')",
        "runWorkbenchAction('split')",
        "runWorkbenchAction('undo')",
        "runWorkbenchAction('save_question')",
        'data-action="merge"',
        'data-action="split"',
        'data-action="undo"',
        'data-action="takeover-split"',
        'data-action="takeover-merge"',
        '来源区域已关联'
    )) {
        Assert-Condition ($app.Contains($marker)) "NS406 UI marker missing: $marker"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS406'
        checkedAt = (Get-Date).ToString('s')
        mode = 'real011_question_edit_wrapper_plus_ns404_ns405_dependencies_and_workbench_markers'
        productionEligible = $false
        dependency = [ordered]@{
            ns404 = 'docs/evidence/20260530-ns404-question-asset-report.json'
            ns405 = 'docs/evidence/20260530-ns405-table-formula-blocks-report.json'
            real011 = $SourceReportPath
        }
        questionEdit = [ordered]@{
            questionId = [string]$real011.questionId
            sourceRegionId = [string]$real011.sourceRegionId
            questionType = [string]$real011.questionEdit.questionType
            defaultScore = [double]$real011.questionEdit.defaultScore
            difficultyEstimated = [double]$real011.questionEdit.difficultyEstimated
            status = [string]$real011.questionEdit.status
            editedStem = [string]$real011.questionEdit.editedStem
            answer = [string]$real011.questionEdit.answer
            solution = [string]$real011.questionEdit.solution
            blockCount = [int]$real011.questionEdit.blockCount
        }
        recrop = [ordered]@{
            regionType = [string]$real011.sourceRegionEdit.regionType
            x = [double]$real011.sourceRegionEdit.x
            y = [double]$real011.sourceRegionEdit.y
            width = [double]$real011.sourceRegionEdit.width
            height = [double]$real011.sourceRegionEdit.height
            sourceRegionAuditId = [string]$real011.sourceRegionEdit.auditId
        }
        audit = [ordered]@{
            questionRevisionAuditId = [string]$real011.auditProbe.questionRevisionAuditId
            questionAuditDecision = [string]$real011.auditProbe.questionAuditDecision
            sourceRegionAuditId = [string]$real011.auditProbe.sourceRegionAuditId
        }
        relatedContracts = [ordered]@{
            questionAssetAuditFromNs404 = [bool]$ns404.acceptance.associateUnlinkReassociateAudited
            tableBlockContractFromNs405 = [bool]$ns405.acceptance.tableSavedAsStructuredJson
            formulaBlockContractFromNs405 = [bool]$ns405.acceptance.formulaKeepsOmmlAsFirstSource
            mergeSplitUndoSaveQuestionUiMarkers = $true
            manualKnowledgeTagEditApiPathPresent = $true
        }
        acceptance = [ordered]@{
            stemEditable = $true
            answerEditable = $true
            solutionEditable = $true
            scoreDifficultyStatusEditable = $true
            bboxRecropEditable = $true
            blockAddAndEditAudited = $true
            questionRevisionAudited = $true
            sourceRegionRevisionAudited = $true
            assetTableFormulaDependenciesVerified = $true
            mergeSplitUndoSaveQuestionWorkbenchPresent = $true
        }
        boundary = 'NS406 proves question edit and recrop audit through REAL011 API smoke, plus NS404 QuestionAsset and NS405 table/formula dependencies. Knowledge tag edit is verified as an API contract path marker, not a separate live UI interaction. It does not claim onsite teacher validation.'
        next = 'NS501 can continue C002 active reference boundary after NS4 edit/import review chain is runtime verified.'
        rollback = "git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns406-question-edit-audit.ps1 docs/evidence/20260530-ns406-question-edit-audit-report.json docs/evidence/20260530-ns406-real011-source-report.json"
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}

param(
    [string] $ReportPath = 'docs/evidence/20260530-ns606-export-preflight-report.json',
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

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

function Read-Text([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing file: $Path"
    return Get-Content -LiteralPath $fullPath -Raw
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

function Invoke-CheckedScript([scriptblock] $Command, [string] $Label) {
    $output = & $Command 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "$Label failed: $output"
    return $output
}

Push-Location $repoRoot
try {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) 'DatabasePassword or PGPASSWORD is required for NS606 export preflight verification.'

    $ns605 = Read-Json 'docs/evidence/20260530-ns605-replace-undo-report.json'
    Assert-Condition ($ns605.status -eq 'pass') 'NS606 dependency NS605 report did not pass'
    Assert-Condition ([bool]$ns605.acceptance.providesUndoSnapshot) 'NS606 requires NS605 reversible paper-workbench evidence'

    $apiBuildOutput = & dotnet build apps/api/K12QuestionGraph.Api.csproj -c Release 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "NS606 API build failed: $apiBuildOutput"

    $s010aPath = 'docs/evidence/20260530-ns606-s010a-source-report.json'
    $s010aPort = Get-FreeTcpPort
    Invoke-CheckedScript {
        .\tools\run-s010a-export-preflight-api-smoke.ps1 `
            -DatabaseName $DatabaseName `
            -DatabaseUser $DatabaseUser `
            -DatabaseHost $DatabaseHost `
            -DatabasePort $DatabasePort `
            -DatabasePassword $DatabasePassword `
            -PgBin $PgBin `
            -ApiPort $s010aPort `
            -ReportPath $s010aPath
    } 'S010A export preflight API smoke' | Write-Host

    $s010a = Read-Json $s010aPath
    Assert-Condition ($s010a.status -eq 'pass') 'S010A source report did not pass'
    Assert-Condition ([string]$s010a.preflightStatus -eq 'blocked') 'NS606 preflight must block risky export'
    Assert-Condition ([int]$s010a.itemCount -eq 2) 'NS606 requires preflight item coverage'
    foreach ($requiredIssue in @(
        'answer_missing',
        'solution_missing',
        'source_missing',
        'knowledge_version_reference_missing',
        'image_not_attached'
    )) {
        Assert-Condition (@($s010a.issueCodes) -contains $requiredIssue) "NS606 missing preflight issue code: $requiredIssue"
    }
    Assert-Condition ([int]$s010a.summary.formulaReadyCount -ge 1) 'NS606 formula readiness count missing'
    Assert-Condition ([int]$s010a.summary.tableReadyCount -ge 1) 'NS606 table readiness count missing'
    Assert-Condition ([int]$s010a.summary.imageReadyCount -ge 1) 'NS606 image readiness count missing'
    Assert-Condition ([int]$s010a.summary.answerReadyCount -ge 1) 'NS606 answer readiness count missing'
    Assert-Condition ([int]$s010a.summary.solutionReadyCount -ge 1) 'NS606 solution readiness count missing'
    Assert-Condition ([int]$s010a.summary.authorizedSourceCount -ge 1) 'NS606 source authorization readiness count missing'
    Assert-Condition ([int]$s010a.summary.activeKnowledgeVersionCount -ge 1) 'NS606 active knowledge version readiness count missing'

    $m004Output = Invoke-CheckedScript {
        .\tools\run-m004-export-preflight-contract.ps1
    } 'M004 export preflight contract'
    $m004 = $m004Output | ConvertFrom-Json
    Assert-Condition ($m004.status -eq 'pass') 'M004 export preflight contract did not pass'

    $apiSurface = (Read-Text 'apps/api/Program.cs') + "`n" + (Read-Text 'apps/api/Application/Workflows/PaperWorkflowService.cs')
    foreach ($marker in @(
        '/paper-baskets/{id:guid}/export-preflight',
        'RunPaperExportPreflight',
        'PaperExportPreflightResponse',
        'source_authorization_risk',
        'knowledge_version_reference_missing',
        'answer_missing',
        'solution_missing'
    )) {
        Assert-Condition ($apiSurface.Contains($marker)) "NS606 API marker missing: $marker"
    }

    $app = Read-Text 'apps/web/src/App.tsx'
    foreach ($marker in @(
        'data-flow="paper-export"',
        'data-action="export-docx"',
        'data-action="export-pdf"',
        'data-contract="export-productionEligible=false"',
        'data-contract="export-artifact-checks"',
        'data-contract="export-preview"'
    )) {
        Assert-Condition ($app.Contains($marker)) "NS606 UI marker missing: $marker"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS606'
        checkedAt = (Get-Date).ToString('s')
        mode = 'export_preflight_review'
        productionEligible = $false
        externalAiCalls = 0
        realStudentDataUsed = $false
        activeAssetMutation = $false
        dependency = [ordered]@{
            ns605 = 'docs/evidence/20260530-ns605-replace-undo-report.json'
            s010a = $s010aPath
            m004 = [string]$m004.m004EvidencePath
        }
        preflight = [ordered]@{
            paperBasketId = [string]$s010a.paperBasketId
            status = [string]$s010a.preflightStatus
            itemCount = [int]$s010a.itemCount
            issueCodes = @($s010a.issueCodes)
            teacherMessage = [string]$s010a.teacherMessage
            summary = $s010a.summary
        }
        acceptance = [ordered]@{
            studentTeacherAnswerVersionsMustBePreflighted = $true
            sourceAuthorizationRiskBlocksExport = $true
            missingAnswerBlocksTeacherAndAnswerVersions = $true
            missingSolutionBlocksExport = $true
            missingSourceBlocksAuthorization = $true
            missingKnowledgeVersionBlocksReproducibility = $true
            imageFormulaTableReadinessCounted = $true
            uiHasDocxAndPdfExportActions = $true
            noExternalAiCall = $true
            noRealStudentData = $true
            noActiveSwitch = $true
        }
        verification = [ordered]@{
            build = 'dotnet build apps/api/K12QuestionGraph.Api.csproj -c Release'
            test = 'tools/run-s010a-export-preflight-api-smoke.ps1'
            contractInvariant = 'tools/run-m004-export-preflight-contract.ps1 plus API/UI markers for export preflight and export actions'
            hotspot = 'gate_na: no independent hotspot command; teacher workflow hotspot covered by issue-code blocking for source authorization, answer, solution, image, and knowledge-version reproducibility'
        }
        boundary = 'NS606 proves export preflight blocks risky student/teacher/answer-version generation until source authorization, answer/solution, asset, and knowledge-version reproducibility checks are visible.'
        rollback = "delete synthetic S010A rows recorded in $s010aPath if needed; git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns606-export-preflight.ps1 $ReportPath $s010aPath"
        next = 'NS607 can continue Word/PDF artifact regression.'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}

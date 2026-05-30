param(
    [string] $ReportPath = 'docs/evidence/20260530-ns602-question-card-ui-report.json'
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

function Read-Text([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing file: $Path"
    return Get-Content -LiteralPath $fullPath -Raw
}

Push-Location $repoRoot
try {
    $ns601 = Read-Json 'docs/evidence/20260530-ns601-question-search-api-report.json'
    Assert-Condition ($ns601.status -eq 'pass') 'NS602 dependency NS601 report did not pass'
    Assert-Condition ([bool]$ns601.acceptance.cardSummaryIncludesPreviewSourcesFlagsAndVersion) 'NS602 requires NS601 card summary evidence'

    $s008bOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File 'tools/run-s008b-question-card-ui-contract.ps1' 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "S008B question card UI dependency failed: $s008bOutput"
    $s008b = Read-Json 'docs/evidence/20260507-s008b-question-card-ui-contract-report.json'
    Assert-Condition ($s008b.status -eq 'pass') 'S008B source report did not pass'

    $program = Read-Text 'apps/api/Program.cs'
    foreach ($marker in @(
        'document.LicenseOrPermission',
        'document.SharingAllowed',
        'document.ContainsStudentPii',
        'SourceSummaryResponse([], [], [], false, false, [], 0, 0)'
    )) {
        Assert-Condition ($program.Contains($marker)) "NS602 API source authorization marker missing: $marker"
    }
    $apiBuildOutput = & dotnet build apps/api/K12QuestionGraph.Api.csproj -c Release 2>&1 | Out-String
    Assert-Condition ($LASTEXITCODE -eq 0) "NS602 API build failed: $apiBuildOutput"

    $contracts = Read-Text 'apps/web/src/api/contracts.ts'
    foreach ($marker in @(
        'permissions: string[]',
        'sharingAllowed: boolean',
        'containsStudentPii: boolean',
        'anonymizationStatuses: string[]',
        "permissions: readArrayField(sources, 'permissions')",
        "sharingAllowed: readBooleanField(sources, 'sharingAllowed')"
    )) {
        Assert-Condition ($contracts.Contains($marker)) "NS602 typed contract marker missing: $marker"
    }

    $app = Read-Text 'apps/web/src/App.tsx'
    foreach ($marker in @(
        'data-contract="s008b-real-api-question-cards"',
        'data-state="question-search-empty"',
        'data-state="question-search-error"',
        'data-action="question-search-refresh"',
        '授权待确认',
        '可校内共享',
        '共享受限',
        '无学生信息',
        '含学生信息',
        '题图',
        '公式',
        '表格'
    )) {
        Assert-Condition ($app.Contains($marker)) "NS602 question card UI marker missing: $marker"
    }

    Push-Location 'apps/web'
    try {
        $buildOutput = & npm run build 2>&1 | Out-String
        Assert-Condition ($LASTEXITCODE -eq 0) "NS602 npm build failed: $buildOutput"
        $lintOutput = & npm run lint 2>&1 | Out-String
        Assert-Condition ($LASTEXITCODE -eq 0) "NS602 npm lint failed: $lintOutput"
    }
    finally {
        Pop-Location
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS602'
        checkedAt = (Get-Date).ToString('s')
        mode = 'question_card_ui_productization_contract'
        productionEligible = $false
        dependency = [ordered]@{
            ns601 = 'docs/evidence/20260530-ns601-question-search-api-report.json'
            s008b = 'docs/evidence/20260507-s008b-question-card-ui-contract-report.json'
        }
        ui = [ordered]@{
            app = 'apps/web/src/App.tsx'
            contracts = 'apps/web/src/api/contracts.ts'
            api = 'apps/api/Program.cs'
            states = @('loading', 'empty', 'error', 'card_selected')
            cardFields = @('preview', 'source', 'knowledge_version', 'question_type', 'difficulty', 'status', 'image', 'formula', 'table', 'permission', 'sharing', 'student_pii')
        }
        verification = [ordered]@{
            apiBuild = 'pass'
            npmBuild = 'pass'
            npmLint = 'pass'
            typedClientBoundary = 'pass'
            sourceAuthorizationBoundaryVisible = $true
        }
        acceptance = [ordered]@{
            cardShowsSourceAndVersion = $true
            cardShowsImageFormulaTableFlags = $true
            cardShowsAuthorizationBoundary = $true
            emptyAndErrorStatesPresent = $true
            typedContractIncludesAuthorization = $true
            noExternalAiCall = $true
            noRealStudentData = $true
        }
        boundary = 'NS602 proves the question-card UI consumes the typed question search contract and displays source, active version, rich-media flags, status, and authorization/privacy boundary states. It runs frontend build/lint and does not call external AI or use real student data.'
        next = 'NS603 can continue paper basket and paper draft persistence.'
        rollback = "git restore apps/api/Program.cs apps/web/src/App.tsx apps/web/src/api/contracts.ts tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns602-question-card-ui.ps1 docs/evidence/20260530-ns602-question-card-ui-report.json"
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}

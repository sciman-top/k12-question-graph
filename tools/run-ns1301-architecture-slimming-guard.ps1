param(
    [string] $ReportPath = 'docs/evidence/20260607-ns1301-architecture-slimming.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Read-Text([string] $Path) {
    $fullPath = Join-Path $repoRoot $Path
    Assert-Condition (Test-Path -LiteralPath $fullPath) "missing file: $Path"
    return Get-Content -LiteralPath $fullPath -Raw
}

Push-Location $repoRoot
try {
    $appPath = 'apps/web/src/App.tsx'
    $app = Read-Text $appPath
    $architecture = Read-Text 'docs/03_Architecture.md'
    $program = Read-Text 'apps/api/Program.cs'

    $requiredUiFiles = @(
        'apps/web/src/ui/workbenchData.tsx',
        'apps/web/src/ui/TeacherHomePanelContent.tsx',
        'apps/web/src/ui/ScoreWorkbenchPanelContent.tsx',
        'apps/web/src/ui/AnalysisPanelContent.tsx',
        'apps/web/src/ui/PaperWorkbenchPanels.tsx'
    )

    foreach ($path in $requiredUiFiles) {
        Assert-Condition (Test-Path -LiteralPath $path) "NS1301 extracted UI file missing: $path"
    }

    foreach ($marker in @(
        "from './ui/TeacherHomePanelContent'",
        "from './ui/ScoreWorkbenchPanelContent'",
        "from './ui/AnalysisPanelContent'",
        "from './ui/PaperWorkbenchPanels'",
        "from './ui/workbenchData'"
    )) {
        Assert-Condition ($app.Contains($marker)) "NS1301 App.tsx missing extracted import marker: $marker"
    }

    foreach ($marker in @(
        '<TeacherHomePanelContent',
        '<ScoreWorkbenchPanelContent',
        '<AnalysisPanelContent',
        '<PaperWorkbenchPanels'
    )) {
        Assert-Condition ($app.Contains($marker)) "NS1301 App.tsx missing extracted component usage: $marker"
    }

    foreach ($forbidden in @(
        'const teacherActions = [',
        'const scoreWorkbenchActions = [',
        'const paperWorkbenchSummaryCards = [',
        'const initialPaperUnderstanding = {',
        'const initialCommentaryReportPreview = {',
        'function renderMathAwareText(value: string): ReactNode[]'
    )) {
        Assert-Condition (-not $app.Contains($forbidden)) "NS1301 App.tsx still owns extracted inline config/helper: $forbidden"
    }

    $appLineCount = (Get-Content -LiteralPath $appPath | Measure-Object -Line).Lines
    Assert-Condition ($appLineCount -lt 2000) "NS1301 expects App.tsx under 2000 lines after extraction; current=$appLineCount"

    foreach ($marker in @(
        'TeacherHomePanelContent.tsx',
        'ScoreWorkbenchPanelContent.tsx',
        'AnalysisPanelContent.tsx',
        'PaperWorkbenchPanels.tsx',
        'workbenchData.tsx',
        'Program.cs',
        'Application/Workflows/*.cs'
    )) {
        Assert-Condition ($architecture.Contains($marker)) "NS1301 architecture inventory missing marker: $marker"
    }

    foreach ($programMarker in @(
        'builder.Host.UseWindowsService();',
        'AddScoped<IImportReviewWorkflowService, ImportReviewWorkflowService>()',
        'AddScoped<IPaperWorkflowService, PaperWorkflowService>()',
        'AddScoped<IScoreAnalysisWorkflowService, ScoreAnalysisWorkflowService>()'
    )) {
        Assert-Condition ($program.Contains($programMarker)) "NS1301 service ownership marker missing in Program.cs: $programMarker"
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS1301'
        checkedAt = (Get-Date).ToString('s')
        mode = 'static_architecture_inventory_and_app_slimming_guard'
        productionEligible = $false
        app = [ordered]@{
            path = $appPath
            lineCount = $appLineCount
            extractedComponents = @(
                'TeacherHomePanelContent',
                'ScoreWorkbenchPanelContent',
                'AnalysisPanelContent',
                'PaperWorkbenchPanels'
            )
            extractedDataModule = 'apps/web/src/ui/workbenchData.tsx'
        }
        api = [ordered]@{
            program = 'apps/api/Program.cs'
            windowsServiceHost = $true
            workflowServiceRegistrations = @(
                'IImportReviewWorkflowService',
                'IPaperWorkflowService',
                'IScoreAnalysisWorkflowService'
            )
        }
        architectureDoc = 'docs/03_Architecture.md'
        acceptance = [ordered]@{
            appOwnsStateNotLargeInlineConfig = $true
            teacherHomeScorePaperViewsExtracted = $true
            architectureInventoryPresent = $true
            windowsServiceAndWorkflowOwnershipVisible = $true
        }
        boundary = 'NS1301 guards the repo-level structure split and inventory. It does not claim every import/review endpoint or every App.tsx panel is fully minimal; remaining import/review density and NS104 legacy direct-DB debt stay explicit.'
        next = 'Continue trimming import/review UI density and migrate remaining review/import direct-DB endpoints toward workflow services before NS1302 Windows Service control panel productization.'
        rollback = 'git restore apps/web/src/App.tsx apps/web/src/ui docs/03_Architecture.md tools/run-gates.ps1; git clean -f -- tools/run-ns1301-architecture-slimming-guard.ps1 docs/evidence/20260607-ns1301-architecture-slimming.json'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}

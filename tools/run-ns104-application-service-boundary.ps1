param(
    [string] $ReportPath = 'docs/evidence/20260529-ns104-application-service-boundary-report.json',
    [string] $ProgramPath = 'apps/api/Program.cs',
    [string] $Project = 'apps/api/K12QuestionGraph.Api.csproj'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Get-EndpointBlock([string[]] $Lines, [string] $Route) {
    $escapedRoute = [regex]::Escape($Route)
    $start = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match "app\.Map(Get|Post|Put|Delete|Patch)\(`"$escapedRoute`"") {
            $start = $i
            break
        }
    }

    Assert-Condition ($start -ge 0) "endpoint missing: $Route"

    $end = [Math]::Min($Lines.Count - 1, $start + 220)
    for ($i = $start; $i -le $end; $i++) {
        if ($Lines[$i] -match '\.WithName\("([^"]+)"\)') {
            $end = $i
            break
        }
    }

    [ordered]@{
        route = $Route
        line = $start + 1
        text = ($Lines[$start..$end] -join "`n")
    }
}

function Test-ServiceBackedEndpoint(
    [string[]] $Lines,
    [string] $Route,
    [string] $RequiredService,
    [string[]] $RequiredMarkers
) {
    $block = Get-EndpointBlock $Lines $Route
    $text = [string]$block.text
    $missingMarkers = @($RequiredMarkers | Where-Object { $text -notmatch [regex]::Escape($_) })

    [ordered]@{
        route = $Route
        line = $block.line
        requiredService = $RequiredService
        serviceInjected = $text -match [regex]::Escape($RequiredService)
        directDbContext = $text -match 'KqgDbContext\s+dbContext'
        saveChangesInEndpoint = $text -match 'SaveChangesAsync\('
        requiredMarkers = $RequiredMarkers
        missingMarkers = $missingMarkers
        pass = (
            ($text -match [regex]::Escape($RequiredService)) -and
            -not ($text -match 'KqgDbContext\s+dbContext') -and
            -not ($text -match 'SaveChangesAsync\(') -and
            $missingMarkers.Count -eq 0
        )
    }
}

Push-Location $repoRoot
try {
    Assert-Condition (Test-Path -LiteralPath $ProgramPath) "missing Program.cs: $ProgramPath"
    foreach ($path in @(
        'apps/api/Application/Workflows/ImportReviewWorkflowService.cs',
        'apps/api/Application/Workflows/CutCandidateGenerationService.cs',
        'apps/api/Application/Workflows/PaperWorkflowService.cs',
        'apps/api/Application/Workflows/ScoreAnalysisWorkflowService.cs',
        'apps/api/Application/Workflows/Contracts/WorkflowContracts.cs'
    )) {
        Assert-Condition (Test-Path -LiteralPath $path) "missing application service boundary file: $path"
    }

    $buildOutput = dotnet build $Project 2>&1
    Assert-Condition ($LASTEXITCODE -eq 0) 'dotnet build failed before NS104 boundary guard'

    $programLines = @(Get-Content -LiteralPath $ProgramPath)
    $programText = $programLines -join "`n"

    foreach ($registration in @(
        'AddScoped<IImportReviewWorkflowService, ImportReviewWorkflowService>',
        'AddScoped<ICutCandidateGenerationService, CutCandidateGenerationService>',
        'AddScoped<IPaperWorkflowService, PaperWorkflowService>',
        'AddScoped<IScoreAnalysisWorkflowService, ScoreAnalysisWorkflowService>'
    )) {
        Assert-Condition ($programText -match [regex]::Escape($registration)) "missing DI registration: $registration"
    }

    $serviceEndpoints = @(
        (Test-ServiceBackedEndpoint $programLines '/source-documents/{id:guid}/cut-candidates/generate' 'ICutCandidateGenerationService' @('GenerateAsync(', 'CutCandidateGenerationResponse')),
        (Test-ServiceBackedEndpoint $programLines '/score-imports' 'IScoreAnalysisWorkflowService' @('ImportScoresAsync(', 'ScoreImportServiceRequest')),
        (Test-ServiceBackedEndpoint $programLines '/assessments/{assessmentId:guid}/item-score-mappings/preview' 'IScoreAnalysisWorkflowService' @('PreviewItemScoreMappingsAsync(', 'ItemScoreMappingPreviewServiceRequest')),
        (Test-ServiceBackedEndpoint $programLines '/assessments/{assessmentId:guid}/commentary-report/export' 'IScoreAnalysisWorkflowService' @('ExportCommentaryReportAsync(', 'CommentaryReportExportServiceRequest')),
        (Test-ServiceBackedEndpoint $programLines '/paper-baskets/{id:guid}/export-preflight' 'IPaperWorkflowService' @('RunExportPreflightAsync(', 'PaperExportPreflightResponse')),
        (Test-ServiceBackedEndpoint $programLines '/paper-requests/parse' 'IPaperWorkflowService' @('ParsePaperRequest(', 'PaperRequestParseResponse')),
        (Test-ServiceBackedEndpoint $programLines '/paper-blueprints' 'IPaperWorkflowService' @('CreateBlueprintReviewAsync(', 'PaperBlueprintReviewResponse')),
        (Test-ServiceBackedEndpoint $programLines '/paper-blueprints/{id:guid}/confirm' 'IPaperWorkflowService' @('ConfirmBlueprintReviewAsync(', 'PaperBlueprintConfirmResponse')),
        (Test-ServiceBackedEndpoint $programLines '/paper-requests/replace-question' 'IPaperWorkflowService' @('ReplaceQuestion(', 'PaperQuestionReplacementResponse')),
        (Test-ServiceBackedEndpoint $programLines '/knowledge-version-explanations/resolve' 'IPaperWorkflowService' @('ResolveKnowledgeVersionExplanation(', 'KnowledgeVersionExplanationResponse'))
    )

    $failedServiceEndpoints = @($serviceEndpoints | Where-Object { -not $_.pass })
    Assert-Condition ($failedServiceEndpoints.Count -eq 0) "service-backed endpoint boundary failed: $($failedServiceEndpoints.route -join ', ')"

    $legacyDirectDbRoutes = @(
        '/imports',
        '/imports/{id:guid}',
        '/review-queue',
        '/review-queue/batch-resolve',
        '/review-queue/{id:guid}/resolve',
        '/review-workbench/actions',
        '/paper-baskets',
        '/paper-baskets/{id:guid}'
    )
    $legacyDebt = @()
    foreach ($route in $legacyDirectDbRoutes) {
        $block = Get-EndpointBlock $programLines $route
        $text = [string]$block.text
        $legacyDebt += [ordered]@{
            route = $route
            line = $block.line
            directDbContext = $text -match 'KqgDbContext\s+dbContext'
            saveChangesInEndpoint = $text -match 'SaveChangesAsync\('
            owner = if ($route -like '/review*') { 'NS402/NS403 review API/workbench' } elseif ($route -like '/imports*') { 'NS301/NS401 import source service extraction' } else { 'NS603 paper basket legacy compatibility' }
            allowedInNs104 = $true
        }
    }

    $serviceFiles = @(
        'apps/api/Application/Workflows/ImportReviewWorkflowService.cs',
        'apps/api/Application/Workflows/CutCandidateGenerationService.cs',
        'apps/api/Application/Workflows/PaperWorkflowService.cs',
        'apps/api/Application/Workflows/ScoreAnalysisWorkflowService.cs'
    )
    $serviceSummaries = foreach ($file in $serviceFiles) {
        $text = Get-Content -LiteralPath $file -Raw
        [ordered]@{
            path = $file
            asyncMethodCount = ([regex]::Matches($text, 'Task<|Task\s')).Count
            saveChangesCount = ([regex]::Matches($text, 'SaveChangesAsync\(')).Count
            dbContextOwnedHere = $text -match 'KqgDbContext'
        }
    }

    $report = [ordered]@{
        status = 'pass'
        taskId = 'NS104'
        checkedAt = (Get-Date).ToString('s')
        mode = 'static_architecture_guard_plus_build'
        productionEligible = $false
        build = [ordered]@{
            project = $Project
            exitCode = 0
        }
        requiredServices = @(
            'IImportReviewWorkflowService',
            'ICutCandidateGenerationService',
            'IPaperWorkflowService',
            'IScoreAnalysisWorkflowService'
        )
        serviceBackedEndpoints = $serviceEndpoints
        serviceBackedEndpointCount = $serviceEndpoints.Count
        legacyDirectDbEndpointDebt = $legacyDebt
        legacyDebtCount = $legacyDebt.Count
        serviceSummaries = $serviceSummaries
        acceptance = [ordered]@{
            cutCandidateGenerationInService = $true
            paperAndExportInService = $true
            scoreImportMappingAnalysisInService = $true
            importReviewServicePresent = $true
            endpointProtocolBoundaryGuarded = $true
            remainingLegacyEndpointDebtTracked = $true
        }
        boundary = 'NS104 guards the service-backed non-site core write chain and tracks remaining legacy direct-DB endpoints; it does not claim Program.cs is fully thin yet.'
        next = 'NS105 can continue frontend typed-client boundary; NS402/NS403 should migrate review queue and review workbench endpoint orchestration into services.'
        rollback = 'git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns104-application-service-boundary.ps1 docs/evidence/20260529-ns104-application-service-boundary-report.json'
    }

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 6
}
finally {
    Pop-Location
}

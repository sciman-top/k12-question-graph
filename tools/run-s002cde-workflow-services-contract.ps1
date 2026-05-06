param()

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

$requiredFiles = @(
    'apps/api/Application/Workflows/ImportReviewWorkflowService.cs',
    'apps/api/Application/Workflows/PaperWorkflowService.cs',
    'apps/api/Application/Workflows/ScoreAnalysisWorkflowService.cs'
)

foreach ($path in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $path))) {
        throw "missing workflow service file: $path"
    }
}

$program = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'apps/api/Program.cs')
$requiredRegistrations = @(
    'AddScoped<IImportReviewWorkflowService, ImportReviewWorkflowService>()',
    'AddScoped<IPaperWorkflowService, PaperWorkflowService>()',
    'AddScoped<IScoreAnalysisWorkflowService, ScoreAnalysisWorkflowService>()'
)

foreach ($registration in $requiredRegistrations) {
    if (-not $program.Contains($registration)) {
        throw "missing DI registration: $registration"
    }
}

[ordered]@{
    status = 'pass'
    taskIds = @('S002C','S002D','S002E')
    task = 'workflow service skeletons and DI boundary'
    checkedAt = (Get-Date).ToString('s')
} | ConvertTo-Json -Depth 4

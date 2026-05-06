param()

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$contractPath = Join-Path $repoRoot 'apps/api/Application/Workflows/Contracts/WorkflowContracts.cs'

if (-not (Test-Path -LiteralPath $contractPath)) {
    throw "S002B contract file missing: $contractPath"
}

$content = Get-Content -Raw -LiteralPath $contractPath
$requiredPatterns = @(
    'public static class WorkflowTypes',
    'public static class WorkflowStatuses',
    'public static class WorkflowErrorCodes',
    'public sealed record WorkflowRollbackReference',
    'public sealed record ImportWorkflowDto',
    'public sealed record ReviewWorkflowDto',
    'public sealed record TaggingWorkflowDto',
    'public sealed record PaperWorkflowDto',
    'public sealed record ExportWorkflowDto',
    'public sealed record ScoreWorkflowDto',
    'public sealed record AnalysisWorkflowDto'
)

foreach ($pattern in $requiredPatterns) {
    if (-not $content.Contains($pattern)) {
        throw "S002B contract missing pattern: $pattern"
    }
}

[ordered]@{
    status = 'pass'
    taskId = 'S002B'
    task = 'workflow dto status error rollback contract'
    contractPath = 'apps/api/Application/Workflows/Contracts/WorkflowContracts.cs'
    checkedAt = (Get-Date).ToString('s')
} | ConvertTo-Json -Depth 4

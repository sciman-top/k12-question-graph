using K12QuestionGraph.Api.Application.Workflows.Contracts;
using K12QuestionGraph.Api.Data;
using Microsoft.EntityFrameworkCore;

namespace K12QuestionGraph.Api.Application.Workflows;

public interface IScoreAnalysisWorkflowService
{
    Task<ScoreWorkflowDto> GetScoreImportSummaryAsync(Guid assessmentId, CancellationToken cancellationToken);
    Task<AnalysisWorkflowDto> GetAnalysisSummaryAsync(Guid assessmentId, CancellationToken cancellationToken);
}

public sealed class ScoreAnalysisWorkflowService(KqgDbContext dbContext) : IScoreAnalysisWorkflowService
{
    public async Task<ScoreWorkflowDto> GetScoreImportSummaryAsync(Guid assessmentId, CancellationToken cancellationToken)
    {
        var importedRowCount = await dbContext.ScoreRecords
            .AsNoTracking()
            .CountAsync(x => x.AssessmentId == assessmentId, cancellationToken);

        var exceptionRowCount = await dbContext.ScoreImportBatches
            .AsNoTracking()
            .Where(x => x.AssessmentId == assessmentId)
            .Select(x => x.ErrorCount)
            .FirstOrDefaultAsync(cancellationToken);

        return new ScoreWorkflowDto(
            assessmentId,
            "score-template-v1",
            importedRowCount,
            exceptionRowCount,
            new WorkflowStatusEnvelope(
                WorkflowTypes.Score,
                WorkflowStatuses.PendingReview,
                $"score:{assessmentId:N}",
                DateTimeOffset.UtcNow,
                Rollback: null,
                Error: null));
    }

    public async Task<AnalysisWorkflowDto> GetAnalysisSummaryAsync(Guid assessmentId, CancellationToken cancellationToken)
    {
        var weakKnowledgePointCount = await dbContext.KnowledgeMappings
            .AsNoTracking()
            .CountAsync(x => x.Confidence.HasValue && x.Confidence < 0.7m, cancellationToken);

        return new AnalysisWorkflowDto(
            assessmentId,
            "analysis-v1",
            weakKnowledgePointCount,
            new WorkflowStatusEnvelope(
                WorkflowTypes.Analysis,
                WorkflowStatuses.PendingReview,
                $"analysis:{assessmentId:N}",
                DateTimeOffset.UtcNow,
                Rollback: null,
                Error: null));
    }
}

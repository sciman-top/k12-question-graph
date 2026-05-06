using K12QuestionGraph.Api.Application.Workflows.Contracts;
using K12QuestionGraph.Api.Data;
using Microsoft.EntityFrameworkCore;

namespace K12QuestionGraph.Api.Application.Workflows;

public interface IImportReviewWorkflowService
{
    Task<ImportWorkflowDto?> GetImportWorkflowAsync(Guid importJobId, CancellationToken cancellationToken);
    Task<ReviewWorkflowDto?> GetReviewWorkflowAsync(Guid sourceDocumentId, CancellationToken cancellationToken);
}

public sealed class ImportReviewWorkflowService(KqgDbContext dbContext) : IImportReviewWorkflowService
{
    public async Task<ImportWorkflowDto?> GetImportWorkflowAsync(Guid importJobId, CancellationToken cancellationToken)
    {
        var job = await dbContext.ImportJobs
            .AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == importJobId, cancellationToken);

        if (job is null)
        {
            return null;
        }

        var source = await dbContext.SourceDocuments
            .AsNoTracking()
            .Where(x => x.FileAssetId == job.InputFileAssetId)
            .OrderByDescending(x => x.CreatedAt)
            .Select(x => new { x.SourceType, x.SourceTitle })
            .FirstOrDefaultAsync(cancellationToken);

        return new ImportWorkflowDto(
            job.Id,
            job.InputFileAssetId,
            source?.SourceType ?? "unknown",
            source?.SourceTitle ?? "未命名来源",
            new WorkflowStatusEnvelope(
                WorkflowTypes.Import,
                job.Status,
                job.IdempotencyKey,
                DateTimeOffset.UtcNow,
                Rollback: null,
                Error: job.LastErrorCode is null
                    ? null
                    : new WorkflowError(job.LastErrorCode, job.LastErrorMessage ?? string.Empty, Retryable: true, EvidencePath: null)));
    }

    public async Task<ReviewWorkflowDto?> GetReviewWorkflowAsync(Guid sourceDocumentId, CancellationToken cancellationToken)
    {
        var sourceDocument = await dbContext.SourceDocuments
            .AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == sourceDocumentId, cancellationToken);

        if (sourceDocument is null)
        {
            return null;
        }

        var pendingRegionCount = await dbContext.SourceRegions
            .AsNoTracking()
            .CountAsync(x => x.SourceDocumentId == sourceDocumentId, cancellationToken);

        var pendingQuestionCount = await dbContext.ReviewQueueItems
            .AsNoTracking()
            .CountAsync(x => x.Status == "open", cancellationToken);

        return new ReviewWorkflowDto(
            sourceDocumentId,
            pendingQuestionCount,
            pendingRegionCount,
            new WorkflowStatusEnvelope(
                WorkflowTypes.Review,
                WorkflowStatuses.PendingReview,
                sourceDocumentId.ToString("N"),
                DateTimeOffset.UtcNow,
                Rollback: null,
                Error: null));
    }
}

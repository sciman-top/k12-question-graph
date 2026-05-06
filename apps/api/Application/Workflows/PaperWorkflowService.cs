using K12QuestionGraph.Api.Application.Workflows.Contracts;
using K12QuestionGraph.Api.Data;
using Microsoft.EntityFrameworkCore;

namespace K12QuestionGraph.Api.Application.Workflows;

public interface IPaperWorkflowService
{
    Task<PaperWorkflowDto> BuildDraftAsync(string requestText, CancellationToken cancellationToken);
}

public sealed class PaperWorkflowService(KqgDbContext dbContext) : IPaperWorkflowService
{
    public async Task<PaperWorkflowDto> BuildDraftAsync(string requestText, CancellationToken cancellationToken)
    {
        var normalized = string.IsNullOrWhiteSpace(requestText) ? "默认组卷请求" : requestText.Trim();

        var questionCount = await dbContext.QuestionItems.AsNoTracking().CountAsync(cancellationToken);
        var useCount = Math.Max(1, Math.Min(questionCount, 10));

        return new PaperWorkflowDto(
            normalized,
            "paper-blueprint-v1",
            useCount,
            useCount * 3,
            new WorkflowStatusEnvelope(
                WorkflowTypes.Paper,
                WorkflowStatuses.PendingReview,
                $"paper:{DateTimeOffset.UtcNow:yyyyMMddHHmmss}",
                DateTimeOffset.UtcNow,
                Rollback: null,
                Error: null));
    }
}

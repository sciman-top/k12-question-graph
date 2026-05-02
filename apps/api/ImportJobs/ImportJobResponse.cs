using K12QuestionGraph.Api.Domain;
using K12QuestionGraph.Api.FileStore;

namespace K12QuestionGraph.Api.ImportJobs;

public sealed record ImportJobResponse(
    Guid Id,
    Guid InputFileAssetId,
    string Status,
    string IdempotencyKey,
    string? LockedBy,
    DateTimeOffset? LockedUntil,
    int AttemptCount,
    int MaxAttempts,
    string? LastErrorCode,
    string? LastErrorMessage,
    DateTimeOffset CreatedAt,
    DateTimeOffset? StartedAt,
    DateTimeOffset? FinishedAt,
    FileAssetResponse? File)
{
    public static ImportJobResponse From(ImportJob job, FileAssetResponse? file = null)
    {
        return new ImportJobResponse(
            job.Id,
            job.InputFileAssetId,
            job.Status,
            job.IdempotencyKey,
            job.LockedBy,
            job.LockedUntil,
            job.AttemptCount,
            job.MaxAttempts,
            job.LastErrorCode,
            job.LastErrorMessage,
            job.CreatedAt,
            job.StartedAt,
            job.FinishedAt,
            file);
    }
}

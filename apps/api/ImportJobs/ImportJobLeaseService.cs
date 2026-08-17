using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using Microsoft.EntityFrameworkCore;

namespace K12QuestionGraph.Api.ImportJobs;

internal sealed record ImportJobLeaseAttempt(bool Acquired, string? LeaseOwner);

internal static class ImportJobLeaseService
{
    private static readonly TimeSpan WorkerLeaseDuration = TimeSpan.FromMinutes(5);

    public static bool CanAcquire(
        string status,
        bool simulateFailure,
        int attemptCount,
        int maxAttempts,
        DateTimeOffset? lockedUntil,
        DateTimeOffset now) =>
        attemptCount < maxAttempts &&
        (!lockedUntil.HasValue || lockedUntil.Value <= now) &&
        (status == JobStatuses.Queued ||
            (!simulateFailure && status is JobStatuses.Running or JobStatuses.Failed or JobStatuses.Succeeded));

    public static async Task<ImportJobLeaseAttempt> TryAcquireAsync(
        KqgDbContext dbContext,
        Guid jobId,
        bool simulateFailure,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var leaseOwner = $"document-worker:{Guid.NewGuid():N}";
        var lockedUntil = now.Add(WorkerLeaseDuration);
        var affected = await dbContext.ImportJobs
            .Where(job =>
                job.Id == jobId &&
                job.AttemptCount < job.MaxAttempts &&
                (!job.LockedUntil.HasValue || job.LockedUntil <= now) &&
                (job.Status == JobStatuses.Queued ||
                    (!simulateFailure &&
                        (job.Status == JobStatuses.Running ||
                            job.Status == JobStatuses.Failed ||
                            job.Status == JobStatuses.Succeeded))))
            .ExecuteUpdateAsync(
                updates => updates
                    .SetProperty(job => job.Status, JobStatuses.Running)
                    .SetProperty(job => job.StartedAt, job => job.StartedAt ?? now)
                    .SetProperty(job => job.FinishedAt, (DateTimeOffset?)null)
                    .SetProperty(job => job.AttemptCount, job => job.AttemptCount + 1)
                    .SetProperty(job => job.LockedBy, leaseOwner)
                    .SetProperty(job => job.LockedUntil, lockedUntil),
                cancellationToken);

        return new ImportJobLeaseAttempt(affected == 1, affected == 1 ? leaseOwner : null);
    }

    public static async Task<bool> RenewForMaterializationAsync(
        KqgDbContext dbContext,
        Guid jobId,
        string leaseOwner,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var affected = await dbContext.ImportJobs
            .Where(job =>
                job.Id == jobId &&
                job.Status == JobStatuses.Running &&
                job.LockedBy == leaseOwner)
            .ExecuteUpdateAsync(
                updates => updates.SetProperty(job => job.LockedUntil, now.Add(WorkerLeaseDuration)),
                cancellationToken);
        return affected == 1;
    }
}

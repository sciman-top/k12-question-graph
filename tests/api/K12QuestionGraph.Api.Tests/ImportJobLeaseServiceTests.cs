using K12QuestionGraph.Api.Domain;
using K12QuestionGraph.Api.ImportJobs;

namespace K12QuestionGraph.Api.Tests;

public class ImportJobLeaseServiceTests
{
    private static readonly DateTimeOffset Now = new(2026, 8, 17, 12, 0, 0, TimeSpan.Zero);

    [Theory]
    [InlineData(JobStatuses.Queued, false, true)]
    [InlineData(JobStatuses.Queued, true, true)]
    [InlineData(JobStatuses.Failed, false, true)]
    [InlineData(JobStatuses.Failed, true, false)]
    [InlineData(JobStatuses.Succeeded, false, true)]
    [InlineData(JobStatuses.Succeeded, true, false)]
    [InlineData(JobStatuses.Running, false, true)]
    [InlineData(JobStatuses.Running, true, false)]
    [InlineData(JobStatuses.Cancelled, false, false)]
    public void CanAcquire_EnforcesSupportedWorkerTransitions(string status, bool simulateFailure, bool expected)
    {
        Assert.Equal(expected, ImportJobLeaseService.CanAcquire(status, simulateFailure, 0, 3, null, Now));
    }

    [Fact]
    public void CanAcquire_RejectsActiveLease()
    {
        Assert.False(ImportJobLeaseService.CanAcquire(
            JobStatuses.Queued,
            simulateFailure: false,
            attemptCount: 0,
            maxAttempts: 3,
            lockedUntil: Now.AddMinutes(1),
            now: Now));
    }

    [Fact]
    public void CanAcquire_RecoversRunningJobOnlyAfterLeaseExpiry()
    {
        Assert.True(ImportJobLeaseService.CanAcquire(
            JobStatuses.Running,
            simulateFailure: false,
            attemptCount: 1,
            maxAttempts: 3,
            lockedUntil: Now.AddSeconds(-1),
            now: Now));
        Assert.False(ImportJobLeaseService.CanAcquire(
            JobStatuses.Running,
            simulateFailure: false,
            attemptCount: 1,
            maxAttempts: 3,
            lockedUntil: Now.AddSeconds(1),
            now: Now));
    }

    [Fact]
    public void CanAcquire_RejectsExhaustedAttempts()
    {
        Assert.False(ImportJobLeaseService.CanAcquire(
            JobStatuses.Queued,
            simulateFailure: false,
            attemptCount: 3,
            maxAttempts: 3,
            lockedUntil: null,
            now: Now));
    }
}

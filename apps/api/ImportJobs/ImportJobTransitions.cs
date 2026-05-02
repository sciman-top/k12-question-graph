using K12QuestionGraph.Api.Domain;

namespace K12QuestionGraph.Api.ImportJobs;

public static class ImportJobTransitions
{
    private static readonly Dictionary<string, string[]> AllowedTransitions = new()
    {
        [JobStatuses.Queued] = [JobStatuses.Running, JobStatuses.Cancelled],
        [JobStatuses.Running] = [JobStatuses.Succeeded, JobStatuses.Failed, JobStatuses.Cancelled, JobStatuses.RetryWaiting],
        [JobStatuses.RetryWaiting] = [JobStatuses.Queued, JobStatuses.Cancelled],
        [JobStatuses.Failed] = [JobStatuses.Queued],
        [JobStatuses.Succeeded] = [],
        [JobStatuses.Cancelled] = []
    };

    public static bool IsAllowed(string from, string to)
    {
        return AllowedTransitions.TryGetValue(from, out var allowed) && allowed.Contains(to);
    }
}

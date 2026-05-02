namespace K12QuestionGraph.Api.ImportJobs;

public sealed record ImportJobStatusUpdate(
    string Status,
    string? LockedBy,
    DateTimeOffset? LockedUntil,
    string? LastErrorCode,
    string? LastErrorMessage);

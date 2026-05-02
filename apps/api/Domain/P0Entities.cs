namespace K12QuestionGraph.Api.Domain;

public static class JobStatuses
{
    public const string Queued = "queued";
    public const string Running = "running";
    public const string Succeeded = "succeeded";
    public const string Failed = "failed";
    public const string Cancelled = "cancelled";
    public const string RetryWaiting = "retry_waiting";
}

public static class ReviewStatuses
{
    public const string Open = "open";
    public const string Resolved = "resolved";
    public const string Dismissed = "dismissed";
}

public static class BackupStatuses
{
    public const string Queued = "queued";
    public const string Running = "running";
    public const string Succeeded = "succeeded";
    public const string Failed = "failed";
}

public static class QuestionStatuses
{
    public const string Draft = "draft";
    public const string PendingReview = "pending_review";
    public const string Usable = "usable";
    public const string Recommended = "recommended";
    public const string NeedsImprovement = "needs_improvement";
    public const string Paused = "paused";
    public const string Retired = "retired";
}

public sealed class TeacherPreference
{
    public Guid Id { get; set; }

    public string TeacherKey { get; set; } = string.Empty;

    public string PreferenceKey { get; set; } = string.Empty;

    public string PreferenceValue { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class FileAsset
{
    public Guid Id { get; set; }

    public string OriginalFileName { get; set; } = string.Empty;

    public string RelativePath { get; set; } = string.Empty;

    public string StorageScope { get; set; } = "original";

    public string ContentType { get; set; } = "application/octet-stream";

    public string Sha256 { get; set; } = string.Empty;

    public long SizeBytes { get; set; }

    public string SourceMetadata { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class ImportJob
{
    public Guid Id { get; set; }

    public Guid InputFileAssetId { get; set; }

    public string Status { get; set; } = JobStatuses.Queued;

    public string IdempotencyKey { get; set; } = string.Empty;

    public string? LockedBy { get; set; }

    public DateTimeOffset? LockedUntil { get; set; }

    public int AttemptCount { get; set; }

    public int MaxAttempts { get; set; } = 3;

    public string? LastErrorCode { get; set; }

    public string? LastErrorMessage { get; set; }

    public string Input { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset? StartedAt { get; set; }

    public DateTimeOffset? FinishedAt { get; set; }
}

public sealed class AIJob
{
    public Guid Id { get; set; }

    public string JobType { get; set; } = string.Empty;

    public string Status { get; set; } = JobStatuses.Queued;

    public string IdempotencyKey { get; set; } = string.Empty;

    public string? ModelRoute { get; set; }

    public string? PromptVersion { get; set; }

    public string? SchemaVersion { get; set; }

    public decimal? EstimatedCost { get; set; }

    public decimal? ActualCost { get; set; }

    public double? Confidence { get; set; }

    public string Input { get; set; } = "{}";

    public string Result { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset? FinishedAt { get; set; }
}

public sealed class ReviewQueueItem
{
    public Guid Id { get; set; }

    public string ReviewType { get; set; } = string.Empty;

    public string Status { get; set; } = ReviewStatuses.Open;

    public string Payload { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset? ResolvedAt { get; set; }
}

public sealed class BackupJob
{
    public Guid Id { get; set; }

    public string Status { get; set; } = BackupStatuses.Queued;

    public string? ManifestPath { get; set; }

    public string? ManifestSha256 { get; set; }

    public string? ErrorMessage { get; set; }

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset? FinishedAt { get; set; }
}

public sealed class QuestionItem
{
    public Guid Id { get; set; }

    public string Subject { get; set; } = "physics";

    public string Stage { get; set; } = "junior_middle_school";

    public string? Grade { get; set; }

    public string? QuestionType { get; set; }

    public decimal? DefaultScore { get; set; }

    public double? DifficultyEstimated { get; set; }

    public double? DifficultyObserved { get; set; }

    public string Status { get; set; } = QuestionStatuses.Draft;

    public Guid? PrimaryKnowledgeId { get; set; }

    public string Blocks { get; set; } = "[]";

    public string CustomFields { get; set; } = "{}";

    public string QualitySignals { get; set; } = "{}";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}

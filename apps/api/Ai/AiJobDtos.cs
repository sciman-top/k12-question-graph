namespace K12QuestionGraph.Api.Ai;

public sealed record AiJobCreateRequest(
    string TaskType,
    string? Mode,
    string? AssetStatus,
    decimal? ExpectedConfidence,
    string InputJson,
    string? IdempotencyKey);

public sealed record AiJobResponse(
    Guid Id,
    string JobType,
    string Status,
    string IdempotencyKey,
    string? ModelRoute,
    string? ModelProvider,
    string? ModelName,
    string? RoutingVersion,
    string? PromptVersion,
    string? SchemaVersion,
    string? InputHash,
    decimal? EstimatedCost,
    decimal? ActualCost,
    double? Confidence,
    int? InputTokens,
    int? OutputTokens,
    int? CachedTokens,
    int? LatencyMs,
    string ReviewStatus,
    bool TeacherModified,
    string Result,
    DateTimeOffset CreatedAt,
    DateTimeOffset? FinishedAt);

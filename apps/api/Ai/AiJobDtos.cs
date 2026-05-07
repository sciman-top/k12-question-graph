namespace K12QuestionGraph.Api.Ai;
using System.Text.Json;

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

public sealed record AiSuggestionConfidence(double Score, double Threshold);

public sealed record AiSuggestionCost(int InputTokens, int OutputTokens, decimal EstimatedUsd);

public sealed record AiSuggestionCache(string CacheKey, bool CacheHit);

public sealed record AiSuggestionEnqueueRequest(
    string SuggestionType,
    Guid SourceDocumentId,
    IReadOnlyList<Guid> SourceRegionIds,
    AiSuggestionConfidence? Confidence,
    AiSuggestionCost? Cost,
    AiSuggestionCache? Cache,
    JsonElement? Payload,
    string? ModelRoute,
    string? PromptVersion,
    string? IdempotencyKey);

public sealed record AiSuggestionEnqueueResponse(
    Guid AiJobId,
    Guid ReviewQueueItemId,
    string ReviewStatus,
    bool TeacherModified,
    DateTimeOffset CreatedAt);

public sealed record AiSuggestionFeedbackRequest(
    string Decision,
    bool TeacherModified,
    string ReviewedBy,
    string Reason);

public sealed record AiSuggestionFeedbackResponse(
    Guid AiJobId,
    string Decision,
    string ReviewStatus,
    bool TeacherModified,
    IReadOnlyList<Guid> ResolvedQueueItemIds,
    DateTimeOffset ResolvedAt);

public sealed record AiSuggestionConfirmRequest(
    string ReviewedBy,
    string Reason,
    string? Subject,
    string? Stage,
    string? Grade,
    string? QuestionType,
    decimal? DefaultScore,
    double? DifficultyEstimated,
    Guid? KnowledgeNodeId,
    decimal? MappingConfidence);

public sealed record AiSuggestionConfirmResponse(
    Guid AiJobId,
    Guid QuestionItemId,
    Guid? KnowledgeMappingId,
    string Status,
    DateTimeOffset ConfirmedAt);

public sealed record AiSuggestionUndoRequest(
    string ReviewedBy,
    string Reason);

public sealed record AiSuggestionUndoResponse(
    Guid AiJobId,
    Guid RemovedQuestionItemId,
    int RemovedKnowledgeMappingCount,
    string Status,
    DateTimeOffset UndoneAt);

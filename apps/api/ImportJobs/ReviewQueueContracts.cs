namespace K12QuestionGraph.Api.ImportJobs;

public sealed record ReviewQueueRevisionRequest(
    string? TextPreview,
    string? Answer,
    string? PrimaryKnowledgeLabel,
    IReadOnlyList<string>? KnowledgeTags);

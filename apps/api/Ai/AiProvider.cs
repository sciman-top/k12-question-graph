namespace K12QuestionGraph.Api.Ai;

public interface IAiProvider
{
    string ProviderId { get; }

    bool SupportsRealModelCalls { get; }

    Task<AiProviderResult> CompleteStructuredAsync(AiProviderRequest request, CancellationToken cancellationToken);
}

public sealed class StubAiProvider : IAiProvider
{
    public string ProviderId => "stub_llm";

    public bool SupportsRealModelCalls => false;

    public Task<AiProviderResult> CompleteStructuredAsync(AiProviderRequest request, CancellationToken cancellationToken)
    {
        var result = new AiProviderResult(
            ProviderId,
            "stub",
            request.PromptVersion,
            request.SchemaVersion,
            "{}",
            0,
            0,
            0,
            0,
            0,
            "pending_review");

        return Task.FromResult(result);
    }
}

public sealed record AiProviderRequest(
    string TaskType,
    string PromptVersion,
    string? SchemaVersion,
    string InputHash,
    string InputJson);

public sealed record AiProviderResult(
    string ProviderId,
    string ModelName,
    string PromptVersion,
    string? SchemaVersion,
    string OutputJson,
    decimal Confidence,
    int InputTokens,
    int OutputTokens,
    int CachedTokens,
    decimal Cost,
    string ReviewStatus);

public sealed record AiProviderInfo(string ProviderId, bool SupportsRealModelCalls);

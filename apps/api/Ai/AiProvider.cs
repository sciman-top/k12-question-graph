namespace K12QuestionGraph.Api.Ai;

using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

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
        var output = JsonSerializer.Serialize(new
        {
            status = "stub",
            taskType = request.TaskType,
            inputHash = request.InputHash,
            requiresHumanReview = true
        });
        var outputTokens = Math.Max(1, output.Length / 4);
        var inputTokens = Math.Max(1, request.InputJson.Length / 4);
        var outputHash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(output))).ToLowerInvariant();
        var result = new AiProviderResult(
            ProviderId,
            "stub",
            request.PromptVersion,
            request.SchemaVersion,
            output,
            0.42m,
            inputTokens,
            outputTokens,
            0,
            0,
            outputHash,
            1,
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
    string OutputHash,
    int LatencyMs,
    string ReviewStatus);

public sealed record AiProviderInfo(string ProviderId, bool SupportsRealModelCalls);

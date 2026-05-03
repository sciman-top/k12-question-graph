using Microsoft.Extensions.Options;

namespace K12QuestionGraph.Api.Ai;

public interface IAiModelRouter
{
    AiRouteDecision Route(AiRouteRequest request);
}

public sealed class AiModelRouter(IOptions<AiRoutingOptions> options, IWebHostEnvironment environment) : IAiModelRouter
{
    private readonly AiRoutingOptions options = options.Value;

    public AiRouteDecision Route(AiRouteRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.TaskType))
        {
            throw new AiRouteException("missing_task_type");
        }

        if (!options.Routes.TryGetValue(request.TaskType, out var route))
        {
            throw new AiRouteException("unknown_task_type");
        }

        var handler = Normalize(route.Handler, "rule");
        var provider = ResolveProvider(handler);
        var mode = Normalize(request.Mode, options.DefaultMode);
        var schemaExists = string.IsNullOrWhiteSpace(route.StructuredOutputSchema) || SchemaExists(route.StructuredOutputSchema);
        var requiresHumanReview = IsLlmHandler(handler) || (route.RequireHumanReviewBelowConfidence.HasValue && request.ExpectedConfidence < route.RequireHumanReviewBelowConfidence.Value);
        var blockers = new List<string>();

        if (!options.AllowRealModelCalls && IsLlmHandler(handler))
        {
            blockers.Add("real_model_calls_disabled");
        }

        if (!string.Equals(request.AssetStatus, "active", StringComparison.OrdinalIgnoreCase))
        {
            blockers.Add("formal_active_domain_asset_required");
        }

        if (!schemaExists)
        {
            blockers.Add("structured_output_schema_missing");
        }

        return new AiRouteDecision(
            Status: "pass",
            RoutingVersion: options.Version,
            TaskType: request.TaskType,
            Mode: mode,
            Handler: handler,
            Provider: provider,
            ModelTier: route.ModelTier,
            PromptVersion: options.PromptVersion,
            SchemaVersion: route.StructuredOutputSchema,
            SchemaExists: schemaExists,
            AllowRealModelCalls: options.AllowRealModelCalls,
            Batchable: route.Batchable,
            RequiresHumanReview: requiresHumanReview,
            ReviewBelowConfidence: route.RequireHumanReviewBelowConfidence,
            ProductionEligible: blockers.Count == 0 && !IsLlmHandler(handler),
            CostTier: ResolveCostTier(handler, route.ModelTier),
            Blockers: blockers);
    }

    private static string ResolveProvider(string handler)
    {
        return IsLlmHandler(handler) ? "stub_llm" : handler;
    }

    private static bool IsLlmHandler(string handler)
    {
        return handler.Contains("llm", StringComparison.OrdinalIgnoreCase);
    }

    private static string ResolveCostTier(string handler, string? modelTier)
    {
        if (!IsLlmHandler(handler))
        {
            return "none";
        }

        return Normalize(modelTier, "medium") switch
        {
            "small" or "small_or_medium" => "low",
            "medium" => "medium",
            "medium_or_strong" or "strong" => "high",
            _ => "medium"
        };
    }

    private bool SchemaExists(string relativePath)
    {
        var repoRoot = Path.GetFullPath(Path.Combine(environment.ContentRootPath, "..", ".."));
        var fullPath = Path.GetFullPath(Path.Combine(repoRoot, relativePath));
        return fullPath.StartsWith(repoRoot, StringComparison.OrdinalIgnoreCase) && File.Exists(fullPath);
    }

    private static string Normalize(string? value, string fallback)
    {
        return string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();
    }
}

public sealed class AiRouteException(string message) : InvalidOperationException(message);

public sealed record AiRouteRequest(
    string TaskType,
    string? Mode,
    string? AssetStatus,
    decimal? ExpectedConfidence);

public sealed record AiRouteDecision(
    string Status,
    string RoutingVersion,
    string TaskType,
    string Mode,
    string Handler,
    string Provider,
    string? ModelTier,
    string PromptVersion,
    string? SchemaVersion,
    bool SchemaExists,
    bool AllowRealModelCalls,
    bool Batchable,
    bool RequiresHumanReview,
    decimal? ReviewBelowConfidence,
    bool ProductionEligible,
    string CostTier,
    IReadOnlyList<string> Blockers);

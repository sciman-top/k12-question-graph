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
        var mode = ResolveMode(request.Mode, options.DefaultMode);
        var modelRole = Normalize(route.ModelRole, IsLlmHandler(handler) ? "bulk_structuring" : "local_deterministic");
        var modelName = Normalize(route.ModelName, IsLlmHandler(handler) ? "stub" : "none");
        var reasoningEffort = Normalize(route.ReasoningEffort, IsLlmHandler(handler) ? "medium" : "none");
        var escalationReasons = ResolveEscalationReasons(request, route, mode, handler);
        var escalated = escalationReasons.Count > 0;
        var effectiveModelRole = escalated ? Normalize(route.EscalateToRole, modelRole) : modelRole;
        var effectiveModelName = escalated ? Normalize(route.EscalateToModel, modelName) : modelName;
        var effectiveReasoningEffort = escalated ? Normalize(route.EscalateReasoningEffort, reasoningEffort) : reasoningEffort;
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
            Stage: Normalize(route.Stage, "unspecified"),
            ModelRole: modelRole,
            ModelName: modelName,
            ReasoningEffort: reasoningEffort,
            EffectiveModelRole: effectiveModelRole,
            EffectiveModelName: effectiveModelName,
            EffectiveReasoningEffort: effectiveReasoningEffort,
            Escalated: escalated,
            EscalationReasons: escalationReasons,
            ModelTier: route.ModelTier,
            EscalateToRole: route.EscalateToRole,
            EscalateToModel: route.EscalateToModel,
            EscalateReasoningEffort: route.EscalateReasoningEffort,
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

    private static IReadOnlyList<string> ResolveEscalationReasons(
        AiRouteRequest request,
        AiRouteOptions route,
        string mode,
        string handler)
    {
        if (!IsLlmHandler(handler)
            || string.IsNullOrWhiteSpace(route.EscalateToModel)
            || string.IsNullOrWhiteSpace(route.EscalateReasoningEffort))
        {
            return [];
        }

        var allowedSignals = route.EscalationSignals.ToHashSet(StringComparer.OrdinalIgnoreCase);
        var reasons = (request.RiskSignals?.ActiveReasons() ?? [])
            .Where(allowedSignals.Contains)
            .ToArray();
        if (string.Equals(mode, "low_cost", StringComparison.OrdinalIgnoreCase))
        {
            return reasons;
        }

        var result = new List<string>(reasons);
        if (route.RequireHumanReviewBelowConfidence.HasValue
            && request.ExpectedConfidence.HasValue
            && request.ExpectedConfidence.Value < route.RequireHumanReviewBelowConfidence.Value)
        {
            result.Add("low_confidence");
        }

        if (string.Equals(mode, "high_accuracy", StringComparison.OrdinalIgnoreCase)
            && route.EscalateInHighAccuracy)
        {
            result.Add("high_accuracy_mode");
        }

        return result.Distinct(StringComparer.Ordinal).ToArray();
    }

    private static string ResolveProvider(string handler)
    {
        return IsLlmHandler(handler) ? "stub_llm" : handler;
    }

    private static string ResolveMode(string? requestedMode, string defaultMode)
    {
        var mode = Normalize(requestedMode, defaultMode).ToLowerInvariant();
        return mode is "low_cost" or "balanced" or "high_accuracy"
            ? mode
            : throw new AiRouteException("unknown_routing_mode");
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
    decimal? ExpectedConfidence,
    AiRouteRiskSignals? RiskSignals = null);

public sealed record AiRouteRiskSignals(
    bool CrossPage = false,
    bool SharedVisual = false,
    bool FormulaOrTable = false,
    bool SemanticConflict = false,
    bool MultipleConstraints = false,
    bool FormalExam = false,
    bool SourceEvidenceConflict = false)
{
    public IReadOnlyList<string> ActiveReasons()
    {
        var reasons = new List<string>();
        if (CrossPage) reasons.Add("cross_page");
        if (SharedVisual) reasons.Add("shared_visual");
        if (FormulaOrTable) reasons.Add("formula_or_table");
        if (SemanticConflict) reasons.Add("semantic_conflict");
        if (MultipleConstraints) reasons.Add("multiple_constraints");
        if (FormalExam) reasons.Add("formal_exam");
        if (SourceEvidenceConflict) reasons.Add("source_evidence_conflict");
        return reasons;
    }
}

public sealed record AiRouteDecision(
    string Status,
    string RoutingVersion,
    string TaskType,
    string Mode,
    string Handler,
    string Provider,
    string Stage,
    string ModelRole,
    string ModelName,
    string ReasoningEffort,
    string EffectiveModelRole,
    string EffectiveModelName,
    string EffectiveReasoningEffort,
    bool Escalated,
    IReadOnlyList<string> EscalationReasons,
    string? ModelTier,
    string? EscalateToRole,
    string? EscalateToModel,
    string? EscalateReasoningEffort,
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

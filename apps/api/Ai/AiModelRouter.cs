using Microsoft.Extensions.Options;

namespace K12QuestionGraph.Api.Ai;

public sealed class AiModelRouter(IOptions<AiRoutingOptions> options, IWebHostEnvironment environment)
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
        var executionSlot = ResolveExecutionSlot(route.ExecutionSlot, modelRole);
        var executionGrade = ResolveExecutionGrade(request.ExecutionGrade, route.ExecutionGrade, executionSlot, mode);
        var initialSelection = IsLlmHandler(handler)
            ? ResolveModelSelection(
                executionSlot,
                executionGrade,
                modelRole,
                modelName,
                reasoningEffort)
            : new AiModelSelection("", modelName, reasoningEffort);
        modelName = initialSelection.ModelName;
        reasoningEffort = initialSelection.ReasoningEffort;
        var escalationReasons = ResolveEscalationReasons(request, route, mode, handler);
        var escalated = escalationReasons.Count > 0;
        var effectiveModelRole = escalated ? Normalize(route.EscalateToRole, modelRole) : modelRole;
        var effectiveExecutionSlot = escalated
            ? ResolveExecutionSlot(route.EscalateToExecutionSlot, effectiveModelRole, executionSlot)
            : executionSlot;
        var effectiveExecutionGrade = escalated
            ? ResolveExecutionGrade(route.EscalateToExecutionGrade, executionGrade, effectiveExecutionSlot, mode)
            : executionGrade;
        var effectiveSelection = escalated
            ? ResolveModelSelection(
                effectiveExecutionSlot,
                effectiveExecutionGrade,
                effectiveModelRole,
                Normalize(route.EscalateToModel, modelName),
                Normalize(route.EscalateReasoningEffort, reasoningEffort))
            : initialSelection;
        var effectiveModelName = effectiveSelection.ModelName;
        var effectiveReasoningEffort = effectiveSelection.ReasoningEffort;
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
            ExecutionSlot: executionSlot,
            ExecutionGrade: executionGrade,
            Preset: initialSelection.PresetId,
            ModelRole: modelRole,
            ModelName: modelName,
            ReasoningEffort: reasoningEffort,
            EffectiveModelRole: effectiveModelRole,
            EffectiveModelName: effectiveModelName,
            EffectiveReasoningEffort: effectiveReasoningEffort,
            EffectiveExecutionSlot: effectiveExecutionSlot,
            EffectiveExecutionGrade: effectiveExecutionGrade,
            EffectivePreset: effectiveSelection.PresetId,
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

    public IReadOnlyList<AiModelFailoverCandidate> GetFailoverCandidates(
        string modelName,
        string reasoningEffort,
        string? executionSlot = null,
        string? executionGrade = null)
    {
        var normalizedModelName = Normalize(modelName, "stub");
        var normalizedReasoningEffort = Normalize(reasoningEffort, "medium");
        var normalizedExecutionSlot = Normalize(executionSlot, "");
        var normalizedExecutionGrade = Normalize(executionGrade, "");
        if (!options.ModelFailover.Enabled || options.ModelPresets.Count == 0)
        {
            return [new("manual", normalizedModelName, normalizedReasoningEffort, false, normalizedExecutionSlot, normalizedExecutionGrade)];
        }

        var requestedPreset = options.ModelPresets.FirstOrDefault(pair =>
            string.Equals(pair.Key, normalizedModelName, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(pair.Value.ModelName, normalizedModelName, StringComparison.OrdinalIgnoreCase));
        if (string.IsNullOrWhiteSpace(requestedPreset.Key))
        {
            return [new("manual", normalizedModelName, normalizedReasoningEffort, false, normalizedExecutionSlot, normalizedExecutionGrade)];
        }

        var orderedPresetIds = new[] { requestedPreset.Key }
            .Concat(options.ModelFailover.PreferredPresetOrder)
            .Where(x => !string.IsNullOrWhiteSpace(x) && options.ModelPresets.ContainsKey(x))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

        var candidates = new List<AiModelFailoverCandidate>(orderedPresetIds.Length);
        foreach (var presetId in orderedPresetIds)
        {
            var preset = options.ModelPresets[presetId];
            if (string.IsNullOrWhiteSpace(preset.ModelName))
            {
                continue;
            }

            var candidateEffort = ResolveSupportedReasoningEffort(
                preset,
                normalizedReasoningEffort,
                normalizedExecutionGrade);
            candidates.Add(new AiModelFailoverCandidate(
                PresetId: presetId,
                ModelName: preset.ModelName.Trim(),
                ReasoningEffort: candidateEffort,
                IsFallback: !string.Equals(presetId, requestedPreset.Key, StringComparison.OrdinalIgnoreCase),
                ExecutionSlot: normalizedExecutionSlot,
                ExecutionGrade: normalizedExecutionGrade));
        }

        return candidates.Count > 0
            ? candidates
            : [new("manual", normalizedModelName, normalizedReasoningEffort, false, normalizedExecutionSlot, normalizedExecutionGrade)];
    }

    public string ModelAvailabilityProbePath => NormalizeProbePath(options.ModelFailover.AvailabilityProbePath);

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

    private static string ResolveSupportedReasoningEffort(
        AiModelPresetOptions preset,
        string requestedReasoningEffort,
        string? executionGrade = null)
    {
        if (!string.IsNullOrWhiteSpace(executionGrade)
            && preset.GradeToReasoningEffort.TryGetValue(executionGrade.Trim(), out var gradeEffort)
            && !string.IsNullOrWhiteSpace(gradeEffort))
        {
            return gradeEffort.Trim();
        }

        var supported = preset.ReasoningEfforts
            .Where(x => !string.IsNullOrWhiteSpace(x))
            .Select(x => x.Trim())
            .ToArray();
        var exact = supported.FirstOrDefault(x => string.Equals(x, requestedReasoningEffort, StringComparison.OrdinalIgnoreCase));
        if (!string.IsNullOrWhiteSpace(exact))
        {
            return exact;
        }

        var fallback = supported.FirstOrDefault(x => string.Equals(x, preset.FallbackReasoningEffort, StringComparison.OrdinalIgnoreCase));
        return fallback ?? supported.FirstOrDefault() ?? requestedReasoningEffort;
    }

    private string ResolveExecutionSlot(string? configuredSlot, string modelRole, string? fallback = null)
    {
        if (!string.IsNullOrWhiteSpace(configuredSlot))
        {
            return configuredSlot.Trim();
        }

        return modelRole.ToLowerInvariant() switch
        {
            "mechanical_cleanup_model" or "local_deterministic" => "mechanical_cleanup",
            "bulk_prefilter_model" or "bulk_structuring" => "bulk_prefilter",
            "engineering_review_model" or "general_semantics" => "engineering_review",
            "visual_review_model" or "visual_document" => "visual_review",
            "high_risk_review_model" or "highest_risk_decision_model" or "semantic_decision" => "high_risk_adjudication",
            _ => Normalize(fallback, "engineering_review")
        };
    }

    private string ResolveExecutionGrade(string? requestedGrade, string? configuredGrade, string executionSlot, string mode)
    {
        var defaultGrade = options.ExecutionSlots.TryGetValue(executionSlot, out var slot)
            ? slot.DefaultGrade
            : mode switch
            {
                "low_cost" => "economy",
                "high_accuracy" => "quality",
                _ => "balanced"
            };
        var grade = Normalize(requestedGrade, Normalize(configuredGrade, defaultGrade));
        return grade.ToLowerInvariant() switch
        {
            "economy" or "balanced" or "quality" => grade.ToLowerInvariant(),
            _ => throw new AiRouteException("unknown_execution_grade")
        };
    }

    private AiModelSelection ResolveModelSelection(
        string executionSlot,
        string executionGrade,
        string modelRole,
        string modelName,
        string reasoningEffort)
    {
        // Execution slots select a grade only. The active preset selects the
        // model for every slot, so a Sol-only/Terra-only/Luna-only preset can
        // never be mixed by a slot-specific model binding.
        var presetId = options.ModelFailover.PreferredPresetOrder
            .FirstOrDefault(id => !string.IsNullOrWhiteSpace(id) && options.ModelPresets.ContainsKey(id));
        presetId ??= options.ModelPresets.Keys.FirstOrDefault();
        if (!string.IsNullOrWhiteSpace(presetId)
            && options.ModelPresets.TryGetValue(presetId, out var preset)
            && !string.IsNullOrWhiteSpace(preset.ModelName))
        {
            return new AiModelSelection(
                presetId,
                preset.ModelName.Trim(),
                ResolveSupportedReasoningEffort(preset, reasoningEffort, executionGrade));
        }

        return new AiModelSelection("", Normalize(modelName, "stub"), Normalize(reasoningEffort, "medium"));
    }

    private sealed record AiModelSelection(string PresetId, string ModelName, string ReasoningEffort);

    private static string NormalizeProbePath(string? value)
    {
        var normalized = Normalize(value, "/models");
        return normalized.StartsWith("/", StringComparison.Ordinal) ? normalized : $"/{normalized}";
    }
}

public sealed class AiRouteException(string message) : InvalidOperationException(message);

public sealed record AiRouteRequest(
    string TaskType,
    string? Mode,
    string? AssetStatus,
    decimal? ExpectedConfidence,
    AiRouteRiskSignals? RiskSignals = null,
    string? ExecutionGrade = null);

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
    string ExecutionSlot,
    string ExecutionGrade,
    string Preset,
    string ModelRole,
    string ModelName,
    string ReasoningEffort,
    string EffectiveModelRole,
    string EffectiveModelName,
    string EffectiveReasoningEffort,
    string EffectiveExecutionSlot,
    string EffectiveExecutionGrade,
    string EffectivePreset,
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

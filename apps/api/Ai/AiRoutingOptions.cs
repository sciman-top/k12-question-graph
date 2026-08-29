namespace K12QuestionGraph.Api.Ai;

public sealed class AiRoutingOptions
{
    public string Version { get; set; } = "d001.business-task-routing.v3";

    public bool AllowRealModelCalls { get; set; }

    public string DefaultMode { get; set; } = "balanced";

    public string PromptVersion { get; set; } = "prompt.d001.draft-test.v1";

    public Dictionary<string, AiRouteOptions> Routes { get; set; } = new(StringComparer.OrdinalIgnoreCase);

    public Dictionary<string, AiModelPresetOptions> ModelPresets { get; set; } = new(StringComparer.OrdinalIgnoreCase);

    public Dictionary<string, AiExecutionSlotOptions> ExecutionSlots { get; set; } = new(StringComparer.OrdinalIgnoreCase);

    public AiModelFailoverOptions ModelFailover { get; set; } = new();
}

public sealed class AiRouteOptions
{
    public string Handler { get; set; } = "rule";

    public string? Stage { get; set; }

    public string? ModelRole { get; set; }

    public string? ModelName { get; set; }

    public string? ReasoningEffort { get; set; }

    public string? ModelTier { get; set; }

    public string? ExecutionSlot { get; set; }

    public string? ExecutionGrade { get; set; }

    public string? EscalateToRole { get; set; }

    public string? EscalateToModel { get; set; }

    public string? EscalateReasoningEffort { get; set; }

    public string? EscalateToExecutionSlot { get; set; }

    public string? EscalateToExecutionGrade { get; set; }

    public string? StructuredOutputSchema { get; set; }

    public decimal? RequireHumanReviewBelowConfidence { get; set; }

    public bool Batchable { get; set; }

    public bool EscalateInHighAccuracy { get; set; }

    public string[] EscalationSignals { get; set; } = [];
}

public sealed class AiModelPresetOptions
{
    public string ModelName { get; set; } = string.Empty;

    public string[] ReasoningEfforts { get; set; } = [];

    public Dictionary<string, string> GradeToReasoningEffort { get; set; } = new(StringComparer.OrdinalIgnoreCase);

    public string FallbackReasoningEffort { get; set; } = "medium";
}

public sealed class AiExecutionSlotOptions
{
    public string Description { get; set; } = string.Empty;

    public string DefaultGrade { get; set; } = "balanced";
}

public sealed class AiModelFailoverOptions
{
    public bool Enabled { get; set; } = true;

    public string[] PreferredPresetOrder { get; set; } = ["sol", "terra", "luna"];

    public string? PinnedPresetId { get; set; }

    public string AvailabilityProbePath { get; set; } = "/models";

    public int FailureCooldownSeconds { get; set; } = 30;
}

public sealed record AiModelFailoverCandidate(
    string PresetId,
    string ModelName,
    string ReasoningEffort,
    bool IsFallback,
    string ExecutionSlot = "",
    string ExecutionGrade = "");

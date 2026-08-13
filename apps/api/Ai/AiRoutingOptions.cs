namespace K12QuestionGraph.Api.Ai;

public sealed class AiRoutingOptions
{
    public string Version { get; set; } = "d001.business-task-routing.v3";

    public bool AllowRealModelCalls { get; set; }

    public string DefaultMode { get; set; } = "balanced";

    public string PromptVersion { get; set; } = "prompt.d001.draft-test.v1";

    public Dictionary<string, AiRouteOptions> Routes { get; set; } = new(StringComparer.OrdinalIgnoreCase);
}

public sealed class AiRouteOptions
{
    public string Handler { get; set; } = "rule";

    public string? Stage { get; set; }

    public string? ModelRole { get; set; }

    public string? ModelName { get; set; }

    public string? ReasoningEffort { get; set; }

    public string? ModelTier { get; set; }

    public string? EscalateToRole { get; set; }

    public string? EscalateToModel { get; set; }

    public string? EscalateReasoningEffort { get; set; }

    public string? StructuredOutputSchema { get; set; }

    public decimal? RequireHumanReviewBelowConfidence { get; set; }

    public bool Batchable { get; set; }

    public bool EscalateInHighAccuracy { get; set; }

    public string[] EscalationSignals { get; set; } = [];
}

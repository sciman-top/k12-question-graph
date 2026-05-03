namespace K12QuestionGraph.Api.Ai;

public sealed class AiRoutingOptions
{
    public string Version { get; set; } = "d001.draft-test.v1";

    public bool AllowRealModelCalls { get; set; }

    public string DefaultMode { get; set; } = "balanced";

    public string PromptVersion { get; set; } = "prompt.d001.draft-test.v1";

    public Dictionary<string, AiRouteOptions> Routes { get; set; } = new(StringComparer.OrdinalIgnoreCase);
}

public sealed class AiRouteOptions
{
    public string Handler { get; set; } = "rule";

    public string? ModelTier { get; set; }

    public string? StructuredOutputSchema { get; set; }

    public decimal? RequireHumanReviewBelowConfidence { get; set; }

    public bool Batchable { get; set; }
}
